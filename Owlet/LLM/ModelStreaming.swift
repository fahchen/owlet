import Foundation

/// A transport that returns the response body while it is still arriving: the streaming twin of
/// `Transport`. The live client wraps `URLSession.bytes`; a test supplies short fixtures from
/// memory. The response arrives up front, which is what lets the shared status rules apply
/// before any body byte is read.
typealias StreamTransport =
    @Sendable (URLRequest) async throws -> (
        AsyncThrowingStream<UInt8, Error>, URLResponse
    )

extension URLSession {
    /// The session's response body as a plain byte stream — the only shape a live session and a
    /// test fixture can both produce. Reading is cancelled together with the returned stream.
    static func stream(
        for request: URLRequest
    ) async throws -> (AsyncThrowingStream<UInt8, Error>, URLResponse) {
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        let stream = AsyncThrowingStream<UInt8, Error> { continuation in
            let reading = Task<Void, Never> {
                do {
                    for try await byte in bytes { continuation.yield(byte) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in reading.cancel() }
        }
        return (stream, response)
    }
}

/// How one provider's streamed events fold into the answer text. The shared rules a complete
/// reply applies before any contract parsing — truncation, refusal, emptiness — stay with the
/// decoder, so a stream fails exactly as its whole-shot sibling does and text that arrived
/// through a stream never counts as success without them.
protocol SSEReplyDecoder: Sendable {
    /// Consumes one `data:` payload; returns what of the answer it revealed, if anything.
    /// A payload this provider's envelope cannot be read from is skipped, not fatal: keep-alive
    /// frames and other event kinds would otherwise fail a reply the whole shot would have parsed.
    mutating func read(_ payload: String) throws -> String?
    /// Checks the complete answer once the stream has ended. Nothing is yielded from here — every
    /// shown character must have arrived as its own chunk — but truncation, refusal and an empty
    /// answer must fail here exactly as they would for a complete reply.
    func content() throws -> String
}

/// What every HTTP protocol shares when the answer streams: the status check with the same
/// mapping as `HTTPBackend.send`, turning the server-sent event stream into `data:` payloads,
/// and the loop that folds those payloads through a protocol's decoder.
enum HTTPStreaming {
    /// Sends one request and returns its body bytes. The status mapping is `HTTPBackend.send`'s;
    /// a failed status cannot show its body from headers alone, so the remaining bytes are drained
    /// for the detail the debug page quotes.
    static func send(
        _ request: URLRequest, transport: StreamTransport
    ) async throws -> AsyncThrowingStream<UInt8, Error> {
        let stream: AsyncThrowingStream<UInt8, Error>
        let response: URLResponse
        do {
            (stream, response) = try await transport(request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw ModelError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { return stream }
        if http.statusCode == 401 || http.statusCode == 403 { throw ModelError.unauthorized }
        if !(200..<300).contains(http.statusCode) {
            var detail = Data()
            do {
                for try await byte in stream { detail.append(byte) }
            } catch {
                // The status carries the failure; whatever remained of the body is only the detail.
            }
            throw ModelError.http(http.statusCode, detail: HTTPBackend.detail(from: detail))
        }
        return stream
    }

    /// The `data:` payloads of a server-sent event stream, one yield per frame. Frame framing is
    /// followed with tolerance: CR-LF endings, a frame with no final blank line, and non-`data:`
    /// fields are all accepted; multi-line payloads keep their inner breaks.
    static func events(
        from bytes: AsyncThrowingStream<UInt8, Error>
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let reading = Task<Void, Never> {
                do {
                    var carried = [UInt8]()
                    var frame = ""
                    for try await byte in bytes {
                        guard byte != UInt8(ascii: "\n") else {
                            var line = String(decoding: carried, as: UTF8.self)
                            carried = []
                            if line.hasSuffix("\r") { line.removeLast() }
                            if line.isEmpty {
                                if !frame.isEmpty { continuation.yield(frame) }
                                frame = ""
                            } else if line.hasPrefix("data:") {
                                var value = line.dropFirst(5)
                                if value.hasPrefix(" ") { value = value.dropFirst() }
                                frame = frame.isEmpty ? String(value) : frame + "\n" + String(value)
                            }
                            continue
                        }
                        carried.append(byte)
                    }
                    // A frame whose terminator the service dropped still means what it said.
                    if !frame.isEmpty { continuation.yield(frame) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in reading.cancel() }
        }
    }

    /// Sends the request, folds its events through `decoder`, and yields the answer as it arrives.
    /// Ends the instant the underlying request does; consuming the stream and the request share
    /// one cancellation path.
    static func sse<D: SSEReplyDecoder>(
        _ request: @escaping @Sendable () throws -> URLRequest,
        transport: @escaping StreamTransport,
        decoder: @escaping @Sendable () -> D
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let reading = Task<Void, Never> {
                do {
                    let bytes = try await send(request(), transport: transport)
                    var reply = decoder()
                    for try await payload in events(from: bytes) {
                        guard let revealed = try reply.read(payload), !revealed.isEmpty else {
                            continue
                        }
                        continuation.yield(revealed)
                    }
                    // Truncation, refusal and an empty answer are decided here, after the frame
                    // loop: the chunks the panel saw must never survive these checks.
                    _ = try reply.content()
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in reading.cancel() }
        }
    }
}

/// OpenAI Chat Completions: increments in `choices[0].delta.content`, the finish reason on a late
/// chunk, and a `data: [DONE]` terminator.
struct OpenAIChatStream: SSEReplyDecoder {
    private var builder = ""
    /// The model can refuse mid-stream: a refusal answer streams as its own delta.
    private var refusal = ""
    private var finishReason: String?
    private var ended = false

    mutating func read(_ payload: String) throws -> String? {
        if payload == "[DONE]" { ended = true; return nil }
        guard !ended, let event = try? JSONDecoder().decode(Event.self, from: Data(payload.utf8)),
            let choice = event.choices.first
        else { return nil }
        if choice.finishReason != nil { finishReason = choice.finishReason }
        if let revealed = choice.delta.refusal { refusal += revealed }
        guard let text = choice.delta.content, !text.isEmpty else { return nil }
        builder += text
        return text
    }

    /// The same rules `OpenAICompatibleBackend.content` applies to a whole reply.
    func content() throws -> String {
        if finishReason == "length" { throw ModelError.truncated }
        if finishReason == "content_filter" || !refusal.isEmpty { throw ModelError.refused }
        guard !builder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ModelError.emptyResponse
        }
        return builder
    }

    private struct Event: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable {
                var content: String?
                var refusal: String?
            }
            var delta: Delta
            var finishReason: String?

            enum CodingKeys: String, CodingKey {
                case delta
                case finishReason = "finish_reason"
            }
        }
        var choices: [Choice]
    }
}

/// The Anthropic Messages stream: `content_block_delta` carries the text, `message_delta` the
/// stop reason, and an `error` event is the stream's own failure.
struct AnthropicStream: SSEReplyDecoder {
    private var builder = ""
    private var stopReason: String?

    mutating func read(_ payload: String) throws -> String? {
        guard let event = try? JSONDecoder().decode(Event.self, from: Data(payload.utf8)) else {
            return nil
        }
        switch event.type {
        case "content_block_delta":
            // A model's own thinking is not the answer: only `text_delta` shows.
            guard event.delta?.type == "text_delta", let text = event.delta?.text, !text.isEmpty
            else { return nil }
            builder += text
            return text
        case "message_delta":
            if let reason = event.delta?.stopReason { stopReason = reason }
            return nil
        case "error":
            throw ModelError.network(event.error?.message ?? "the service stream failed")
        default:
            return nil
        }
    }

    /// The same rules `AnthropicBackend.content` applies to a whole reply.
    func content() throws -> String {
        if stopReason == "max_tokens" { throw ModelError.truncated }
        if stopReason == "refusal" { throw ModelError.refused }
        guard !builder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ModelError.emptyResponse
        }
        return builder
    }

    private struct Event: Decodable {
        struct Delta: Decodable {
            var type: String?
            var text: String?
            var stopReason: String?

            enum CodingKeys: String, CodingKey {
                case type, text
                case stopReason = "stop_reason"
            }
        }
        struct Failure: Decodable { var message: String? }
        var type: String?
        var delta: Delta?
        var error: Failure?
    }
}

/// The OpenAI Responses stream: `response.output_text.delta` carries the text; the incomplete and
/// failed terminal events reuse the complete reply's own reasons.
struct OpenAIResponsesStream: SSEReplyDecoder {
    private var builder = ""
    private var refusal = ""
    private var incomplete: String?
    private var failure: String?

    mutating func read(_ payload: String) throws -> String? {
        guard let event = try? JSONDecoder().decode(Event.self, from: Data(payload.utf8)) else {
            return nil
        }
        switch event.type {
        case "response.output_text.delta":
            guard let text = event.delta, !text.isEmpty else { return nil }
            builder += text
            return text
        case "response.refusal.delta":
            refusal += event.delta ?? ""
        case "response.incomplete":
            incomplete = event.response?.incompleteDetails?.reason ?? incomplete
        case "response.failed":
            failure = event.response?.error?.message ?? "the response failed"
        case "error":
            throw ModelError.network(event.error?.message ?? event.message ?? "the service stream failed")
        default:
            break
        }
        return nil
    }

    /// The same rules `OpenAIResponsesBackend.content` applies to a whole reply.
    func content() throws -> String {
        switch incomplete {
        case "max_output_tokens": throw ModelError.truncated
        case "content_filter": throw ModelError.refused
        default: break
        }
        if !refusal.isEmpty { throw ModelError.refused }
        if let failure { throw ModelError.network(failure) }
        guard !builder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ModelError.emptyResponse
        }
        return builder
    }

    private struct Event: Decodable {
        struct Failure: Decodable { var message: String? }
        struct Response: Decodable {
            struct Incomplete: Decodable { var reason: String? }
            var incompleteDetails: Incomplete?
            var error: Failure?

            enum CodingKeys: String, CodingKey {
                case incompleteDetails = "incomplete_details"
                case error
            }
        }
        var type: String?
        var delta: String?
        var message: String?
        var response: Response?
        var error: Failure?
    }
}

/// The Gemini `alt=sse` stream: a `data:` payload per generated chunk, the finish reason on the
/// last one.
struct GeminiStream: SSEReplyDecoder {
    private var builder = ""
    private var finishReason: String?
    private var blocked = false

    mutating func read(_ payload: String) throws -> String? {
        guard let event = try? JSONDecoder().decode(Event.self, from: Data(payload.utf8)) else {
            return nil
        }
        if event.promptFeedback?.blockReason != nil { blocked = true; return nil }
        let candidate = event.candidates?.first
        if let reason = candidate?.finishReason { finishReason = reason }
        // A thinking part is not the answer, as in the complete reply.
        let text = (candidate?.content?.parts ?? []).filter { $0.thought != true }.compactMap(\.text)
            .joined()
        guard !text.isEmpty else { return nil }
        builder += text
        return text
    }

    /// The same rules `GeminiBackend.content` applies to a whole reply.
    func content() throws -> String {
        if blocked { throw ModelError.refused }
        switch finishReason {
        case nil, "STOP", "FINISH_REASON_UNSPECIFIED": break
        case "MAX_TOKENS", "CONTINUATION": throw ModelError.truncated
        default: throw ModelError.refused
        }
        guard !builder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ModelError.emptyResponse
        }
        return builder
    }

    private struct Event: Decodable {
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
