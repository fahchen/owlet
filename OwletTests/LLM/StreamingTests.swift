import Foundation
import Testing

@testable import Owlet

// `TestTransportError` comes from `StreamingFlowTests.swift`.

/// BDR-0017: the display-only streaming layer — SSE framing, the shared status rules, one decoder
/// per protocol, and the rule that partial text is shown but never trusted.
@Suite struct StreamingTests {
    func byteStream(_ text: String) -> AsyncThrowingStream<UInt8, Error> {
        AsyncThrowingStream(bufferingPolicy: .unbounded) {
            for byte in Array(text.utf8) { $0.yield(byte) }
            $0.finish()
        }
    }

    func payloads(_ wire: String) async throws -> [String] {
        var read: [String] = []
        for try await payload in HTTPStreaming.events(from: byteStream(wire)) {
            read.append(payload)
        }
        return read
    }

    // MARK: Server-sent event framing

    @Test func framesSplitOnBlankLinesAndTolerateVariants() async throws {
        // CR-LF endings, an optional space after `data:`, and the final flush of a frame whose
        // terminator the service dropped.
        #expect(try await payloads("data: a\r\n\r\ndata: b\r\n\r\n") == ["a", "b"])
        #expect(try await payloads("data:a\ndata:b\n") == ["a\nb"])
        #expect(try await payloads("event: delta\ndata: one\ndata: two\n\n") == ["one\ntwo"])
        // Non-data fields and empty frames say nothing.
        #expect(try await payloads(": keep-alive\n\r\n:") == [])
    }

    // MARK: The shared status rules

    @Test func aFailedStatusIsJudgedOnHeadersAndItsBodyBecomesTheDetail() async throws {
        let url = URL(string: "https://example.test/v1")!
        await #expect(throws: ModelError.unauthorized) {
            try await HTTPStreaming.send(
                URLRequest(url: url),
                transport: { request in
                    (TestStream.empty(), StreamingTests.response(request, status: 403))
                })
        }
        await #expect(
            throws: ModelError.http(500, detail: "the error body")
        ) {
            try await HTTPStreaming.send(
                URLRequest(url: url),
                transport: { request in
                    (TestStream.body("the error body"), StreamingTests.response(request, status: 500))
                })
        }
        // Transport shapes stay: a cancellation is a cancellation, anything else is network.
        await #expect(throws: CancellationError.self) {
            try await HTTPStreaming.send(
                URLRequest(url: url), transport: { _ in throw CancellationError() })
        }
        await #expect(throws: ModelError.network("the transport failed")) {
            try await HTTPStreaming.send(
                URLRequest(url: url),
                transport: { _ in throw TestTransportError() })
        }
    }

    // MARK: The OpenAI Chat Completions stream

    @Test func openAIChatFoldsDeltasAndSkipsWhatItCannotRead() throws {
        var stream = OpenAIChatStream()
        #expect(try stream.read(#"{"choices":[{"delta":{"content":"Hel"}}]}"#) == "Hel")
        #expect(try stream.read(#"{"choices":[{"delta":{"content":"lo"}}]}"#) == "lo")
        // Keep-alive noise and shapes that are not reveal events are skipped, not fatal.
        #expect(try stream.read("garbage") == nil)
        #expect(try stream.read(#"{"choices":[{"delta":{"content":""}}]}"#) == nil)
        #expect(try stream.read("[DONE]") == nil)
        #expect(try stream.content() == "Hello")
    }

    @Test func openAIChatJudgesTruncationRefusalAndEmptinessAtTheEnd() throws {
        var refused = OpenAIChatStream()
        _ = try? refused.read(#"{"choices":[{"delta":{"content":"no"}}]}"#)
        _ = try? refused.read(#"{"choices":[{"delta":{"refusal":"I will not"}}]}"#)
        #expect(throws: ModelError.refused) { try refused.content() }

        var filtered = OpenAIChatStream()
        _ = try? filtered.read(#"{"choices":[{"delta":{},"finish_reason":"content_filter"}]}"#)
        #expect(throws: ModelError.refused) { try filtered.content() }

        var truncated = OpenAIChatStream()
        _ = try? truncated.read(#"{"choices":[{"delta":{"content":"Hel"}}]}"#)
        _ = try? truncated.read(#"{"choices":[{"delta":{},"finish_reason":"length"}]}"#)
        #expect(throws: ModelError.truncated) { try truncated.content() }

        // Late-on-set silence ends the way the whole shot does.
        #expect(throws: ModelError.emptyResponse) { try OpenAIChatStream().content() }
    }

    // MARK: The Anthropic Messages stream

    @Test func anthropicShowsTextDeltasOnlyAndJudgesAtTheEnd() throws {
        var stream = AnthropicStream()
        // The model's own thinking is not the answer.
        #expect(
            try stream.read(
                #"{"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"hmm"}}"#
            ) == nil)
        #expect(
            try stream.read(
                #"{"type":"content_block_delta","delta":{"type":"text_delta","text":"河"}}"#
            ) == "河")
        #expect(
            try stream.read(
                #"{"type":"content_block_delta","delta":{"type":"text_delta","text":"岸"}}"#
            ) == "岸")
        #expect(try stream.read(#"{"type":"message_delta","delta":{"stop_reason":"end_turn"}}"#) == nil)
        #expect(try stream.content() == "河岸")

        var truncated = AnthropicStream()
        _ = try? truncated.read(
            #"{"type":"content_block_delta","delta":{"type":"text_delta","text":"河"}}"#)
        _ = try? truncated.read(#"{"type":"message_delta","delta":{"stop_reason":"max_tokens"}}"#)
        #expect(throws: ModelError.truncated) { try truncated.content() }
        #expect(throws: ModelError.emptyResponse) { try AnthropicStream().content() }
    }

    @Test func anthropicErrorEventFailsTheStreamAtOnce() {
        var stream = AnthropicStream()
        _ = try? stream.read(
            #"{"type":"content_block_delta","delta":{"type":"text_delta","text":"河"}}"#)
        #expect(throws: ModelError.network("overloaded")) {
            try stream.read(#"{"type":"error","error":{"message":"overloaded"}}"#)
        }
    }

    // MARK: The OpenAI Responses stream

    @Test func responsesFoldsOutputTextAndMapsTerminals() throws {
        var stream = OpenAIResponsesStream()
        #expect(try stream.read(#"{"type":"response.output_text.delta","delta":"Hi"}"#) == "Hi")
        #expect(try stream.read(#"{"type":"response.output_text.delta","delta":"!"}"#) == "!")
        #expect(try stream.content() == "Hi!")

        var refused = OpenAIResponsesStream()
        _ = try? refused.read(#"{"type":"response.refusal.delta","delta":"no"}"#)
        #expect(throws: ModelError.refused) { try refused.content() }

        var truncated = OpenAIResponsesStream()
        _ = try? truncated.read(#"{"type":"response.output_text.delta","delta":"Hi"}"#)
        _ = try? truncated.read(
            #"{"type":"response.incomplete","response":{"incomplete_details":{"reason":"max_output_tokens"}}}"#)
        #expect(throws: ModelError.truncated) { try truncated.content() }

        var failed = OpenAIResponsesStream()
        _ = try? failed.read(#"{"type":"response.output_text.delta","delta":"Hi"}"#)
        _ = try? failed.read(#"{"type":"response.failed","response":{"error":{"message":"overloaded"}}}"#)
        #expect(throws: ModelError.network("overloaded")) { try failed.content() }

        // A top-level error event has its own failure words.
        var live = OpenAIResponsesStream()
        #expect(throws: ModelError.network("bad gateway")) {
            try live.read(#"{"type":"error","message":"bad gateway"}"#)
        }
    }

    // MARK: The Gemini `alt=sse` stream

    @Test func geminiFoldsPartsAndMapsFinishReasons() throws {
        var stream = GeminiStream()
        #expect(try stream.read(#"{"candidates":[{"content":{"parts":[{"text":"Bank"}]}}]}"#) == "Bank")
        #expect(try stream.read(#"{"candidates":[{"content":{"parts":[{"text":"river"}]}}]}"#) == "river")
        // A thinking part is not the answer, as in the complete reply.
        #expect(
            try stream.read(
                #"{"candidates":[{"content":{"parts":[{"text":"hmm","thought":true}]}}]}"#
            ) == nil)
        #expect(try stream.content() == "Bankriver")

        var truncated = GeminiStream()
        _ = try? truncated.read(#"{"candidates":[{"finishReason":"MAX_TOKENS"}]}"#)
        #expect(throws: ModelError.truncated) { try truncated.content() }

        var blocked = GeminiStream()
        _ = try? blocked.read(#"{"promptFeedback":{"blockReason":"SAFETY"}}"#)
        #expect(throws: ModelError.refused) { try blocked.content() }

        var odd = GeminiStream()
        _ = try? odd.read(#"{"candidates":[{"finishReason":"OTHER"}]}"#)
        #expect(throws: ModelError.refused) { try odd.content() }

        #expect(throws: ModelError.emptyResponse) { try GeminiStream().content() }
    }
}

/// The empty stream and any single body, under one name, for the status tests above.
private enum TestStream {
    static func empty() -> AsyncThrowingStream<UInt8, Error> {
        AsyncThrowingStream(bufferingPolicy: .unbounded) { $0.finish() }
    }

    static func body(_ text: String) -> AsyncThrowingStream<UInt8, Error> {
        AsyncThrowingStream(bufferingPolicy: .unbounded) {
            for byte in Array(text.utf8) { $0.yield(byte) }
            $0.finish()
        }
    }
}

extension StreamingTests {
    static func response(_ request: URLRequest, status: Int) -> URLResponse {
        HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
    }
}
