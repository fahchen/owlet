import Foundation

enum ModelError: Error, Equatable {
    case network(String)
    case unauthorized
    case http(Int)
    case emptyResponse

    var message: String {
        switch self {
        case .network(let detail): "Network error: \(detail)"
        case .unauthorized: "Authentication failed. Check the API key."
        case .http(let code): "Service returned HTTP \(code)."
        case .emptyResponse: "The service returned an empty response."
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
        let body = try? JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = body?.choices.first?.message.content,
            !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw ModelError.emptyResponse }
        return content
    }

    func makeRequest(text: String, targetLanguage: String, config: ServiceConfig) throws
        -> URLRequest
    {
        var request = URLRequest(url: config.baseURL.appending(path: "chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        let system =
            "Translate the user's message into \(targetLanguage). Reply with the translation only."
        let body = ChatRequest(
            model: config.model,
            messages: [.init(role: "system", content: system), .init(role: "user", content: text)])
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }
}

struct ChatMessage: Codable, Equatable {
    var role: String
    var content: String
}

struct ChatRequest: Encodable {
    var model: String
    var messages: [ChatMessage]
}

struct ChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            var content: String?
        }
        var message: Message
    }
    var choices: [Choice]
}
