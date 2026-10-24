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
/// prompt instead, which is what the app already does for DeepSeek.
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
    /// A value the user typed in place of a level; every backend sends it verbatim and maps nothing.
    var customEffort: String? = nil
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
    /// The answer as its pieces arrive. The default runs `complete` and yields the whole answer once
    /// (BDR-0017 §4): a backend without a stream works unchanged, and a request never has to care
    /// which shape it got.
    func stream(_ request: ModelRequest, config: ServiceConfig) -> AsyncThrowingStream<String, Error>
}

extension ModelBackend {
    func stream(
        _ request: ModelRequest, config: ServiceConfig
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let whole = Task<Void, Never> {
                do {
                    continuation.yield(try await self.complete(request, config: config))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in whole.cancel() }
        }
    }

    /// The degradation of BDR-0017 §4 as a stream: `complete` runs once and its answer is the
    /// stream's only element, so a caller sees the same shape either way. A backend reaches for it
    /// when no separate stream seam has been given — a `transport` stub serves both paths then.
    static func degraded(
        _ complete: @escaping @Sendable () async throws -> String
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let whole = Task<Void, Never> {
                do {
                    continuation.yield(try await complete())
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in whole.cancel() }
        }
    }
}

/// An OpenAI-compatible service: the app posts the same chat body it has always posted.
struct OpenAICompatibleBackend: ModelBackend {
    var transport: Transport = { try await URLSession.shared.data(for: $0) }
    /// `nil` (the default) degrades to `complete` (BDR-0017 §4): a `transport` stub then serves
    /// both paths, so a test that injects one seam covers streaming too.
    var streamTransport: StreamTransport? = nil

    func describe(_ request: ModelRequest, config: ServiceConfig) -> String {
        HTTPBackend.describe { try Self.body(for: request, config: config) }
    }

    func complete(_ request: ModelRequest, config: ServiceConfig) async throws -> String {
        let body = try Self.body(for: request, config: config)
        let urlRequest = HTTPBackend.post(
            config.baseURL.appending(path: "chat/completions"), body: body,
            headers: HTTPBackend.credential("Authorization", config.apiKey, prefix: "Bearer "))
        return try Self.content(from: try await HTTPBackend.send(urlRequest, transport: transport))
    }

    func stream(
        _ request: ModelRequest, config: ServiceConfig
    ) -> AsyncThrowingStream<String, Error> {
        guard let streamTransport else {
            return Self.degraded { try await self.complete(request, config: config) }
        }
        return HTTPStreaming.sse(
            {
                HTTPBackend.post(
                    config.baseURL.appending(path: "chat/completions"),
                    body: try Self.body(for: request, config: config, stream: true),
                    headers: HTTPBackend.credential("Authorization", config.apiKey, prefix: "Bearer "))
            }, transport: streamTransport
        ) { OpenAIChatStream() }
    }

    /// The chat body as the service receives it. Kept separate from sending, so the wire shape is
    /// asserted directly by the tests instead of through a captured request. `stream` adds only the
    /// streaming switch, which is owned by the transport, not the request.
    static func body(for request: ModelRequest, config: ServiceConfig, stream: Bool = false)
        throws -> Data
    {
        var body: [String: Any] = [
            "model": request.model,
            "messages": messages(for: request),
            "response_format": responseFormat(request.format),
        ]
        if stream { body["stream"] = true }
        // Automatic sends no effort parameter at all.
        if let value = request.customEffort
            ?? ModelEffort.reasoningEffort(for: request.effort, model: request.model)
        {
            body["reasoning_effort"] = value
        }
        return try JSONSerialization.data(withJSONObject: body)
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

    private static func messages(for request: ModelRequest) -> [[String: String]] {
        [["role": "system", "content": request.system]]
            + HTTPBackend.roles(request.turns).map { ["role": $0.role, "content": $0.text] }
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

    func stream(
        _ request: ModelRequest, config: ServiceConfig
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let stream = Task<Void, Never> {
                do {
                    let answer = try await agent.stream(kind: kind, request: request, config: config)
                    // An answer that never shows anything is the same empty reply the whole shot
                    // reports, so a shrink of the contract never buys a corrective round.
                    var answered = false
                    for try await piece in answer where !piece.isEmpty {
                        answered = true
                        continuation.yield(piece)
                    }
                    guard answered else { throw ModelError.emptyResponse }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in stream.cancel() }
        }
    }
}

extension Provider {
    /// The backend that speaks this provider's protocol: one HTTP wire shape each, or a CLI. With no
    /// stream transport the HTTP backends degrade to `complete` (BDR-0017 §4), matching their own
    /// and `ModelClient`'s defaults.
    func backend(
        transport: @escaping Transport, stream: StreamTransport? = nil, agent: LocalAgent
    ) -> any ModelBackend {
        switch self {
        case .openAICompatible: OpenAICompatibleBackend(transport: transport, streamTransport: stream)
        case .openAIResponses: OpenAIResponsesBackend(transport: transport, streamTransport: stream)
        case .anthropic: AnthropicBackend(transport: transport, streamTransport: stream)
        case .gemini: GeminiBackend(transport: transport, streamTransport: stream)
        case .claudeCode: LocalAgentBackend(kind: .claudeCode, agent: agent)
        case .codexCLI: LocalAgentBackend(kind: .codexCLI, agent: agent)
        }
    }
}

/// What every HTTP protocol shares: posting a JSON body, the status codes, and showing the body on the
/// debug page. The wire shapes differ; this part does not.
enum HTTPBackend {
    /// The credential header, or none when no key is set: a local server such as Ollama asks for
    /// none, and an empty credential is a malformed one some services refuse.
    static func credential(_ field: String, _ key: String, prefix: String = "") -> [String: String] {
        key.isEmpty ? [:] : [field: prefix + key]
    }

    static func post(_ url: URL, body: Data, headers: [String: String]) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (field, value) in headers { request.setValue(value, forHTTPHeaderField: field) }
        request.httpBody = body
        return request
    }

    /// Sends one request; a failure becomes the `ModelError` the UI shows, a cancellation stays one.
    static func send(_ request: URLRequest, transport: Transport) async throws -> Data {
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
            if !(200..<300).contains(http.statusCode) {
                throw ModelError.http(http.statusCode, detail: Self.detail(from: data))
            }
        }
        return data
    }

    /// The body of a failed response, trimmed and cut to something a page can show. nil when there was
    /// nothing to read.
    static func detail(from data: Data) -> String? {
        let text = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return String(text.prefix(2000))
    }

    /// The body as sent, so the debug page shows the real request instead of a reconstruction. The API
    /// key is a header, so it is not included.
    static func describe(_ body: () throws -> Data) -> String {
        guard let data = try? body(), let object = try? JSONSerialization.jsonObject(with: data),
            let pretty = try? JSONSerialization.data(
                withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
            let text = String(data: pretty, encoding: .utf8)
        else { return "(the request body is unreadable)" }
        return text
    }

    /// The turns as role/text pairs, which is the shape every HTTP protocol starts from.
    static func roles(_ turns: [ModelTurn], assistant: String = "assistant") -> [(role: String, text: String)] {
        turns.map {
            switch $0 {
            case .user(let text): ("user", text)
            case .assistant(let text): (assistant, text)
            }
        }
    }
}

/// The Anthropic Messages API. The schema goes in `output_config.format`, which has no `json_object`
/// mode: without a schema the shape travels in the system prompt alone.
struct AnthropicBackend: ModelBackend {
    var transport: Transport = { try await URLSession.shared.data(for: $0) }
    /// `nil` (the default) degrades to `complete` (BDR-0017 §4): a `transport` stub then serves
    /// both paths, so a test that injects one seam covers streaming too.
    var streamTransport: StreamTransport? = nil

    static let apiVersion = "2023-06-01"
    /// The API requires a ceiling. This one leaves room for the longest learning reply while keeping a
    /// non-streaming request well inside the HTTP timeout.
    static let maxTokens = 16000

    /// Thinking cannot be switched off on current Claude models, so Off is the lowest level, as for the
    /// local agents.
    static let effortValues: [EffortLevel: String] = [
        .off: "low", .low: "low", .medium: "medium", .high: "high", .max: "max",
    ]

    func describe(_ request: ModelRequest, config: ServiceConfig) -> String {
        HTTPBackend.describe { try Self.body(for: request) }
    }

    func complete(_ request: ModelRequest, config: ServiceConfig) async throws -> String {
        let urlRequest = HTTPBackend.post(
            config.baseURL.appending(path: "messages"), body: try Self.body(for: request),
            headers: HTTPBackend.credential("x-api-key", config.apiKey).merging(["anthropic-version": Self.apiVersion])
            { $1 })
        return try Self.content(from: try await HTTPBackend.send(urlRequest, transport: transport))
    }

    func stream(
        _ request: ModelRequest, config: ServiceConfig
    ) -> AsyncThrowingStream<String, Error> {
        guard let streamTransport else {
            return Self.degraded { try await self.complete(request, config: config) }
        }
        return HTTPStreaming.sse(
            {
                HTTPBackend.post(
                    config.baseURL.appending(path: "messages"),
                    body: try Self.body(for: request, stream: true),
                    headers: HTTPBackend.credential("x-api-key", config.apiKey).merging([
                        "anthropic-version": Self.apiVersion
                    ]) { $1 })
            }, transport: streamTransport
        ) { AnthropicStream() }
    }

    static func body(for request: ModelRequest, stream: Bool = false) throws -> Data {
        var output: [String: Any] = [:]
        if case .jsonSchema(_, let schema) = request.format {
            output["format"] = [
                "type": "json_schema", "schema": try JSONSerialization.jsonObject(with: schema),
            ]
        }
        output["effort"] = request.customEffort ?? effortValues[request.effort]
        var body: [String: Any] = [
            "model": request.model,
            "max_tokens": maxTokens,
            "system": request.system,
            "messages": HTTPBackend.roles(request.turns).map { ["role": $0.role, "content": $0.text] },
        ]
        if stream { body["stream"] = true }
        if !output.isEmpty { body["output_config"] = output }
        return try JSONSerialization.data(withJSONObject: body)
    }

    static func content(from data: Data) throws -> String {
        let reply = try? JSONDecoder().decode(Reply.self, from: data)
        if reply?.stopReason == "max_tokens" { throw ModelError.truncated }
        if reply?.stopReason == "refusal" { throw ModelError.refused }
        let text = (reply?.content ?? []).filter { $0.type == "text" }.compactMap(\.text).joined()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ModelError.emptyResponse
        }
        return text
    }

    private struct Reply: Decodable {
        struct Block: Decodable {
            var type: String
            var text: String?
        }
        var content: [Block]
        var stopReason: String?

        enum CodingKeys: String, CodingKey {
            case content
            case stopReason = "stop_reason"
        }
    }
}

/// The OpenAI Responses API. Same effort vocabulary as Chat Completions, so the same per-model table
/// applies; the envelope and the field names differ.
struct OpenAIResponsesBackend: ModelBackend {
    var transport: Transport = { try await URLSession.shared.data(for: $0) }
    /// `nil` (the default) degrades to `complete` (BDR-0017 §4): a `transport` stub then serves
    /// both paths, so a test that injects one seam covers streaming too.
    var streamTransport: StreamTransport? = nil

    func describe(_ request: ModelRequest, config: ServiceConfig) -> String {
        HTTPBackend.describe { try Self.body(for: request) }
    }

    func complete(_ request: ModelRequest, config: ServiceConfig) async throws -> String {
        let urlRequest = HTTPBackend.post(
            config.baseURL.appending(path: "responses"), body: try Self.body(for: request),
            headers: HTTPBackend.credential("Authorization", config.apiKey, prefix: "Bearer "))
        return try Self.content(from: try await HTTPBackend.send(urlRequest, transport: transport))
    }

    func stream(
        _ request: ModelRequest, config: ServiceConfig
    ) -> AsyncThrowingStream<String, Error> {
        guard let streamTransport else {
            return Self.degraded { try await self.complete(request, config: config) }
        }
        return HTTPStreaming.sse(
            {
                HTTPBackend.post(
                    config.baseURL.appending(path: "responses"),
                    body: try Self.body(for: request, stream: true),
                    headers: HTTPBackend.credential("Authorization", config.apiKey, prefix: "Bearer "))
            }, transport: streamTransport
        ) { OpenAIResponsesStream() }
    }

    static func body(for request: ModelRequest, stream: Bool = false) throws -> Data {
        let format: [String: Any]
        switch request.format {
        case .jsonObject:
            format = ["type": "json_object"]
        case .jsonSchema(let name, let schema):
            format = [
                "type": "json_schema", "name": name, "strict": true,
                "schema": try JSONSerialization.jsonObject(with: schema),
            ]
        }
        var body: [String: Any] = [
            "model": request.model,
            "instructions": request.system,
            "input": HTTPBackend.roles(request.turns).map { ["role": $0.role, "content": $0.text] },
            "text": ["format": format],
            // The user's text has no reason to outlive the request on the vendor's side.
            "store": false,
        ]
        if let value = request.customEffort
            ?? ModelEffort.reasoningEffort(for: request.effort, model: request.model)
        {
            body["reasoning"] = ["effort": value]
        }
        if stream { body["stream"] = true }
        return try JSONSerialization.data(withJSONObject: body)
    }

    /// `output_text` is an SDK convenience, so the text is read from the message items themselves.
    static func content(from data: Data) throws -> String {
        let reply = try? JSONDecoder().decode(Reply.self, from: data)
        switch reply?.incompleteDetails?.reason {
        case "max_output_tokens": throw ModelError.truncated
        case "content_filter": throw ModelError.refused
        default: break
        }
        let parts = (reply?.output ?? []).filter { $0.type == "message" }.flatMap { $0.content ?? [] }
        if parts.contains(where: { $0.type == "refusal" }) { throw ModelError.refused }
        let text = parts.filter { $0.type == "output_text" }.compactMap(\.text).joined()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ModelError.emptyResponse
        }
        return text
    }

    private struct Reply: Decodable {
        struct Item: Decodable {
            struct Part: Decodable {
                var type: String
                var text: String?
            }
            var type: String
            var content: [Part]?
        }
        struct Incomplete: Decodable { var reason: String? }
        var output: [Item]
        var incompleteDetails: Incomplete?

        enum CodingKeys: String, CodingKey {
            case output
            case incompleteDetails = "incomplete_details"
        }
    }
}

/// The Gemini API's `generateContent`. The schema goes in `responseJsonSchema`, and without one the
/// reply is still asked for as JSON, which is Gemini's `json_object`.
struct GeminiBackend: ModelBackend {
    var transport: Transport = { try await URLSession.shared.data(for: $0) }
    /// `nil` (the default) degrades to `complete` (BDR-0017 §4): a `transport` stub then serves
    /// both paths, so a test that injects one seam covers streaming too.
    var streamTransport: StreamTransport? = nil

    func describe(_ request: ModelRequest, config: ServiceConfig) -> String {
        HTTPBackend.describe { try Self.body(for: request) }
    }

    func complete(_ request: ModelRequest, config: ServiceConfig) async throws -> String {
        let urlRequest = HTTPBackend.post(
            config.baseURL.appending(path: "models/\(request.model):generateContent"),
            body: try Self.body(for: request), headers: HTTPBackend.credential("x-goog-api-key", config.apiKey))
        return try Self.content(from: try await HTTPBackend.send(urlRequest, transport: transport))
    }

    func stream(
        _ request: ModelRequest, config: ServiceConfig
    ) -> AsyncThrowingStream<String, Error> {
        guard let streamTransport else {
            return Self.degraded { try await self.complete(request, config: config) }
        }
        return HTTPStreaming.sse(
            {
                HTTPBackend.post(
                    config.baseURL.appending(
                        path: "models/\(request.model):streamGenerateContent"
                    )
                    .appending(queryItems: [URLQueryItem(name: "alt", value: "sse")]),
                    body: try Self.body(for: request),
                    headers: HTTPBackend.credential("x-goog-api-key", config.apiKey))
            }, transport: streamTransport
        ) { GeminiStream() }
    }

    static func body(for request: ModelRequest) throws -> Data {
        var generation: [String: Any] = ["responseMimeType": "application/json"]
        if case .jsonSchema(_, let schema) = request.format {
            generation["responseJsonSchema"] = try JSONSerialization.jsonObject(with: schema)
        }
        if let level = request.customEffort ?? thinkingLevel(for: request.effort, model: request.model) {
            generation["thinkingConfig"] = ["thinkingLevel": level]
        }
        let body: [String: Any] = [
            "systemInstruction": ["parts": [["text": request.system]]],
            "contents": HTTPBackend.roles(request.turns, assistant: "model").map {
                ["role": $0.role, "parts": [["text": $0.text]]]
            },
            "generationConfig": generation,
        ]
        return try JSONSerialization.data(withJSONObject: body)
    }

    /// `thinkingLevel` exists from Gemini 3 on and is an error on earlier models, so those get nothing.
    /// Which levels a model takes varies, and an unsupported one is a 400, so each family maps to what
    /// its documentation lists; none of them can switch thinking off entirely.
    // ponytail: prefix table like ModelEffort; read `thinking` from GET /models if the families multiply.
    static func thinkingLevel(for level: EffortLevel, model: String) -> String? {
        guard level != .automatic else { return nil }
        let id = model.lowercased().replacingOccurrences(of: "models/", with: "")
        let table: [EffortLevel: String]
        if id.hasPrefix("gemini-3-flash") {
            table = [.off: "MINIMAL", .low: "LOW", .medium: "MEDIUM", .high: "HIGH", .max: "HIGH"]
        } else if id.hasPrefix("gemini-3") || id.hasPrefix("gemini-4") {
            // The pro families take only low and high, and an unsupported level is a 400, so a level
            // they lack falls back rather than being sent.
            table =
                id.contains("-pro")
                ? [.off: "LOW", .low: "LOW", .medium: "LOW", .high: "HIGH", .max: "HIGH"]
                : [.off: "LOW", .low: "LOW", .medium: "MEDIUM", .high: "HIGH", .max: "HIGH"]
        } else {
            return nil
        }
        return table[level]
    }

    static func content(from data: Data) throws -> String {
        let reply = try? JSONDecoder().decode(Reply.self, from: data)
        if reply?.promptFeedback?.blockReason != nil { throw ModelError.refused }
        let candidate = reply?.candidates?.first
        switch candidate?.finishReason {
        case nil, "STOP", "FINISH_REASON_UNSPECIFIED": break
        case "MAX_TOKENS", "CONTINUATION": throw ModelError.truncated
        default: throw ModelError.refused
        }
        let text = (candidate?.content?.parts ?? []).filter { $0.thought != true }.compactMap(\.text)
            .joined()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ModelError.emptyResponse
        }
        return text
    }

    private struct Reply: Decodable {
        struct Candidate: Decodable {
            struct Content: Decodable {
                struct Part: Decodable {
                    var text: String?
                    var thought: Bool?
                }
                var parts: [Part]?
            }
            var content: Content?
            var finishReason: String?
        }
        struct Feedback: Decodable { var blockReason: String? }
        var candidates: [Candidate]?
        var promptFeedback: Feedback?
    }
}
