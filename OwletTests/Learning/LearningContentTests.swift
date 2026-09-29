import Foundation
import SwiftData
import Synchronization
import Testing

@testable import Owlet

/// Three recommendations that all appear in the sample result, used by the model and collection tests.
private let learningPayload =
    #"{"items":[{"text":"take a step back","language":"en","kind":"phrase","meaning":"退一步重新审视。","context":"Let's take a step back."},{"text":"the bigger picture","language":"en","kind":"phrase","meaning":"全局、整体情况。","context":"look at the bigger picture"},{"text":"move forward","language":"en","kind":"phrase","meaning":"继续推进。","context":"before we move forward"}]}"#

private let translationPayload =
    #"{"source_language":"en","target_language":"zh-Hans","segments":[{"source":"Let's take a step back.","target":"让我们退一步。"}]}"#

@MainActor
struct LearningContentTests {
    var request: LearningRequest {
        LearningRequest(
            text: "Let's take a step back and look at the bigger picture before we move forward.",
            operation: .translate, targetLanguage: "zh-Hans", result: "让我们退一步，从全局的角度看一看。")
    }

    func makeStore() throws -> VocabularyStore {
        let schema = Schema([VocabularyEntry.self, VocabularyContext.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return VocabularyStore(container: try ModelContainer(for: schema, configurations: [config]))
    }

    @Test func parsesEveryItemAndAllowsAnEmptyList() throws {
        let items = try LearningResult.parse(learningPayload)
        #expect(items.count == 3)
        #expect(items.first?.text == "take a step back")
        #expect(items.first?.kind == "phrase")
        #expect(items.first?.context == "Let's take a step back.")
        // No padding: an empty list is a valid answer, not a failure.
        #expect(try LearningResult.parse(#"{"items":[]}"#).isEmpty)
    }

    @Test(arguments: [
        "not json",
        #"{"items":"x"}"#,
        #"{"recommendations":[]}"#,
        #"{"items":[],"extra":1}"#,
        #"{"items":[{"text":"follow up","language":"en","kind":"idiom","meaning":"跟进。","context":"I will follow up."}]}"#,
        #"{"items":[{"text":"follow up","language":"en","kind":"phrase","meaning":"  ","context":"I will follow up."}]}"#,
        #"{"items":[{"text":"missing","language":"en","kind":"phrase","meaning":"跟进。","context":"I will follow up."}]}"#,
        #"{"items":[{"text":"follow up","language":"en","kind":"phrase","meaning":"跟进。"}]}"#,
        #"{"items":["nope"]}"#,
    ])
    func malformedPayloadsAreFormatErrors(content: String) {
        #expect(throws: ModelError.format) { try LearningResult.parse(content) }
    }

    @Test func learningRequestReusesThePromptAndAddsTheContract() throws {
        let request = try clientWithBuiltInPrompt().makeLearningRequest(
            text: "Let's take a step back.", operation: .translate, targetLanguage: "zh-Hans",
            result: "让我们退一步。", config: testConfig)
        let json = try #require(
            JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
        let messages = try #require(json["messages"] as? [[String: String]])
        #expect(messages.first?["content"]?.hasPrefix(DefaultPrompts.translate) == true)
        #expect(messages.first?["content"]?.contains("json") == true)
        let user = try #require(messages.last?["content"])
        #expect(user.contains("Let's take a step back."))
        #expect(user.contains("让我们退一步。"))
        let format = try #require(json["response_format"] as? [String: Any])
        #expect(format["type"] as? String == "json_schema")
        let schema = try JSONSerialization.data(withJSONObject: format["json_schema"]!)
        #expect(!String(decoding: schema, as: UTF8.self).contains("minLength"))
    }

    @Test func learningMapsResponseAndRequestFailures() async throws {
        let ok = ModelClient(transport: stub(body: chatBody(learningPayload)))
        let items = try await ok.learning(
            text: "x", operation: .translate, targetLanguage: "zh-Hans", result: "y",
            config: testConfig)
        #expect(items.count == 3)

        let bad = ModelClient(transport: stub(body: chatBody("nope")))
        await #expect(throws: ModelError.format) {
            try await bad.learning(
                text: "x", operation: .translate, targetLanguage: "zh-Hans", result: "y",
                config: testConfig)
        }

        let failing = ModelClient(transport: { _ in throw URLError(.notConnectedToInternet) })
        await #expect {
            try await failing.learning(
                text: "x", operation: .translate, targetLanguage: "zh-Hans", result: "y",
                config: testConfig)
        } throws: { error in
            if case .network = error as? ModelError { return true }
            return false
        }
    }

    @Test func noRequestUntilAskedOrAutoEnabled() async throws {
        let calls = Mutex(0)
        let model = LearningModel(
            client: ModelClient(transport: { request in
                calls.withLock { $0 += 1 }
                return try await stub(body: chatBody(learningPayload))(request)
            }),
            config: { testConfig })
        // The switch is injected so the assertion does not read the developer's own settings.
        model.autoRequest = { _ in false }

        model.generateIfAutoRequested(for: request)
        #expect(calls.withLock { $0 } == 0)
        #expect(model.state == .idle)

        model.autoRequest = { _ in true }
        model.generateIfAutoRequested(for: request)
        await model.task?.value
        #expect(calls.withLock { $0 } == 1)
        #expect(model.state == .success(try LearningResult.parse(learningPayload)))
    }

    @Test func secondExpandReusesTheGeneratedItems() async throws {
        let calls = Mutex(0)
        let model = LearningModel(
            client: ModelClient(transport: { request in
                calls.withLock { $0 += 1 }
                return try await stub(body: chatBody(learningPayload))(request)
            }),
            config: { testConfig })

        model.generate(for: request)
        await model.task?.value
        #expect(model.state == .success(try LearningResult.parse(learningPayload)))
        #expect(calls.withLock { $0 } == 1)

        // 收起 then 展开 must show what was already generated instead of paying again.
        model.isExpanded = false
        model.isExpanded = true
        model.generate(for: request)
        #expect(calls.withLock { $0 } == 1)
        #expect(model.state == .success(try LearningResult.parse(learningPayload)))
    }

    @Test func retryAfterFailureCostsExactlyOneRequest() async throws {
        let calls = Mutex(0)
        let client = ModelClient(transport: { request in
            let count = calls.withLock { value -> Int in
                value += 1
                return value
            }
            if count == 1 { throw URLError(.notConnectedToInternet) }
            return try await stub(body: chatBody(learningPayload))(request)
        })
        let model = LearningModel(client: client, config: { testConfig })

        model.generate(for: request)
        await model.task?.value
        if case .failure = model.state {
        } else {
            Issue.record("expected a failure, got \(model.state)")
        }
        model.retry(for: request)
        await model.task?.value
        #expect(model.state == .success(try LearningResult.parse(learningPayload)))
        #expect(calls.withLock { $0 } == 2)

        // A finished result is never re-requested, even through the plain generate path.
        model.generate(for: request)
        #expect(calls.withLock { $0 } == 2)
    }

    @Test func onlyCheckedItemsReachTheNotebook() async throws {
        let store = try makeStore()
        let collection = CollectionAction(
            store: store, client: ModelClient(), config: { testConfig })
        let model = LearningModel(
            client: ModelClient(transport: stub(body: chatBody(learningPayload))),
            config: { testConfig })

        model.generate(for: request)
        await model.task?.value
        model.selected = [0, 2]
        model.collectSelected(into: collection, for: request)

        let entries = try store.entries()
        withExtendedLifetime(store) {
            #expect(entries.count == 2)
            #expect(Set(entries.map(\.expression)) == ["take a step back", "move forward"])
            #expect(
                entries.first { $0.expression == "take a step back" }?.meaning == "退一步重新审视。")
        }
        // The meaning came with the recommendation, so collection never spent a second request.
        #expect(collection.status == .saved)

        // Collecting the same checked items again reuses the entries instead of duplicating them.
        model.collectSelected(into: collection, for: request)
        #expect(try store.entries().count == 2)
    }

    @Test func learningFailureLeavesTheMainResultUsable() async throws {
        let main = TextProcessingModel(
            client: ModelClient(transport: stub(body: chatBody(translationPayload))),
            config: { testConfig })
        main.input = "Let's take a step back."
        await main.process(to: "zh-Hans")?.value
        let request = try #require(LearningRequest.from(main))

        let learning = LearningModel(
            client: ModelClient(transport: { _ in throw URLError(.notConnectedToInternet) }),
            config: { testConfig })
        learning.generate(for: request)
        await learning.task?.value
        if case .failure = learning.state {
        } else {
            Issue.record("expected a learning failure, got \(learning.state)")
        }
        #expect(main.state == .success("让我们退一步。"))
    }

    @Test func resetDropsALateResponse() async throws {
        let model = LearningModel(
            client: ModelClient(transport: { request in
                try? await Task.sleep(for: .milliseconds(200))
                return try await stub(body: chatBody(learningPayload))(request)
            }),
            config: { testConfig })
        model.generate(for: request)
        let task = try #require(model.task)
        model.reset()
        await task.value
        #expect(model.state == .idle)
        #expect(model.selected.isEmpty)
    }
}
