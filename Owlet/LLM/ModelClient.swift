import Foundation

enum ModelError: Error, Equatable {
    case network(String)
    case unauthorized
    case http(Int)
    case emptyResponse
    /// The returned JSON does not have the agreed shape: a missing or extra field, a wrong type, a
    /// blank segment, or text outside one code fence.
    case format
    /// The returned source text does not reassemble into what was submitted, so the pairing cannot
    /// be trusted even though the JSON itself was well formed.
    case sourceMismatch
    /// The model answered in another language than the one requested.
    case targetMismatch(requested: String, returned: String)
    case truncated
    case refused

    /// A failure reaches the user as its message, and that is all the panel keeps: the kind above
    /// decides what it means, this decides how it reads.
    var message: String {
        switch self {
        case .network(let detail):
            L10n.shared.string("Network error: %@", detail)
        case .unauthorized: L10n.shared.string("Authentication failed. Check the API key.")
        case .http(let code): L10n.shared.string("The service returned HTTP %lld.", code)
        case .emptyResponse: L10n.shared.string("The service returned empty content.")
        case .format:
            L10n.shared.string(
                "The reply does not match the agreed structure: a missing field, a wrong type, or empty content."
            )
        case .sourceMismatch:
            L10n.shared.string(
                "The returned source does not reassemble into what was submitted, so the pairing cannot be trusted."
            )
        case .targetMismatch(let requested, let returned):
            L10n.shared.string(
                "The reply is in %@, which does not match the requested %@.", returned, requested)
        case .truncated: L10n.shared.string("The result was cut off for being too long.")
        case .refused: L10n.shared.string("The service refused to process this text.")
        }
    }

    /// What a failure means for the user. Classification is a property of the error, never of its
    /// wording: a translated message must not decide whether the way out is the prompt editor or the
    /// service settings, nor whether the problem is the connection.
    enum Kind: Equatable {
        /// A prompt edit can address it: the reply broke the contract.
        case contract
        /// Reaching the service failed: network, credentials or HTTP status.
        case connection
        /// The service answered, but the answer is unusable.
        case service
    }

    var kind: Kind {
        switch self {
        case .format, .sourceMismatch, .targetMismatch: .contract
        case .network, .unauthorized, .http: .connection
        case .emptyResponse, .truncated, .refused: .service
        }
    }
}

typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

/// A contract failure together with the model content that produced it, so a caller can show the model
/// what it must fix instead of asking again from scratch.
struct ContractError: Error {
    let error: Error
    let content: String
}

extension ModelClient {
    /// Whether a failure is worth one corrective round. A structure the app cannot read, a pairing that
    /// does not reassemble, or an explanation in the wrong language all describe something the model got
    /// wrong and can be told about. Truncation, refusal, an empty answer and transport failures cannot.
    static func isCorrectable(_ error: ModelError) -> Bool {
        switch error {
        case .format, .sourceMismatch, .targetMismatch: true
        case .network, .unauthorized, .http, .emptyResponse, .truncated, .refused: false
        }
    }

    func isCorrectable(_ error: ModelError) -> Bool { Self.isCorrectable(error) }
}

struct ModelClient: Sendable {
    var transport: Transport = { try await URLSession.shared.data(for: $0) }
    /// Resolves the behavior prompt for an operation, so a saved custom prompt reaches assembly while
    /// a test can substitute a hostile one; the fixed contract is appended by `makeRequest` either way.
    var promptForOperation: @Sendable (Operation) -> String = { SettingsStore.prompt(for: $0) }
    /// Where a finished exchange goes for the debug page; off by default so ordinary use never keeps
    /// the user's text.
    var capture: DebugCapture = .live

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
        return try await perform(
            request, title: Self.debugTitle(operation: operation, target: target), submitted: text,
            parse: { try TranslationResult.parse($0, submitted: text, targetLanguage: target) })
    }

    /// Names what was asked for, so a debug entry reads without opening it.
    static func debugTitle(operation: Operation, target: String?) -> String {
        let name = operation.name
        return target.map { "\(name) · \($0)" } ?? name
    }

    /// The body as sent, so the debug page shows the real request instead of a reconstruction. The
    /// API key is a header, so it is not included.
    static func prettyPrintedBody(_ request: URLRequest) -> String {
        guard let body = request.httpBody,
            let object = try? JSONSerialization.jsonObject(with: body),
            let pretty = try? JSONSerialization.data(
                withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
            let text = String(data: pretty, encoding: .utf8)
        else { return "(the request body is unreadable)" }
        return text
    }

    /// Fills in a meaning for one collected expression through the learning contract, in the language
    /// that entry is explained in (BDR-0005); the caller keeps the saved entry when this throws so the
    /// user can retry.
    func fillMeaning(
        expression: String, language: String, context: String, definitionLocale: String,
        config: ServiceConfig
    ) async throws -> String {
        var request = URLRequest(url: config.baseURL.appending(path: "chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        let task = ModelPrompts.format(
            "fillMeaningTask", LanguageCatalog.name(for: definitionLocale))
        // The prompt text lives in ModelPrompts.json; `"\n"` keeps the blank line and the indent the
        // literal used to carry, so the model receives the same bytes.
        var system = task + "\n\n"
        system += "            " + ModelPrompts["fillMeaningShape"] + "\n"
        system +=
            "            "
            + ModelPrompts.format(
                "fillMeaningFields", LanguageCatalog.name(for: definitionLocale)) + "\n"
        system += "            " + ModelPrompts["fillMeaningExample"] + "\n"
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
        return try await perform(
            request, title: L10n.shared.string("Fill In Meaning"), submitted: expression,
            parse: { try LearningResult.item($0, expression: expression).meaning })
    }

    /// Runs the optional learning request as its own call, so a failure here can only ever affect the
    /// learning area and never the main result the caller already has.
    ///
    /// A reply this app cannot accept buys one corrective round: the model is shown its own answer and
    /// which rule it broke, which is far more reliable than re-sending the same prompt and hoping. Only
    /// one round, so a model that cannot follow the contract still fails exactly where it did.
    func learning(
        text: String, operation: Operation, targetLanguage: String, result: String,
        config: ServiceConfig
    ) async throws -> [LearningResult.Item] {
        let request = try makeLearningRequest(
            text: text, operation: operation, targetLanguage: targetLanguage, result: result,
            config: config)
        switch try await attempt(request, title: L10n.shared.string("Study Expressions"), submitted: text) {
        case .success(let items):
            return items
        case .failure(let error):
            // Only a reply that arrived but broke the contract is worth correcting; truncation,
            // refusal, an empty answer and every transport failure stand as they are.
            guard let asModelError = error.error as? ModelError,
                isCorrectable(asModelError)
            else { throw error.error }
            // A reply with no JSON in it names no rule to follow, so it gets no second round.
            let reasons = LearningResult.diagnose(error.content)
            guard !reasons.isEmpty else { throw error.error }
            let correction = try makeLearningRequest(
                text: text, operation: operation, targetLanguage: targetLanguage, result: result,
                config: config, correcting: error.content, reasons: reasons)
            switch try await attempt(
                correction, title: L10n.shared.string("Study Expressions (corrected)"), submitted: text)
            {
            case .success(let items): return items
            case .failure(let retried): throw retried.error
            }
        }
    }

    /// Sends one request and parses it; the parse failure carries the content back, because the
    /// corrective round has to show the model the reply it must fix. Everything else throws.
    private func attempt(
        _ request: URLRequest, title: String, submitted: String
    ) async throws -> Result<[LearningResult.Item], ContractError> {
        try await perform(request, title: title, submitted: submitted) {
            (content: String) -> Result<[LearningResult.Item], ContractError> in
            do {
                return .success(try LearningResult.parse(content))
            } catch {
                return .failure(ContractError(error: error, content: content))
            }
        }
    }

    /// Builds the separate learning request: the same behavior prompt as the main request plus the
    /// learning task and the `$defs.learning` contract, with the original and result as data.
    ///
    /// With `correcting`, the same contract comes after the model's own rejected reply and the rules
    /// it broke, so the one thing that changes between the two requests is the model's own output.
    func makeLearningRequest(
        text: String, operation: Operation, targetLanguage: String, result: String,
        config: ServiceConfig, correcting reply: String? = nil, reasons: [String] = []
    ) throws -> URLRequest {
        var request = URLRequest(url: config.baseURL.appending(path: "chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        let meaningLanguage = LanguageCatalog.name(for: targetLanguage)
        let task = ModelPrompts.format(
            operation == .polish ? "learningTaskPolish" : "learningTaskTranslate", meaningLanguage)
        var system = promptForOperation(operation) + "\n\n"
        // The prompt text is data; the indent keeps the bytes the literal used to carry.
        system += "            " + task + ModelPrompts["learningPreamble"] + "\n"
        system += "            " + ModelPrompts["learningShape"] + "\n"
        system += "            " + ModelPrompts.format("learningFields", meaningLanguage) + "\n"
        system += "            " + ModelPrompts["learningExample"] + "\n"
        let payload = try JSONSerialization.data(withJSONObject: [
            "original": text, "result": result,
        ])
        let user = String(decoding: payload, as: UTF8.self)
        let messages: [[String: String]]
        if let reply {
            let problems =
                reasons.isEmpty
                ? "It does not satisfy the contract for items."
                : "These rules were broken: " + reasons.joined(separator: "; ") + "."
            messages = [
                ["role": "system", "content": system],
                [
                    "role": "user",
                    "content": "Original and result, as data:\n\(user)",
                ],
                ["role": "assistant", "content": reply],
                [
                    "role": "user",
                    "content": """
                    That reply was rejected. \(problems)
                    Reply again with only the one json object, keeping every meaning you already \
                    wrote and changing only what the rules require.
                    """,
                ],
            ]
        } else {
            messages = [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ]
        }
        let body = requestBody(
            messages: messages, responseFormat: learningResponseFormat(config.model, config: config),
            config: config)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// The learning contract as a provider accepts it: a real schema where the service supports one,
    /// otherwise `json_object` with the shape carried by the system prompt instead.
    private func learningResponseFormat(_ name: String, config: ServiceConfig) -> [String: Any] {
        !config.provider.supportsJSONSchema
            ? ["type": "json_object"]
            : [
                "type": "json_schema",
                "json_schema": [
                    "name": name, "strict": true, "schema": LearningResult.providerSchema,
                ],
            ]
    }

    /// One explicit reading lookup through `$defs.lookup`. The context and offset come from the
    /// app's snapshot, so the model is only trusted for the explanation itself.
    ///
    /// As with learning, a reply this app cannot accept buys one corrective round naming the claims the
    /// model got wrong. A lookup is the app's most exacting contract — seven keys, nullable ones
    /// included, and a definition written in the language that was asked for — and a provider that
    /// breaks it usually has a fixable answer, not a bad one.
    func lookup(_ query: LookupQuery, config: ServiceConfig) async throws -> LookupResult {
        let request = try makeLookupRequest(query, config: config)
        let title = L10n.shared.string("Look Up · %@", query.definitionLanguage)
        switch try await attemptLookup(request, query: query, title: title) {
        case .success(let result):
            return result
        case .failure(let error):
            guard let asModelError = error.error as? ModelError, isCorrectable(asModelError) else {
                throw error.error
            }
            // A reply with no JSON in it names no claim to fix, so it gets no second round.
            let reasons = LookupResult.diagnose(error.content, query: query)
            guard !reasons.isEmpty else { throw error.error }
            let correction = try makeLookupRequest(
                query, config: config, correcting: error.content, reasons: reasons)
            switch try await attemptLookup(
                correction, query: query, title: L10n.shared.string("%@ (corrected)", title))
            {
            case .success(let result): return result
            case .failure(let retried): throw retried.error
            }
        }
    }

    /// Sends one lookup and parses it; the parse failure carries the content back for correction.
    private func attemptLookup(
        _ request: URLRequest, query: LookupQuery, title: String
    ) async throws -> Result<LookupResult, ContractError> {
        func parsed(_ content: String) -> Result<LookupResult, ContractError> {
            do {
                return .success(try LookupResult.parse(content, query: query))
            } catch {
                return .failure(ContractError(error: error, content: content))
            }
        }
        return try await perform(request, title: title, submitted: query.text, parse: parsed)
    }

    func makeLookupRequest(_ query: LookupQuery, config: ServiceConfig) throws -> URLRequest {
        try makeLookupRequest(query, config: config, correcting: nil, reasons: [])
    }

    /// Builds the lookup request. With `correcting`, the same data comes after the model's own rejected
    /// reply and the claims it got wrong, so only the model's answer changes between the two requests.
    func makeLookupRequest(
        _ query: LookupQuery, config: ServiceConfig, correcting reply: String? = nil,
        reasons: [String] = []
    ) throws -> URLRequest {
        var request = URLRequest(url: config.baseURL.appending(path: "chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        let pronunciation =
            query.pronunciation.map { "Use \($0) for pronunciation." }
            ?? "Use kana for Japanese, pinyin for Chinese and IPA for other languages."
        let system = """
            Explain the text a reader selected. With a context, explain only what it means in that \
            context, adding usage only when needed; do not list other senses. With a null context, \
            give the general meaning. Write meaning and part_of_speech in \(query.definitionLanguage).
            Respond with one json object with keys text, language, definition_language, meaning, \
            lemma, pronunciation, part_of_speech. Every key must be present; a field that does not \
            apply or is uncertain is null, not missing. text must equal the selected text exactly. \
            language is the BCP 47 tag of the text, or null if unknown\
            \(query.language.map { "; it is \($0)" } ?? ""). definition_language is \
            \(query.definitionLanguage). lemma is the dictionary form only when it applies and is \
            certain, else null. \(pronunciation) Use null for any field that does not apply or is \
            uncertain. When the text is a whole sentence, pronunciation and part_of_speech must be null. \
            \(ModelPrompts["lookupExample"])
            """
        let payload = try JSONSerialization.data(
            withJSONObject: [
                "text": query.text, "context": query.context as Any? ?? NSNull(),
                "selection_start": query.offset as Any? ?? NSNull(),
                "language": query.language as Any? ?? NSNull(),
            ], options: .sortedKeys)
        let user = String(decoding: payload, as: UTF8.self)
        let messages: [[String: String]]
        if let reply {
            let problems =
                reasons.isEmpty
                ? "It does not satisfy the contract."
                : "These claims were wrong: " + reasons.joined(separator: "; ") + "."
            messages = [
                ["role": "system", "content": system],
                ["role": "user", "content": "Selected text, context and language, as data:\n\(user)"],
                ["role": "assistant", "content": reply],
                [
                    "role": "user",
                    "content": """
                    That reply was rejected. \(problems)
                    Reply again with only the one json object, every key present and every other \
                    claim unchanged.
                    """,
                ],
            ]
        } else {
            messages = [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ]
        }
        let body = requestBody(
            messages: messages, responseFormat: lookupResponseFormat(config: config), config: config)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// The lookup contract as a provider accepts it.
    private func lookupResponseFormat(config: ServiceConfig) -> [String: Any] {
        !config.provider.supportsJSONSchema
            ? ["type": "json_object"]
            : [
                "type": "json_schema",
                "json_schema": [
                    "name": "lookup", "strict": true, "schema": LookupResult.providerSchema,
                ],
            ]
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

    /// Sends one request and hands the finished exchange to the debug capture whatever the outcome,
    /// then parses the decoded content. Every request type goes through here so none is silently
    /// left off the debug page.
    private func perform<T>(
        _ request: URLRequest, title: String, submitted: String, parse: (String) throws -> T
    ) async throws -> T {
        let capture = capture
        let records = capture.isEnabled()
        var response: String?
        var failure: String?
        var failureKind: ModelError.Kind?
        // The record is handed off, not awaited: diagnostics must never delay or fail a request.
        defer {
            if records {
                let exchange = DebugExchange(
                    title: title, request: Self.prettyPrintedBody(request), submitted: submitted,
                    response: response, failure: failure, failureKind: failureKind)
                let record = capture.record
                Task { await record(exchange) }
            }
        }
        do {
            let content = try decodedContent(try await send(request))
            response = content
            return try parse(content)
        } catch {
            failure = (error as? ModelError)?.message ?? error.localizedDescription
            failureKind = (error as? ModelError)?.kind
            throw error
        }
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
