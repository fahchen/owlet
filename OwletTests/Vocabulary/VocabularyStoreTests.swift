import Foundation
import SwiftData
import Synchronization
import Testing

@testable import Owlet

@MainActor
struct VocabularyStoreTests {
    /// One fresh in-memory container per test, per `tasks/plan.md`.
    func makeStore() throws -> VocabularyStore {
        let schema = Schema([VocabularyEntry.self, VocabularyContext.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return VocabularyStore(container: try ModelContainer(for: schema, configurations: [config]))
    }

    func draft(
        _ expression: String, language: String = "en", context: String = "I will follow up tomorrow."
    ) -> VocabularyDraft {
        VocabularyDraft(
            expression: expression, language: language, context: context, polishBefore: nil,
            polishAfter: nil)
    }

    @Test func persistsCollectedDraft() throws {
        let store = try makeStore()
        let entry = try store.collect(draft("follow up"))
        #expect(entry.expression == "follow up")
        #expect(entry.language == "en")
        #expect(entry.meaning.isEmpty)
        let contexts = try #require(entry.contexts.first)
        #expect(contexts.source == "I will follow up tomorrow.")
        let entries = try store.entries()
        #expect(entries.count == 1)
        #expect(entries.first?.expression == "follow up")
    }

    @Test func aFreshContextReadsTheSavedEntry() throws {
        let store = try makeStore()
        _ = try store.collect(draft("follow up"))
        let fresh = ModelContext(store.container)
        #expect(try fresh.fetch(FetchDescriptor<VocabularyEntry>()).count == 1)
    }

    @Test func trimsTheExpressionAndReusesTheEntry() throws {
        let store = try makeStore()
        _ = try store.collect(draft(" follow up "))
        let second = try store.collect(draft("follow up", context: "Another sentence."))
        #expect(try store.entries().count == 1)
        #expect(second.expression == "follow up")
        // Appending a second context is T11; T08 must only avoid a duplicate entry.
        #expect(second.contexts.count == 1)
    }

    @Test func separatesTheSameExpressionByLanguage() throws {
        let store = try makeStore()
        _ = try store.collect(draft("手紙", language: "zh", context: "中文句子"))
        _ = try store.collect(draft("手紙", language: "ja", context: "日本語の文"))
        #expect(try store.entries().count == 2)
    }

    @Test func deletingAnEntryCascadesToItsContexts() throws {
        let store = try makeStore()
        let entry = try store.collect(draft("follow up"))
        let context = store.container.mainContext
        #expect(try context.fetchCount(FetchDescriptor<VocabularyContext>()) == 1)
        context.delete(entry)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<VocabularyContext>()) == 0)
    }

    @Test func blankExpressionIsRejected() throws {
        let store = try makeStore()
        #expect(throws: VocabularyError.self) {
            try store.collect(draft("   "))
        }
    }

    @Test func keepsThePolishBeforeAndAfterPair() throws {
        let store = try makeStore()
        let entry = try store.collect(
            VocabularyDraft(
                expression: "This is bad.", language: "en", context: "This is bad.",
                polishBefore: "This are bad.", polishAfter: "This is bad."))
        let context = try #require(entry.contexts.first)
        #expect(context.polishBefore == "This are bad.")
        #expect(context.polishAfter == "This is bad.")
    }
}

@MainActor
struct CollectionActionTests {
    let meaningResponse =
        #"{"items":[{"text":"follow up","language":"en","kind":"phrase","meaning":"跟进，后续联系。","context":"I will follow up tomorrow."}]}"#

    func makeStore() throws -> VocabularyStore {
        let schema = Schema([VocabularyEntry.self, VocabularyContext.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return VocabularyStore(container: try ModelContainer(for: schema, configurations: [config]))
    }

    func draft() -> VocabularyDraft {
        VocabularyDraft(
            expression: "follow up", language: "en", context: "I will follow up tomorrow.",
            polishBefore: nil, polishAfter: nil)
    }

    @Test func failedMeaningRequestKeepsTheEntryAndRetryFillsIt() async throws {
        let store = try makeStore()
        let calls = Mutex(0)
        let client = ModelClient(transport: { request in
            let call = calls.withLock { count -> Int in
                count += 1
                return count
            }
            if call == 1 { throw URLError(.notConnectedToInternet) }
            return try await stub(body: chatBody(self.meaningResponse))(request)
        })
        let action = CollectionAction(store: store, client: client, config: { testConfig })
        let entry = try #require(action.collect(draft()))
        await action.task?.value
        // The failure must not undo the save.
        #expect(try store.entries().count == 1)
        #expect(entry.meaning.isEmpty)
        guard case .meaningFailed(let failed, _) = action.status else {
            Issue.record("expected a failed meaning request, got \(action.status)")
            return
        }
        #expect(failed == entry)

        action.fillMeaning(for: entry)
        await action.task?.value
        #expect(entry.meaning == "跟进，后续联系。")
        #expect(try store.entries().first?.meaning == "跟进，后续联系。")
        #expect(action.status == .saved)
    }

    @Test func emptyRecommendationListFailsWithoutLosingTheEntry() async throws {
        let store = try makeStore()
        let client = ModelClient(transport: stub(body: chatBody(#"{"items":[]}"#)))
        let action = CollectionAction(store: store, client: client, config: { testConfig })
        let entry = try #require(action.collect(draft()))
        await action.task?.value
        #expect(entry.meaning.isEmpty)
        if case .meaningFailed = action.status {
        } else {
            Issue.record("expected a failed meaning request, got \(action.status)")
        }
        #expect(try store.entries().count == 1)
    }

    @Test func missingConfigReportsAFailureWithoutDroppingTheEntry() async throws {
        let store = try makeStore()
        let action = CollectionAction(
            store: store, client: ModelClient(), config: { nil })
        let entry = try #require(action.collect(draft()))
        #expect(try store.entries().count == 1)
        guard case .meaningFailed(let failed, _) = action.status else {
            Issue.record("expected a missing-config failure, got \(action.status)")
            return
        }
        #expect(failed == entry)
    }
}

@MainActor
struct VocabularyDraftTests {
    func polishModel() async throws -> TranslationModel {
        let content =
            #"{"source_language":"en","target_language":"en","segments":[{"source":"This are bad.","target":"This is bad."}]}"#
        let model = TranslationModel(
            client: ModelClient(transport: stub(body: chatBody(content))), config: { testConfig })
        model.operation = .polish
        model.input = "This are bad."
        await model.translate(to: "zh-Hans")?.value
        return model
    }

    @Test func selectionWinsOverTheWholeResult() async throws {
        let model = try await polishModel()
        let selected = try #require(
            VocabularyDraft.from(region: .result, model: model, selection: "bad"))
        #expect(selected.expression == "bad")
        #expect(selected.language == "en")
        #expect(selected.context == "This is bad.")
    }

    @Test func blankSelectionFallsBackToTheWholeRegion() async throws {
        let model = try await polishModel()
        let result = try #require(
            VocabularyDraft.from(region: .result, model: model, selection: "   "))
        #expect(result.expression == "This is bad.")
        let source = try #require(
            VocabularyDraft.from(region: .source, model: model, selection: nil))
        #expect(source.expression == "This are bad.")
        #expect(source.context == "This are bad.")
    }

    @Test func polishKeepsTheBeforeAndAfterPair() async throws {
        let model = try await polishModel()
        let draft = try #require(
            VocabularyDraft.from(region: .result, model: model, selection: nil))
        #expect(draft.polishBefore == "This are bad.")
        #expect(draft.polishAfter == "This is bad.")
    }

    @Test func noResultMeansNothingToCollect() async throws {
        let model = TranslationModel(client: ModelClient(), config: { testConfig })
        model.input = "Hello"
        #expect(VocabularyDraft.from(region: .source, model: model, selection: nil) == nil)
    }
}

@MainActor
struct LearningResultTests {
    @Test func parsesTheMatchingItemAndItsMeaning() throws {
        let content =
            #"{"items":[{"text":"follow up","language":"en","kind":"phrase","meaning":"跟进。","context":"I will follow up."}]}"#
        let item = try LearningResult.item(content, expression: "follow up")
        #expect(item.meaning == "跟进。")
        #expect(item.kind == "phrase")
    }

    @Test func rejectsARejectedOrUnknownKind() {
        let content =
            #"{"items":[{"text":"follow up","language":"en","kind":"idiom","meaning":"跟进。","context":"I will follow up."}]}"#
        #expect(throws: ModelError.format) {
            try LearningResult.item(content, expression: "follow up")
        }
    }

    @Test func rejectsAnItemThatDoesNotMatchTheExpression() {
        let content =
            #"{"items":[{"text":"other","language":"en","kind":"word","meaning":"别的。","context":"I will follow up."}]}"#
        #expect(throws: ModelError.format) {
            try LearningResult.item(content, expression: "follow up")
        }
    }
}
