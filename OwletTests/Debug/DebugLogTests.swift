import Foundation
import Testing

@testable import Owlet

/// The debug page is off by default, keeps only recent exchanges in memory, and explains the check
/// that actually failed so a contract failure can be diagnosed from a copy of the raw data.
@MainActor
struct DebugLogTests {
    final class Box: @unchecked Sendable { var exchanges: [DebugExchange] = [] }

    @Test func theLogKeepsTheNewestFirstAndBounded() {
        let log = DebugLog()
        for index in 0..<(DebugLog.limit + 3) {
            log.add(DebugExchange(title: "第 \(index) 次", request: "{}", submitted: "x"))
        }
        #expect(log.exchanges.count == DebugLog.limit)
        #expect(log.exchanges.first?.title == "第 \(DebugLog.limit + 2) 次")
        log.clear()
        #expect(log.exchanges.isEmpty)
    }

    /// The API key travels in a header, so a copied report must not carry it.
    @Test func theReportCarriesTheExchangeButNotTheKey() {
        let exchange = DebugExchange(
            title: "翻译 · zh-Hant", request: #"{"model":"m"}"#, submitted: "お世話になっております。",
            response: #"{"source_language":"ja"}"#, failure: ModelError.format.message)
        let report = exchange.report
        #expect(report.contains("翻译 · zh-Hant"))
        #expect(report.contains(ModelError.format.message))
        #expect(report.contains("お世話になっております。"))
        #expect(report.contains(#"{"model":"m"}"#))
        #expect(!report.lowercased().contains("bearer"))
        #expect(!report.lowercased().contains("sk-"))
    }

    /// Only a source mismatch gets the comparison, so the hint never claims the wrong check failed.
    @Test func aSourceMismatchPointsAtTheFirstDifferentCharacter() {
        let exchange = DebugExchange(
            title: "翻译 · zh-Hant", request: "{}", submitted: "お世話になっております。",
            response:
                #"{"source_language":"ja","target_language":"zh-Hant","segments":[{"source":"お世話になりました。","target":"x"}]}"#,
            failure: ModelError.sourceMismatch.message)
        let divergence = exchange.sourceDivergence
        #expect(divergence?.contains("首个差异") == true)
        #expect(divergence?.contains("お世話になり") == true)
    }

    @Test func otherFailuresCarryNoSourceComparison() {
        let exchange = DebugExchange(
            title: "翻译 · zh-Hant", request: "{}", submitted: "x",
            response: #"{"segments":[]}"#, failure: ModelError.format.message)
        #expect(exchange.sourceDivergence == nil)
    }

    /// A finished request is handed to the capture, with the body actually sent and the raw reply.
    @Test func aRequestIsRecordedWhenTheCaptureIsOn() async {
        let box = Box()
        var client = ModelClient(transport: stub(body: chatBody(TestReplies.reply(for: "Hello"))))
        client.capture = DebugCapture(
            isEnabled: { true }, record: { box.exchanges.append($0) })
        _ = try? await client.process(
            "Hello", operation: .translate, to: "zh-Hans", config: testConfig)
        await settle(box)
        #expect(box.exchanges.count == 1)
        #expect(box.exchanges.first?.title == "翻译 · zh-Hans")
        #expect(box.exchanges.first?.failure == nil)
        #expect(box.exchanges.first?.request.contains("zh-Hans") == true)
        #expect(box.exchanges.first?.response?.contains("source_language") == true)
    }

    /// A failed request keeps the raw reply too: that is the whole point of the page.
    @Test func aFailedRequestKeepsTheRawReply() async {
        let box = Box()
        let content =
            #"{"source_language":"en","target_language":"ja","segments":[{"source":"Hello","target":"你好"}]}"#
        var client = ModelClient(transport: stub(body: chatBody(content)))
        client.capture = DebugCapture(
            isEnabled: { true }, record: { box.exchanges.append($0) })
        _ = try? await client.process(
            "Hello", operation: .translate, to: "zh-Hans", config: testConfig)
        await settle(box)
        #expect(
            box.exchanges.first?.failure
                == ModelError.targetMismatch(
                    requested: "zh-Hans", returned: "ja"
                ).message)
        #expect(box.exchanges.first?.response?.contains("\"ja\"") == true)
    }

    @Test func nothingIsRecordedWhenTheCaptureIsOff() async {
        let box = Box()
        var client = ModelClient(transport: stub(body: chatBody(TestReplies.reply(for: "Hello"))))
        client.capture = DebugCapture(isEnabled: { false }, record: { box.exchanges.append($0) })
        _ = try? await client.process(
            "Hello", operation: .translate, to: "zh-Hans", config: testConfig)
        for _ in 0..<20 { await Task.yield() }
        #expect(box.exchanges.isEmpty)
    }

    /// The record is handed off from a detached task, so the assertion waits for it.
    private func settle(_ box: Box) async {
        for _ in 0..<200 where box.exchanges.isEmpty { await Task.yield() }
    }
}
