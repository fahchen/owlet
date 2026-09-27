import Foundation
import Testing

@testable import Owlet

/// Switching the operation re-runs the text at once, and switching back is served from a cache that
/// belongs to that one text.
@MainActor
struct OperationSwitchTests {
    /// Counts requests; only touched from the main actor and the transport closure.
    final class Calls: @unchecked Sendable { var count = 0 }

    /// A transport that answers every request and counts them.
    func countingModel(_ calls: Calls) -> TranslationModel {
        TranslationModel(
            client: ModelClient(transport: { request in
                calls.count += 1
                let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
                let text = (body["messages"] as! [[String: String]]).last!["content"]!
                return try await stub(body: chatBody(TestReplies.reply(for: text)))(request)
            }),
            config: { testConfig })
    }

    @Test func switchingBackServesTheCachedResult() async {
        let calls = Calls()
        let model = countingModel(calls)
        model.input = "Hello"
        await model.translate(to: "zh-Hans")?.value
        #expect(model.state == .success("T:Hello"))
        #expect(calls.count == 1)

        model.operation = .polish
        await model.translate(to: "zh-Hans")?.value
        #expect(calls.count == 2)

        // Back to the first operation: the same text and settings are already answered.
        model.operation = .translate
        await model.translate(to: "zh-Hans")?.value
        #expect(model.state == .success("T:Hello"))
        #expect(calls.count == 2)
    }

    /// The cache lives with the text: a new text must be sent, even for an operation already run.
    @Test func changingTheTextDropsTheCache() async {
        let calls = Calls()
        let model = countingModel(calls)
        model.input = "Hello"
        await model.translate(to: "zh-Hans")?.value
        model.input = "Goodbye"
        await model.translate(to: "zh-Hans")?.value
        #expect(calls.count == 2)
    }

    /// A different target language is a different result for the same text.
    @Test func aDifferentLanguageIsNotCached() async {
        let calls = Calls()
        let model = countingModel(calls)
        model.input = "Hello"
        await model.translate(to: "zh-Hans")?.value
        await model.translate(to: "en")?.value
        #expect(calls.count == 2)
    }

    /// What the views ask before re-running on a switch: nothing to re-run until this text has been
    /// sent once.
    @Test func nothingHasBeenSentBeforeTheFirstRequest() async {
        let model = countingModel(Calls())
        #expect(!model.hasBeenSent)
        model.input = "Hello"
        #expect(!model.hasBeenSent)
        await model.translate(to: "zh-Hans")?.value
        #expect(model.hasBeenSent)
    }

    /// A cached answer still comes back as a finished task, which is what the panel's one-shot
    /// write-back awaits before writing the result into the other app.
    @Test func aCachedAnswerStillReturnsAFinishedTask() async {
        let calls = Calls()
        let model = countingModel(calls)
        model.input = "Hello"
        await model.translate(to: "zh-Hans")?.value
        let again = model.translate(to: "zh-Hans")
        #expect(again != nil)
        await again?.value
        #expect(calls.count == 1)
    }

    /// A failure is not cached: retrying it must reach the model again.
    @Test func failuresAreNotCached() async {
        let calls = Calls()
        let model = TranslationModel(
            client: ModelClient(transport: { _ in
                calls.count += 1
                throw ModelError.http(500)
            }),
            config: { testConfig })
        model.input = "Hello"
        await model.translate(to: "zh-Hans")?.value
        await model.translate(to: "zh-Hans")?.value
        #expect(calls.count == 2)
    }
}
