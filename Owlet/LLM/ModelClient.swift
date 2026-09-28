import Foundation

enum ModelError: Error, Equatable {
    case network(String)
    case unauthorized
    case http(Int)
    case emptyResponse
    case format
    case truncated
    case refused

    var message: String {
        switch self {
        case .network(let detail): "Network error: \(detail)"
        case .unauthorized: "Authentication failed. Check the API key."
        case .http(let code): "Service returned HTTP \(code)."
        case .emptyResponse: "The service returned an empty response."
        case .format: "The response did not match the required format."
        case .truncated: "The result was too long and got truncated."
        case .refused: "The service refused to process this text."
        }
    }
}

typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

struct ModelClient: Sendable {
    var transport: Transport = { try await URLSession.shared.data(for: $0) }
    /// Resolves the behavior prompt for an operation, so a saved custom prompt reaches assembly while
    /// a test can substitute a hostile one; the fixed contract is appended by `makeRequest` either way.
    var promptForOperation: @Sendable (Operation) -> String = { SettingsStore.prompt(for: $0) }

    func translate(_ text: String, to targetLanguage: String, config: ServiceConfig)
        async throws -> String
    {
        try await process(text, operation: .translate, to: targetLanguage, config: config)
    }

    /// `targetLanguage` is ignored for polish, whose result must stay in the source language.
    func process(
        _ text: String, operation: Operation, to targetLanguage: String, config: ServiceConfig
    ) async throws -> String {
        try await processResult(text, operation: operation, to: targetLanguage, config: config).text
    }

    /// Returns the whole validated result so a caller can also read the source and target languages
    /// of a collected expression.
    func processResult(
        _ text: String, operation: Operation, to targetLanguage: String, config: ServiceConfig
    ) async throws -> TranslationResult {
        let target = operation == .translate ? targetLanguage : nil
        let request = try makeRequest(
            text: text, operation: operation, targetLanguage: target, config: config)
        let data = try await send(request)
        let content = try decodedContent(data)
        return try TranslationResult.parse(
            content, submitted: text, targetLanguage: target)
    }

    /// Fills in a Chinese meaning for one collected expression through the learning contract; the
    /// caller keeps the saved entry when this throws so the user can retry.
    func fillMeaning(
        expression: String, language: String, context: String, config: ServiceConfig
    ) async throws -> String {
        var request = URLRequest(url: config.baseURL.appending(path: "chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        let task = """
            为下面这条语言学习条目给出简体中文释义。释义要说明含义和用法，保留必要的语域说明，\
            不添加原文没有的信息。
            """
        let system = """
            \(task)

            Respond with one json object with key items (array of {text, language, kind, meaning, context}). \
            kind is one of word, phrase, sentence. text must appear in context. Example json: \
            {"items":[{"text":"follow up","language":"en","kind":"phrase",\
            "meaning":"跟进，后续联系。","context":"..."}]}
            """
        let responseFormat: [String: Any] =
            !config.provider.supportsJSONSchema
            ? ["type": "json_object"]
            : [
                "type": "json_schema",
                "json_schema": [
                    "name": "meaning", "strict": true,
                    "schema": LearningResult.providerSchema,
                ],
            ]
        let payload = try JSONSerialization.data(withJSONObject: [
            "expression": expression, "language": language, "context": context,
        ])
        let body = requestBody(
            messages: [
                ["role": "system", "content": system],
                ["role": "user", "content": String(decoding: payload, as: UTF8.self)],
            ], responseFormat: responseFormat, config: config)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data = try await send(request)
        return try LearningResult.item(try decodedContent(data), expression: expression).meaning
    }

    /// Runs the optional learning request as its own call, so a failure here can only ever affect the
    /// learning area and never the main result the caller already has.
    func learning(
        text: String, operation: Operation, targetLanguage: String, result: String,
        config: ServiceConfig
    ) async throws -> [LearningResult.Item] {
        let request = try makeLearningRequest(
            text: text, operation: operation, targetLanguage: targetLanguage, result: result,
            config: config)
        let data = try await send(request)
        return try LearningResult.parse(try decodedContent(data))
    }

    /// Builds the separate learning request: the same behavior prompt as the main request plus the
    /// learning task and the `$defs.learning` contract, with the original and result as data.
    func makeLearningRequest(
        text: String, operation: Operation, targetLanguage: String, result: String,
        config: ServiceConfig
    ) throws -> URLRequest {
        var request = URLRequest(url: config.baseURL.appending(path: "chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        let task =
            operation == .polish
            ? "从这次润色的原文与结果中挑选值得学习的表达，用简体中文解释修改的原因，并区分语法错误与风格偏好。"
            : "从这次翻译的原文与结果中挑选值得学习的词汇、搭配或句式，用简体中文解释含义与用法。"
        let system = """
            \(promptForOperation(operation))

            \(task)不强凑条目，没有值得推荐的内容时 items 为空数组。
            Respond with one json object with key items (array of {text, language, kind, meaning, context}). \
            kind is one of word, phrase, sentence. meaning is Simplified Chinese. context must come from \
            the original or the result, and text must appear in context. Example json: \
            {"items":[{"text":"take a step back","language":"en","kind":"phrase",\
            "meaning":"退一步重新审视。","context":"Let's take a step back."}]}
            """
        let responseFormat: [String: Any] =
            !config.provider.supportsJSONSchema
            ? ["type": "json_object"]
            : [
                "type": "json_schema",
                "json_schema": [
                    "name": "learning", "strict": true,
                    "schema": LearningResult.providerSchema,
                ],
            ]
        let payload = try JSONSerialization.data(withJSONObject: [
            "original": text, "result": result,
        ])
        let body = requestBody(
            messages: [
                ["role": "system", "content": system],
                ["role": "user", "content": String(decoding: payload, as: UTF8.self)],
            ], responseFormat: responseFormat, config: config)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Lists model ids from the OpenAI-style `GET /models` endpoint.
    func listModels(baseURL: URL, apiKey: String) async throws -> [String] {
        var request = URLRequest(url: baseURL.appending(path: "models"))
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let data = try await send(request)
        guard let list = try? JSONDecoder().decode(ModelList.self, from: data) else {
            throw ModelError.format
        }
        return list.data.map(\.id)
    }

    /// Decodes the provider envelope and applies the shared truncation and content-policy rules
    /// before any contract parsing, so every request type fails the same way.
    private func decodedContent(_ data: Data) throws -> String {
        let choice = (try? JSONDecoder().decode(ChatResponse.self, from: data))?.choices.first
        if choice?.finishReason == "length" { throw ModelError.truncated }
        if choice?.finishReason == "content_filter" || choice?.message.refusal?.isEmpty == false {
            throw ModelError.refused
        }
        guard let content = choice?.message.content,
            !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw ModelError.emptyResponse }
        return content
    }

    /// The shared chat body: model, messages and response format, plus the reasoning effort only when
    /// the user chose one, so a provider that rejects the field is left untouched by the default.
    private func requestBody(
        messages: [[String: Any]], responseFormat: [String: Any], config: ServiceConfig
    ) -> [String: Any] {
        var body: [String: Any] = [
            "model": config.model,
            "messages": messages,
            "response_format": responseFormat,
        ]
        if let value = ModelEffort.reasoningEffort(for: config.effort, model: config.model) {
            body["reasoning_effort"] = value
        }
        return body
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport(request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw ModelError.network(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 401 || http.statusCode == 403 { throw ModelError.unauthorized }
            if !(200..<300).contains(http.statusCode) { throw ModelError.http(http.statusCode) }
        }
        return data
    }

    func makeRequest(
        text: String, operation: Operation = .translate, targetLanguage: String?,
        config: ServiceConfig
    ) throws -> URLRequest {
        var request = URLRequest(url: config.baseURL.appending(path: "chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        let task =
            targetLanguage.map { "Operation: translate. Target language: \($0)." }
            ?? "Operation: polish. target_language must equal source_language."
        let system = """
            \(promptForOperation(operation))

            \(task)
            Respond with one json object with keys source_language, target_language and segments \
            (array of {source, target}). Concatenated sources must equal the user message exactly.
            Example json: {"source_language":"en","target_language":"zh-Hans",\
            "segments":[{"source":"...","target":"..."}]}
            """
        // Without schema support the prompt above must mention "json" and spell out the shape.
        let responseFormat: [String: Any] =
            !config.provider.supportsJSONSchema
            ? ["type": "json_object"]
            : [
                "type": "json_schema",
                "json_schema": [
                    "name": operation == .translate ? "translation" : "polish", "strict": true,
                    "schema": TranslationResult.providerSchema,
                ],
            ]
        let body = requestBody(
            messages: [
                ["role": "system", "content": system], ["role": "user", "content": text],
            ], responseFormat: responseFormat, config: config)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
}

struct ChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            var content: String?
            var refusal: String?
        }
        var message: Message
        var finishReason: String?

        enum CodingKeys: String, CodingKey {
            case message
            case finishReason = "finish_reason"
        }
    }
    var choices: [Choice]
}

struct ModelList: Decodable {
    struct Model: Decodable { var id: String }
    var data: [Model]
}
