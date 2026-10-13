import Foundation

/// One turn of the conversation as the app sends it: the user's data, or a reply the app is showing
/// back to the model for the one corrective round.
enum ModelTurn: Sendable, Equatable {
    case user(String)
    case assistant(String)

    var content: String {
        switch self {
        case .user(let text): text
        case .assistant(let text): "Previous reply (rejected):\n" + text
        }
    }
}

/// How the answer must be shaped. A provider that cannot constrain the shape carries it in the system
/// prompt instead, which is what the app already does for DeepSeek and for pi.
enum ModelResponseFormat: Sendable, Equatable {
    case jsonObject
    case jsonSchema(name: String, schema: Data)
}

/// One row of a model picker: the value the provider takes, the text a person reads, and — when the
/// provider says so — the effort levels that model accepts. `efforts` is nil when the provider says
/// nothing about it, and empty when the model does not reason at all.
struct ModelOption: Sendable, Equatable, Hashable {
    var id: String
    var label: String
    var efforts: [EffortLevel]?

    init(id: String, label: String? = nil, efforts: [EffortLevel]? = nil) {
        self.id = id
        self.label = label ?? id
        self.efforts = efforts
    }
}

/// One model call, provider-agnostic (BDR-0013 §3): the same value goes to an HTTP service or to a
/// local agent CLI, and each backend turns it into its own request.
struct ModelRequest: Sendable, Equatable {
    var model: String
    /// The behavior prompt plus the fixed contract and this operation's task.
    var system: String
    var turns: [ModelTurn]
    var format: ModelResponseFormat
    var effort: EffortLevel
    /// What the provider said the chosen model accepts, when it said anything: the effort switch takes
    /// the nearest lower level in this list, and no level at all when the list is empty.
    var supportedEfforts: [EffortLevel]? = nil
}

/// How the app reaches a model. Every provider implements this, so nothing above it knows whether the
/// answer came from an HTTP service or from a process.
protocol ModelBackend: Sendable {
    /// The request as the debug page shows it: the body that was posted, or the command that ran.
    func describe(_ request: ModelRequest, config: ServiceConfig) -> String
    /// Runs one request and returns the model's answer text, or throws what the UI shows.
    func complete(_ request: ModelRequest, config: ServiceConfig) async throws -> String
}

/// An OpenAI-compatible service: the app posts the same chat body it has always posted.
struct OpenAICompatibleBackend: ModelBackend {
    var transport: Transport = { try await URLSession.shared.data(for: $0) }

    func describe(_ request: ModelRequest, config: ServiceConfig) -> String {
        guard let body = try? Self.body(for: request, config: config) else {
            return "(the request body is unreadable)"
        }
        return Self.prettyPrinted(body)
    }

    func complete(_ request: ModelRequest, config: ServiceConfig) async throws -> String {
        var urlRequest = URLRequest(url: config.baseURL.appending(path: "chat/completions"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try Self.body(for: request, config: config)
        return try Self.content(from: try await send(urlRequest))
    }

    /// The chat body as the service receives it. Kept separate from sending, so the wire shape is
    /// asserted directly by the tests instead of through a captured request.
    static func body(for request: ModelRequest, config: ServiceConfig) throws -> Data {
        var body: [String: Any] = [
            "model": request.model,
            "messages": messages(for: request),
            "response_format": responseFormat(request.format),
        ]
        // 自动 sends no effort parameter at all, and a local agent maps the level to its own switch
        // rather than to this OpenAI-style field.
        if config.provider.localAgent == nil,
            let value = ModelEffort.reasoningEffort(for: request.effort, model: request.model)
        {
            body["reasoning_effort"] = value
        }
        return try JSONSerialization.data(withJSONObject: body)
    }

    /// The body as sent, so the debug page shows the real request instead of a reconstruction. The API
    /// key is a header, so it is not included.
    static func prettyPrinted(_ body: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: body),
            let pretty = try? JSONSerialization.data(
                withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
            let text = String(data: pretty, encoding: .utf8)
        else { return "(the request body is unreadable)" }
        return text
    }

    /// Decodes the provider envelope and applies the shared truncation and content-policy rules before
    /// any contract parsing, so every request type fails the same way.
    static func content(from data: Data) throws -> String {
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

    /// Sends one request to the service; `listModels` uses this too.
    func send(_ request: URLRequest) async throws -> Data {
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

    private static func messages(for request: ModelRequest) -> [[String: String]] {
        var messages: [[String: String]] = [["role": "system", "content": request.system]]
        for turn in request.turns {
            switch turn {
            case .user(let text): messages.append(["role": "user", "content": text])
            case .assistant(let text): messages.append(["role": "assistant", "content": text])
            }
        }
        return messages
    }

    private static func responseFormat(_ format: ModelResponseFormat) -> [String: Any] {
        switch format {
        case .jsonObject:
            return ["type": "json_object"]
        case .jsonSchema(let name, let schema):
            let object = (try? JSONSerialization.jsonObject(with: schema)) ?? [String: Any]()
            return [
                "type": "json_schema",
                "json_schema": ["name": name, "strict": true, "schema": object],
            ]
        }
    }
}

/// A local agent CLI: the app runs one process and reads its final text (BDR-0013). The agent does not
/// wrap its answer in a provider envelope, because it has none to wrap: the text is the text.
struct LocalAgentBackend: ModelBackend {
    var kind: LocalAgentKind
    var agent: LocalAgent = LocalAgent()

    func describe(_ request: ModelRequest, config: ServiceConfig) -> String {
        agent.command(kind: kind, request: request, config: config) ?? "(the agent is not set)"
    }

    func complete(_ request: ModelRequest, config: ServiceConfig) async throws -> String {
        try await agent.complete(kind: kind, request: request, config: config)
    }
}

extension Provider {
    /// The backend that runs one request for this provider: a CLI for a local agent, HTTP otherwise.
    func backend(transport: @escaping Transport, agent: LocalAgent) -> any ModelBackend {
        guard let kind = localAgent else { return OpenAICompatibleBackend(transport: transport) }
        return LocalAgentBackend(kind: kind, agent: agent)
    }
}
