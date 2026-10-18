import Foundation
import Testing

@testable import Owlet

/// Translation Display: the preference persists, the response pairs are exposed for Sentence by Sentence, and switching
/// the mode never spends a model request.
@MainActor
struct DisplayModeTests {
    final class Calls: @unchecked Sendable { var count = 0 }

    func model(_ calls: Calls, reply: String) -> TextProcessingModel {
        TextProcessingModel(
            client: ModelClient(transport: { request in
                calls.count += 1
                return try await stub(body: chatBody(reply))(request)
            }),
            config: { testConfig })
    }

    @Test func defaultDisplayModeIsSectioned() {
        let defaults = UserDefaults(suiteName: "DisplayModeTests.\(UUID().uuidString)")!
        #expect(SettingsStore.displayMode(in: defaults) == .sectioned)
    }

    @Test func displayModePersists() {
        let defaults = UserDefaults(suiteName: "DisplayModeTests.\(UUID().uuidString)")!
        defaults.set(TranslationDisplayMode.aligned.rawValue, forKey: SettingsStore.displayModeKey)
        #expect(SettingsStore.displayMode(in: defaults) == .aligned)
    }

    /// The pairs come straight from the response, so Sentence by Sentence never splits on punctuation, and both
    /// copy and write-back still read the joined targets.
    @Test func successfulResultKeepsTheResponsePairs() async {
        let reply =
            #"{"source_language":"en","target_language":"zh-Hans","segments":[{"source":"Good morning. ","target":"早上好。"},{"source":"Let's begin.","target":"我们开始吧。"}]}"#
        let model = model(Calls(), reply: reply)
        model.input = "Good morning. Let's begin."
        await model.process(to: "zh-Hans")?.value
        #expect(model.segments.map(\.source) == ["Good morning. ", "Let's begin."])
        #expect(model.segments.map(\.target) == ["早上好。", "我们开始吧。"])
        #expect(model.displayPairs.map(\.target) == model.segments.map(\.target))
        guard case .success(let text) = model.state else {
            Issue.record("expected a successful result")
            return
        }
        #expect(text == model.segments.map(\.target).joined())
    }

    /// Changing the preference only changes the layout, so no request is issued.
    @Test func switchingDisplayModeDoesNotRequestAgain() async {
        let calls = Calls()
        let model = model(calls, reply: TestReplies.reply(for: "Hello"))
        model.input = "Hello"
        await model.process(to: "zh-Hans")?.value
        #expect(calls.count == 1)
        let defaults = UserDefaults(suiteName: "DisplayModeTests.\(UUID().uuidString)")!
        defaults.set(TranslationDisplayMode.aligned.rawValue, forKey: SettingsStore.displayModeKey)
        #expect(SettingsStore.displayMode(in: defaults) == .aligned)
        #expect(calls.count == 1)
        #expect(model.state == .success("T:Hello"))
    }

    /// The new text drops the pairs together with the result they describe.
    @Test func changingTheTextDropsThePairs() async {
        let model = model(Calls(), reply: TestReplies.reply(for: "Hello"))
        model.input = "Hello"
        await model.process(to: "zh-Hans")?.value
        #expect(!model.segments.isEmpty)
        model.input = "Goodbye"
        #expect(model.segments.isEmpty)
    }

    /// The pairs a reply is still arriving in are displayable while it waits: Sentence by Sentence shows them
    /// grouped from the first closed pair on, and the source field folds away then. Nothing is displayable
    /// before the first pair closes, so the panel still shows the source it is waiting on.
    @Test func arrivingPairsAreDisplayable() async {
        let model = TextProcessingModel(
            client: streamingClient(
                StreamStub([chatStreamFrame(Self.arriving)], pause: .seconds(60), holding: true)),
            config: { testConfig })
        defer { model.cancel() }
        #expect(model.displayPairs.isEmpty)
        model.input = "Good morning. Let's begin."
        _ = model.process(to: "zh-Hans")
        for _ in 0..<400 where model.displayPairs.isEmpty {
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(model.displayPairs.map(\.target) == ["早上好。"])
        #expect(model.isReceiving)
    }

    /// One pair closed, the next still being written, so only the closed one is displayable.
    static let arriving =
        #"{"source_language":"en","target_language":"zh-Hans","segments":[{"source":"Good morning. ","target":"早上好。"},{"source":"Let's begin.","target":"我们开"#
}
