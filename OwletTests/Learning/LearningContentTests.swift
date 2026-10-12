import Foundation
import SwiftData
import Synchronization
import Testing

@testable import Owlet

/// Three recommendations that all appear in the sample result, used by the model and collection tests.
private let learningPayload = learningJSON(
    #"{"items":[{"text":"take a step back","language":"en","kind":"phrase","meaning":"退一步重新审视。","context":"Let's take a step back."},{"text":"the bigger picture","language":"en","kind":"phrase","meaning":"全局、整体情况。","context":"look at the bigger picture"},{"text":"move forward","language":"en","kind":"phrase","meaning":"继续推进。","context":"before we move forward"}]}"#
)
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
        #expect(items.first?.lemma == nil)
        // No padding: an empty list is a valid answer, not a failure.
        #expect(try LearningResult.parse(#"{"items":[]}"#).isEmpty)
    }

    /// The shape that used to fail every Japanese recommendation: the text is the inflected form as
    /// it appears in the sentence, and the dictionary form rides along in `lemma` (BDR-0009).
    @Test func aLemmaThatDiffersFromTheSentenceFormIsAccepted() throws {
        let content = learningJSON(
            #"{"items":[{"text":"跳ね上がっている","language":"ja","kind":"word","meaning":"急剧上升。","context":"物価が跳ね上がっている。","lemma":"跳ね上がる"}]}"#
        )
        let item = try #require(try LearningResult.parse(content).first)
        #expect(item.text == "跳ね上がっている")
        #expect(item.lemma == "跳ね上がる")
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
        // A lemma that says nothing new, or is only whitespace, is malformed rather than stored.
        #"{"items":[{"text":"follow up","language":"en","kind":"phrase","meaning":"跟进。","context":"I will follow up.","lemma":"follow up"}]}"#,
        #"{"items":[{"text":"follow up","language":"en","kind":"phrase","meaning":"跟进。","context":"I will follow up.","lemma":"  "}]}"#,
    ])
    func malformedPayloadsAreFormatErrors(content: String) {
        #expect(throws: ModelError.format) { try LearningResult.parse(learningJSON(content)) }
    }

    @Test func learningRequestReusesThePromptAndAddsTheContract() throws {
        let request = try clientWithBuiltInPrompt().learningRequest(
            text: "Let's take a step back.", operation: .translate, targetLanguage: "zh-Hans",
            result: "让我们退一步。", config: testConfig)
        #expect(request.system.hasPrefix(DefaultPrompts.translate))
        #expect(request.system.contains("json"))
        let user = try #require(request.turns.first?.content)
        #expect(user.contains("Let's take a step back."))
        #expect(user.contains("让我们退一步。"))
        let schema = try #require(schema(of: request))
        #expect(!String(decoding: schema.data, as: UTF8.self).contains("minLength"))
    }

    @Test func learningMapsResponseAndRequestFailures() async throws {
        let ok = ModelClient(transport: stub(body: learningBody(learningPayload)))
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
                return try await stub(body: learningBody(learningPayload))(request)
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
                return try await stub(body: learningBody(learningPayload))(request)
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
            return try await stub(body: learningBody(learningPayload))(request)
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
            client: ModelClient(transport: stub(body: learningBody(learningPayload))),
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

    /// A checked recommendation keeps the form it was collected as and the dictionary form beside it,
    /// so the notebook shows what the user saw without losing the lemma (BDR-0009).
    @Test func aCollectedRecommendationKeepsItsLemma() async throws {
        let payload = learningJSON(
            #"{"items":[{"text":"跳ね上がっている","language":"ja","kind":"word","meaning":"急剧上升。","context":"物価が跳ね上がっている。","lemma":"跳ね上がる"}]}"#
        )
        let store = try makeStore()
        let collection = CollectionAction(store: store, client: ModelClient(), config: { testConfig })
        let model = LearningModel(
            client: ModelClient(transport: stub(body: learningBody(payload))), config: { testConfig })

        model.generate(for: request)
        await model.task?.value
        model.selected = [0]
        model.collectSelected(into: collection, for: request)

        let entry = try #require(try store.entries().first)
        withExtendedLifetime(store) {
            #expect(entry.expression == "跳ね上がっている")
            #expect(entry.lemma == "跳ね上がる")
            // The meaning language the request asked for, recorded with the meaning it produced.
            #expect(entry.definitionLocale == "zh-Hans")
        }
    }

    /// The user's own failing reply, from the debug page on 2026-10-11: every item gave the
    /// dictionary form as `text`, so none of them appears in its context, and every `lemma` repeated
    /// the text. The corrective round must show the model exactly that and take the fixed answer.
    @Test func aReplyThatGivesDictionaryFormsIsCorrected() async throws {
        let rejected = """
            {"items":[{"text":"跳ね上がる","language":"ja","kind":"word","meaning":"急剧上涨。",\
            "context":"原油市場で受け渡しまでの期間が短い現物の取引価格が跳ね上がっている。","lemma":"跳ね上がる"}]}
            """
        let accepted = learningJSON(
            #"{"items":[{"text":"跳ね上がっている","language":"ja","kind":"word","meaning":"急剧上涨。","context":"原油市場で受け渡しまでの期間が短い現物の取引価格が跳ね上がっている。","lemma":"跳ね上がる"}]}"#
        )
        let calls = Mutex(0)
        let sentCorrection = Mutex(false)
        let client = ModelClient(transport: { request in
            let count = calls.withLock { value -> Int in
                value += 1
                return value
            }
            if count == 2 {
                let body = try JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any]
                let messages = body?["messages"] as? [[String: String]] ?? []
                // The second request carries the rejected reply back to the model, plus which rule
                // it broke, instead of repeating the same question.
                sentCorrection.withLock {
                    $0 =
                        messages.contains { $0["role"] == "assistant" && $0["content"] == rejected }
                        && messages.contains {
                            $0["role"] == "user" && ($0["content"]?.contains("not in its context") ?? false)
                        }
                }
            }
            return try await stub(body: chatBody(count == 1 ? rejected : accepted))(request)
        })

        let items = try await client.learning(
            text: "原油市場で…", operation: .translate, targetLanguage: "zh-Hans", result: "在原油市场…",
            config: testConfig)

        #expect(calls.withLock { $0 } == 2)
        #expect(sentCorrection.withLock { $0 })
        #expect(items.count == 1)
        #expect(items.first?.text == "跳ね上がっている")
        #expect(items.first?.lemma == "跳ね上がる")
    }

    /// One corrective round only: a model that cannot follow the contract still fails, and the third
    /// request is never sent.
    @Test func aSecondBadReplyIsNotCorrectedAgain() async throws {
        let bad = learningJSON(
            #"{"items":[{"text":"missing","language":"en","kind":"word","meaning":"无。","context":"I will follow up."}]}"#
        )
        let calls = Mutex(0)
        let client = ModelClient(transport: { request in
            calls.withLock { $0 += 1 }
            return try await stub(body: learningBody(bad))(request)
        })
        await #expect(throws: ModelError.format) {
            try await client.learning(
                text: "I will follow up.", operation: .translate, targetLanguage: "zh-Hans",
                result: "我会跟进。", config: testConfig)
        }
        #expect(calls.withLock { $0 } == 2)
    }

    /// A transport failure is not a contract failure: there is no reply to correct, so the request is
    /// not repeated.
    @Test func aTransportFailureIsNotRetried() async throws {
        let calls = Mutex(0)
        let client = ModelClient(transport: { _ in
            calls.withLock { $0 += 1 }
            throw URLError(.notConnectedToInternet)
        })
        await #expect(throws: (any Error).self) {
            try await client.learning(
                text: "Hello", operation: .translate, targetLanguage: "zh-Hans", result: "你好",
                config: testConfig)
        }
        #expect(calls.withLock { $0 } == 1)
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
                return try await stub(body: learningBody(learningPayload))(request)
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
