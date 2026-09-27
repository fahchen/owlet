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

    func translate(_ text: String, to targetLanguage: String, config: ServiceConfig)
        async throws -> String
    {
        let request = try makeRequest(text: text, targetLanguage: targetLanguage, config: config)
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
        let choice = (try? JSONDecoder().decode(ChatResponse.self, from: data))?.choices.first
        if choice?.finishReason == "length" { throw ModelError.truncated }
        if choice?.finishReason == "content_filter" || choice?.message.refusal?.isEmpty == false {
            throw ModelError.refused
        }
        guard let content = choice?.message.content,
            !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw ModelError.emptyResponse }
        return try TranslationResult.parse(
            content, submitted: text, targetLanguage: targetLanguage
        ).text
    }

    func makeRequest(text: String, targetLanguage: String, config: ServiceConfig) throws
        -> URLRequest
    {
        var request = URLRequest(url: config.baseURL.appending(path: "chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        let system = """
            \(DefaultPrompts.translate)

            Operation: translate. Target language: \(targetLanguage).
            Respond with one JSON object with keys source_language, target_language and segments \
            (array of {source, target}). Concatenated sources must equal the user message exactly.
            """
        let body: [String: Any] = [
            "model": config.model,
            "messages": [
                ["role": "system", "content": system], ["role": "user", "content": text],
            ],
            "response_format": [
                "type": "json_schema",
                "json_schema": [
                    "name": "translation", "strict": true,
                    "schema": TranslationResult.providerSchema,
                ],
            ],
        ]
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
