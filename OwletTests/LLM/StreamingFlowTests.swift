import Foundation
import Synchronization
import Testing

@testable import Owlet

/// A request transport whose response body arrives as a stream like a live one: chunks with a
/// pause (or a hold a test releases) between them. It counts what it was asked to send.
final class StreamStub: @unchecked Sendable {
    private let frames: [String]
    private let pause: Duration
    /// After the first frame the stream waits until `release()` before going on.
    private let holding: Bool
    private let waiting = Mutex<[CheckedContinuation<Void, Never>]>([])

    /// Requests this stub saw, in arrival order.
    let requests = Mutex<[URLRequest]>([])

    init(_ frames: [String], pause: Duration = .milliseconds(20), holding: Bool = false) {
        self.frames = frames
        self.pause = pause
        self.holding = holding
    }

    func release() { waiting.withLock { $0.removeFirst() }.resume() }

    var count: Int { requests.withLock { $0.count } }

    var streamTransport: StreamTransport {
        { [self] request in
            self.requests.withLock { $0.append(request) }
            let frames = frames
            let holds = holding
            let pause = pause
            let stream = AsyncThrowingStream(bufferingPolicy: .unbounded) { continuation in
                let sending = Task<Void, Never> {
                    do {
                        for (index, frame) in frames.enumerated() {
                            if index > 0 { try await Task.sleep(for: pause) }
                            for byte in Array(frame.utf8) { continuation.yield(byte) }
                            if holds, index == 0 {
                                await withCheckedContinuation { continuation in
                                    self.waiting.withLock { $0.append(continuation) }
                                }
                            }
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in sending.cancel() }
            }
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (stream, response)
        }
    }
}

/// One chat-completions SSE frame whose delta reveals `piece` of the raw answer.
func chatStreamFrame(_ piece: String) -> String {
    do {
        let frame = try JSONSerialization.data(
            withJSONObject: ["choices": [["delta": ["content": piece]]]])
        return "data: \(String(decoding: frame, as: UTF8.self))\n\n"
    } catch {
        fatalError("a chat stream frame must always build")
    }
}

/// The client a streaming test drives: the whole-shot route cannot run by accident, and the stream
/// is the fixture.
func streamingClient(_ stub: StreamStub) -> ModelClient {
    var client = ModelClient()
    client.capture = .off
    client.transport = { _ in
        Issue.record("with a stream fixture, the whole-shot transport must never run")
        throw TestTransportError()
    }
    client.streamTransport = stub.streamTransport
    return client
}

struct TestTransportError: Error, LocalizedError, CustomStringConvertible {
    var description: String { "the transport failed" }
    var errorDescription: String? { "the transport failed" }
}

extension TestReplies {
    /// A valid `$defs.lookup` raw answer, so a streaming fixture can hand it out in pieces.
    static let lookupContent =
        #"""
        {"text":"bank","language":"en","definition_language":"zh-Hans","meaning":"河岸","lemma":null,"pronunciation":null,"part_of_speech":null}
        """#
}

/// BDR-0017: from the client down, a stream is seen while it arrives and judged only once it is
/// complete — and a caller without a stream seam degrades to one whole piece through its own
/// `transport` seam.
@Suite struct StreamingFlowTests {
    let content = TestReplies.reply(for: "Hello")

    @Test func thePanelSeesPiecesAndTheContractJudgesTheWhole() async throws {
        let stub = StreamStub([
            chatStreamFrame(String(content.prefix(content.count / 2))),
            chatStreamFrame(String(content.dropFirst(content.count / 2))),
            "data: [DONE]\n\n",
        ])
        let client = streamingClient(stub)
        let seen = Mutex<[String]>([])
        let reply = try await client.translate("Hello", to: "zh-Hans", config: testConfig) {
            accumulated in
            seen.withLock { $0.append(accumulated) }
        }
        #expect(reply == "T:Hello")
        // Each reveal reached the handler while the answer was still a prefix of it.
        #expect(seen.withLock { $0 } == [String(content.prefix(content.count / 2)), content])
        // The wire asked for a stream.
        let body =
            try JSONSerialization.jsonObject(
                with: try #require(stub.requests.withLock { $0.first?.httpBody })
            ) as? [String: Any]
        #expect(body?["stream"] as? Bool == true)
    }

    @Test func withoutAStreamTransportOneStubServesTheWholeShot() async throws {
        var client = ModelClient(transport: stub(body: chatBody(content)))
        client.capture = .off
        let seen = Mutex<[String]>([])
        let reply = try await client.translate("Hello", to: "zh-Hans", config: testConfig) {
            accumulated in
            seen.withLock { $0.append(accumulated) }
        }
        // The automatic degradation of BDR-0017 §4: the whole answer, once.
        #expect(reply == "T:Hello")
        #expect(seen.withLock { $0 } == [content])
    }
}

/// What a still-arriving reply may show: `PartialReply` extracts structure that has closed and
/// nothing that has not.
@Suite struct PartialReplyTests {
    @Test func segmentsShowOnlyPairsTheReplyHasClosed() {
        let done =
            #"{"note":"both","segments":[{"source":"He","target":"他"},{"source":"\"sat\"","target":"坐"}]}"#
        // The pair inside plain prose is not a segment scan; the listed pairs are.
        #expect(
            PartialReply.segments(from: done) == [
                .init(source: "He", target: "他"), .init(source: #""sat""#, target: "坐"),
            ])
        // A pair still being written shows nothing, even though an earlier pair is ready.
        let tailOpen = #"{"segments":[{"source":"He","target":"他"},{"source":"sat","target":""#
        #expect(PartialReply.segments(from: tailOpen) == [.init(source: "He", target: "他")])
        #expect(PartialReply.segments(from: #"{"segments""#) == [])
        #expect(PartialReply.segments(from: "") == [])
    }

    @Test func segmentsApplyTheContractPairRules() {
        // A blank source may pair with an empty target; a word with no target cannot.
        #expect(
            PartialReply.segments(from: #"{"segments":[{"source":"  ","target":""}]}"#)
                == [.init(source: "  ", target: "")])
        #expect(PartialReply.segments(from: #"{"segments":[{"source":"He","target":""}]}"#) == [])
        // A pair whose source is only its own escape survives unescaping, never as raw JSON.
        #expect(
            PartialReply.segments(from: #"{"segments":[{"source":"a\"b","target":"a\"b"}]}"#)
                == [.init(source: #"a"b"#, target: #"a"b"#)])
    }

    @Test func meaningShowsOnlyOnceItsValueClosed() {
        // Still open: nothing, however far the value got.
        #expect(PartialReply.meaning(from: "{\"meaning\":") == nil)
        #expect(PartialReply.meaning(from: "{\u{22}meaning\u{22}") == nil)
        #expect(PartialReply.meaning(from: "{\"meaning\":\"河") == nil)
        // Closed: unescaped, and only then.
        #expect(PartialReply.meaning(from: #"{"meaning":"河岸"}"#) == "河岸")
        #expect(PartialReply.meaning(from: #"{"meaning":"河岸\"河\""}"#) == #"河岸"河""#)
        // An empty value is not an explanation.
        #expect(PartialReply.meaning(from: #"{"meaning":""}"#) == nil)
        // The header inside prose can only move where the display starts; the parser judges anyway.
        #expect(PartialReply.meaning(from: #"{"note":"meaning"}"#) == nil)
    }
}

/// Receiving through the whole model flow: partial pairs reach the page (or the panel) while the
/// request still runs, and nothing partial survives success, failure, supersede or cancel.
@MainActor @Suite struct StreamingReceivingTests {
    let content = TestReplies.reply(for: "Hello")

    @Test func receivingShowsWhileLoadingAndClearsOnSuccess() async throws {
        let model = TextProcessingModel(
            client: streamingClient(
                StreamStub([chatStreamFrame(content), "data: [DONE]\n\n"], pause: .milliseconds(300))
            ),
            config: { testConfig })
        model.input = "Hello"
        var expansions = 0
        model.process(to: "zh-Hans", onFirstPartial: { expansions += 1 })
        for _ in 0..<200 where model.receiving == nil { try? await Task.sleep(for: .milliseconds(5)) }
        #expect(model.isReceiving)
        #expect(model.receiving == [.init(source: "Hello", target: "T:Hello")])
        #expect(expansions == 1)
        for _ in 0..<200 where model.isReceiving { try? await Task.sleep(for: .milliseconds(5)) }
        #expect(model.state == .success("T:Hello"))
        #expect(model.receiving == nil)
    }

    @Test func receivingSurvivesNothingOnceCancelledOrSuperseded() async throws {
        // The stream shows its piece, then stays open, so a cancel catches it mid-arrival.
        let frames = [chatStreamFrame(content), "data: [DONE]\n\n"]
        let model = TextProcessingModel(
            client: streamingClient(StreamStub(frames, pause: .seconds(60))), config: { testConfig })
        model.input = "Hello"
        model.process(to: "zh-Hans")
        for _ in 0..<200 where model.receiving == nil { try? await Task.sleep(for: .milliseconds(5)) }
        #expect(model.receiving != nil)
        model.cancel()
        #expect(model.state == .idle)
        #expect(model.receiving == nil)
        // A superseding request must clear its predecessor's partial in the same way.
        let model2 = TextProcessingModel(
            client: streamingClient(StreamStub(frames, pause: .seconds(60))), config: { testConfig })
        model2.input = "Hello"
        model2.process(to: "zh-Hans")
        for _ in 0..<200 where model2.receiving == nil { try? await Task.sleep(for: .milliseconds(5)) }
        model2.input = "Something else"
        #expect(model2.receiving == nil)
    }

    @Test func aFailureLeavesNoPartialBehind() async throws {
        // The decoder's refusal check fails the stream at its end, exactly like the whole shot:
        // what the panel saw meanwhile never outlives the failure.
        var client = ModelClient()
        client.capture = .off
        client.transport = { _ in throw TestTransportError() }
        client.streamTransport =
            StreamStub([
                chatStreamFrame(#"open, but never a result"#),
                "data: " + #"{"choices":[{"delta":{"refusal":"I will not"}}]}"# + "\n\n",
            ]).streamTransport
        let model = TextProcessingModel(client: client, config: { testConfig })
        model.input = "Hello"
        model.process(to: "zh-Hans")
        for _ in 0..<200 where model.state == .loading { try? await Task.sleep(for: .milliseconds(5)) }
        if case .failure = model.state {} else { Issue.record("the refusal must surface") }
        #expect(model.receiving == nil)
    }
}

/// The lookup's own receiving state: the meaning shows in the card while the request runs, without
/// ever counting as an answer.
@MainActor @Suite struct LookupReceivingTests {
    func makeStore(_ stub: StreamStub) -> LookupStore {
        LookupStore(
            client: streamingClient(stub), config: { testConfig }, defaults: lookupDefaults)
    }

    @Test func theCardShowsTheMeaningWhileItStillArrives() async throws {
        let query = try query("bank", in: "We sat on the bank of the river.")
        let stub = StreamStub(
            [chatStreamFrame(TestReplies.lookupContent), "data: [DONE]\n\n"],
            pause: .milliseconds(300))
        let store = makeStore(stub)
        let stamped = store.stamped(query)
        store.open(stamped)
        for _ in 0..<200 where store.entries[stamped] == .loading {
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(store.entries[stamped] == .receiving("河岸"))
        // While still receiving, the same query joins the request instead of asking again.
        store.open(stamped)
        #expect(stub.count == 1)
        for _ in 0..<200 where store.entries[stamped] == .receiving("河岸") {
            try? await Task.sleep(for: .milliseconds(5))
        }
        if case .success(let answer) = store.entries[stamped] {
            #expect(answer.meaning == "河岸")
        } else {
            Issue.record("the stream must settle in a success")
        }
    }

    @Test func aMeaningStillOpenShowsNothingAtAll() async throws {
        // The stream stays open with a prefix of the reply: no `meaning` value has closed, so the
        // card keeps showing plain loading and no answer exists to collect.
        let query = try query("bank", in: "We sat on the bank of the river.")
        let store = makeStore(
            StreamStub(
                [
                    "data: "
                        + #"{"choices":[{"delta":{"content":"{\"text\":\"bank\""}}]}"# + "\n\n",
                    "data: [DONE]\n\n",
                ], pause: .seconds(60)))
        let stamped = store.stamped(query)
        store.open(stamped)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(store.entries[stamped] == .loading)
    }
}
