import Foundation
import Synchronization
import Testing

@testable import Owlet

private let learningPayload = learningJSON(
    #"{"items":[{"text":"take a step back","language":"en","kind":"phrase","meaning":"退一步重新审视。","context":"Let's take a step back."}]}"#
)

/// The automatic 学习表达 request: off by default, on after a success when its switch is on, never
/// for a failure, and never retroactively for a result the user already saw.
@MainActor
struct LearningAutoRequestTests {
    /// A finished translation whose input is "Hello".
    func completedTranslation() async -> TextProcessingModel {
        let model = TextProcessingModel(
            client: ModelClient(transport: stub(body: chatBody(TestReplies.reply(for: "Hello")))),
            config: { testConfig })
        model.input = "Hello"
        await model.process(to: "zh-Hans")?.value
        return model
    }

    @Test func offByDefaultIssuesNoRequestAfterSuccess() async throws {
        let calls = Mutex(0)
        let suite = "LearningAutoRequestTests.off.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let main = await completedTranslation()
        let request = try #require(LearningRequest.from(main))
        let learning = LearningModel(
            client: ModelClient(transport: { request in
                calls.withLock { $0 += 1 }
                return try await stub(body: learningBody(learningPayload))(request)
            }),
            config: { testConfig })
        learning.autoRequest = { SettingsStore.autoRequestsLearning(for: $0, in: defaults) }

        learning.generateIfAutoRequested(for: request)
        await learning.task?.value
        #expect(calls.withLock { $0 } == 0)
    }

    @Test func enabledSwitchFiresExactlyOneRequestAfterSuccess() async throws {
        let calls = Mutex(0)
        let main = await completedTranslation()
        let request = try #require(LearningRequest.from(main))
        let learning = LearningModel(
            client: ModelClient(transport: { request in
                calls.withLock { $0 += 1 }
                return try await stub(body: learningBody(learningPayload))(request)
            }),
            config: { testConfig })
        learning.autoRequest = { (operation: Owlet.Operation) in operation == .translate }

        learning.generateIfAutoRequested(for: request)
        await learning.task?.value
        #expect(calls.withLock { $0 } == 1)
        #expect(learning.state == .success(try LearningResult.parse(learningPayload)))

        // A rebuilt view for the same result is not a new success, so it spends nothing.
        let rebuilt = LearningModel(
            client: ModelClient(transport: { request in
                calls.withLock { $0 += 1 }
                return try await stub(body: learningBody(learningPayload))(request)
            }),
            config: { testConfig })
        rebuilt.autoRequest = { (operation: Owlet.Operation) in operation == .translate }
        rebuilt.generateIfAutoRequested(for: request)
        await rebuilt.task?.value
        #expect(calls.withLock { $0 } == 1)
    }

    @Test func aFailedResultNeverAutoRequests() async {
        let main = TextProcessingModel(
            client: ModelClient(transport: { _ in throw URLError(.notConnectedToInternet) }),
            config: { testConfig })
        main.input = "Hello"
        await main.process(to: "zh-Hans")?.value
        if case .failure = main.state {
        } else {
            Issue.record("expected a failure, got \(main.state)")
        }

        // No request to build, and no decision left for a rebuilt view to spend.
        #expect(LearningRequest.from(main) == nil)
        #expect(!main.claimAutoLearningRequest())
    }

    @Test func turningTheSwitchOnAfterASeenResultDoesNotRetroGenerate() async throws {
        let calls = Mutex(0)
        let main = await completedTranslation()
        let request = try #require(LearningRequest.from(main))
        let learning = LearningModel(
            client: ModelClient(transport: { request in
                calls.withLock { $0 += 1 }
                return try await stub(body: learningBody(learningPayload))(request)
            }),
            config: { testConfig })
        learning.autoRequest = { (_: Owlet.Operation) in false }

        // The view appears while the switch is off: it consumes the result's one decision.
        learning.generateIfAutoRequested(for: request)
        await learning.task?.value
        #expect(calls.withLock { $0 } == 0)

        // Turning the switch on afterwards must not generate for the result already on screen.
        learning.autoRequest = { (_: Owlet.Operation) in true }
        learning.generateIfAutoRequested(for: request)
        await learning.task?.value
        #expect(calls.withLock { $0 } == 0)
    }

    @Test func polishUsesItsOwnSwitch() async {
        let calls = Mutex(0)
        let polish = LearningRequest(
            text: "Hello", operation: .polish, targetLanguage: "en", result: "Hello.")
        let learning = LearningModel(
            client: ModelClient(transport: { request in
                calls.withLock { $0 += 1 }
                return try await stub(body: learningBody(learningPayload))(request)
            }),
            config: { testConfig })
        learning.autoRequest = { (operation: Owlet.Operation) in operation == .translate }

        learning.generateIfAutoRequested(for: polish)
        await learning.task?.value
        #expect(calls.withLock { $0 } == 0)
    }

    @Test func manualExpandStillRequestsWhileTheSwitchIsOff() async throws {
        let calls = Mutex(0)
        let main = await completedTranslation()
        let request = try #require(LearningRequest.from(main))
        let learning = LearningModel(
            client: ModelClient(transport: { request in
                calls.withLock { $0 += 1 }
                return try await stub(body: learningBody(learningPayload))(request)
            }),
            config: { testConfig })
        learning.autoRequest = { (_: Owlet.Operation) in false }

        // The disclosure's own 生成 path ignores the switch but still spends one request.
        learning.generate(for: request)
        await learning.task?.value
        #expect(calls.withLock { $0 } == 1)
        #expect(learning.state == .success(try LearningResult.parse(learningPayload)))
    }

    /// The production default reads the shared settings, which is what the settings page writes.
    @Test func defaultAutoRequestMirrorsTheSavedSettings() {
        let learning = LearningModel()
        for operation in Owlet.Operation.allCases {
            #expect(
                learning.autoRequest(operation)
                    == SettingsStore.autoRequestsLearning(for: operation))
        }
    }
}
