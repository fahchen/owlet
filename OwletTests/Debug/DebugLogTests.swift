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

    /// A collapsed row shows the sent text on one line, so a multi-line selection must not make the
    /// row grow.
    @Test func theSummaryKeepsARowOnOneLine() {
        let exchange = DebugExchange(
            title: "翻译 · zh-Hant", request: "{}", submitted: "お世話になっております。\n株式会社PeopleX")
        #expect(exchange.summary == "お世話になっております。 株式会社PeopleX")
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

    /// The switch is the only consent for keeping the user's text, so it must decide both whether to
    /// record and whether what was already recorded survives.
    @Test func theSwitchDecidesRecordingAndClearsWhenTurnedOff() {
        let defaults = UserDefaults(suiteName: "DebugLogTests.settings.\(UUID().uuidString)")!
        #expect(!SettingsStore.isDebugEnabled(in: defaults))
        defaults.set(true, forKey: SettingsStore.debugEnabledKey)
        #expect(SettingsStore.isDebugEnabled(in: defaults))

        let log = DebugLog()
        log.add(DebugExchange(title: "翻译", request: "{}", submitted: "x"))
        #expect(log.exchanges.count == 1)
        log.clear()
        #expect(log.exchanges.isEmpty)
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

    /// The learning recommendations are a request of their own, so they must appear on the debug page
    /// like the main request does.
    @Test func aLearningRequestIsRecorded() async {
        let box = Box()
        var client = ModelClient(
            transport: stub(
                body: chatBody(
                    #"{"items":[{"text":"Hello","language":"en","kind":"word","meaning":"你好","context":"Hello"}]}"#)))
        client.capture = DebugCapture(
            isEnabled: { true }, record: { box.exchanges.append($0) })
        _ = try? await client.learning(
            text: "Hello", operation: .translate, targetLanguage: "zh-Hans", result: "你好",
            config: testConfig)
        await settle(box)
        #expect(box.exchanges.count == 1)
        #expect(box.exchanges.first?.title == "学习推荐")
        #expect(box.exchanges.first?.request.contains("original") == true)
        #expect(box.exchanges.first?.response?.contains("items") == true)
    }

    /// The on-demand meaning fill is a request of its own, so it must appear on the debug page too.
    @Test func aMeaningFillIsRecorded() async {
        let box = Box()
        var client = ModelClient(
            transport: stub(
                body: chatBody(
                    #"{"items":[{"text":"follow up","language":"en","kind":"phrase","meaning":"跟进","context":"follow up"}]}"#
                )))
        client.capture = DebugCapture(
            isEnabled: { true }, record: { box.exchanges.append($0) })
        _ = try? await client.fillMeaning(
            expression: "follow up", language: "en", context: "follow up", config: testConfig)
        await settle(box)
        #expect(box.exchanges.count == 1)
        #expect(box.exchanges.first?.title == "补释义")
        #expect(box.exchanges.first?.request.contains("expression") == true)
        #expect(box.exchanges.first?.response?.contains("items") == true)
    }

    /// The record is handed off from a detached task, so the assertion waits for it.
    private func settle(_ box: Box) async {
        for _ in 0..<200 where box.exchanges.isEmpty { await Task.yield() }
    }
}
