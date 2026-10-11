import Foundation
import SwiftData
import Synchronization
import Testing

@testable import Owlet

/// One fresh in-memory notebook per test, per `tasks/plan.md`; several suites below need one.
@MainActor
func makeVocabularyStore() throws -> VocabularyStore {
    let schema = Schema([VocabularyEntry.self, VocabularyContext.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return VocabularyStore(container: try ModelContainer(for: schema, configurations: [config]))
}

@MainActor
struct VocabularyStoreTests {
    @Test func deletesSelectedEntriesAndTheirContextsOnly() throws {
        let store = try makeStore()
        let first = try store.collect(draft("one"))
        let second = try store.collect(draft("two"))
        _ = try store.collect(draft("three"))
        try store.delete([first, second])
        let fresh = ModelContext(store.container)
        #expect(try fresh.fetch(FetchDescriptor<VocabularyEntry>()).map(\.expression) == ["three"])
        #expect(try fresh.fetchCount(FetchDescriptor<VocabularyContext>()) == 1)
    }

    func makeStore() throws -> VocabularyStore { try makeVocabularyStore() }

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
        // The second sentence is appended to the same entry instead of forking a duplicate.
        #expect(second.contexts.count == 2)
    }

    @Test func appendingANewContextKeepsTheEarlierOneAndTheMeaning() throws {
        let store = try makeStore()
        let entry = try store.collect(draft("follow up"))
        try store.update(entry, expression: entry.expression, meaning: "跟进，后续联系。")
        let appended = try store.collect(
            draft("follow up", context: "She will follow up next week."))
        #expect(appended === entry)
        #expect(try store.entries().count == 1)
        #expect(appended.contexts.count == 2)
        // The earlier context is still there and the meaning written before the append survives.
        #expect(
            Set(appended.contexts.map(\.source)) == [
                "I will follow up tomorrow.", "She will follow up next week.",
            ])
        #expect(appended.meaning == "跟进，后续联系。")
    }

    @Test func theSameContextIsNotAppendedTwice() throws {
        let store = try makeStore()
        _ = try store.collect(draft("follow up"))
        // Only leading and trailing whitespace is ignored, so this is the same context.
        let again = try store.collect(draft("follow up", context: "  I will follow up tomorrow.  "))
        #expect(again.contexts.count == 1)
        #expect(try store.entries().count == 1)
    }

    @Test func aPolishPairIsADifferentContextFromThePlainSentence() throws {
        let store = try makeStore()
        _ = try store.collect(draft("This is bad.", context: "This is bad."))
        let polished = try store.collect(
            VocabularyDraft(
                expression: "This is bad.", language: "en", context: "This is bad.",
                polishBefore: "This are bad.", polishAfter: "This is bad."))
        // The second collect carries a comparison the first one lacks, so it is a new context.
        #expect(polished.contexts.count == 2)
        #expect(
            polished.contexts.contains {
                $0.polishBefore == "This are bad." && $0.polishAfter == "This is bad."
            })
    }

    @Test func separatesTheSameExpressionByLanguage() throws {
        let store = try makeStore()
        let chinese = try store.collect(draft("手紙", language: "zh", context: "中文句子"))
        let japanese = try store.collect(draft("手紙", language: "ja", context: "日本語の文"))
        #expect(try store.entries().count == 2)
        // A different language is always a different entry, so the two contexts never merge.
        #expect(chinese.contexts.map(\.source) == ["中文句子"])
        #expect(japanese.contexts.map(\.source) == ["日本語の文"])
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

    @Test func editingTheMeaningAndExpressionPersists() throws {
        let store = try makeStore()
        let entry = try store.collect(draft("follow up"))
        try store.update(entry, expression: " follow-up ", meaning: " 跟进，后续联系。 ")
        #expect(entry.expression == "follow-up")
        let fresh = ModelContext(store.container)
        let reloaded = try #require(try fresh.fetch(FetchDescriptor<VocabularyEntry>()).first)
        #expect(reloaded.expression == "follow-up")
        #expect(reloaded.meaning == "跟进，后续联系。")
        #expect(reloaded.contexts.count == 1)
    }

    @Test func editingRefusesABlankExpressionAndACollision() throws {
        let store = try makeStore()
        let first = try store.collect(draft("follow up"))
        let second = try store.collect(draft("check in"))
        #expect(throws: VocabularyError.self) {
            try store.update(second, expression: "   ", meaning: "")
        }
        #expect(throws: VocabularyError.self) {
            try store.update(second, expression: "follow up", meaning: "")
        }
        #expect(second.expression == "check in")
        #expect(first.expression == "follow up")
    }

    @Test func deletingAnEntryPersists() throws {
        let store = try makeStore()
        let entry = try store.collect(draft("follow up"))
        try store.delete(entry)
        #expect(try store.entries().isEmpty)
        let fresh = ModelContext(store.container)
        #expect(try fresh.fetch(FetchDescriptor<VocabularyEntry>()).isEmpty)
        #expect(try fresh.fetch(FetchDescriptor<VocabularyContext>()).isEmpty)
    }
}

@MainActor
struct VocabularyFilterTests {
    func makeStore() throws -> VocabularyStore {
        let schema = Schema([VocabularyEntry.self, VocabularyContext.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return VocabularyStore(container: try ModelContainer(for: schema, configurations: [config]))
    }

    /// English and Japanese entries whose meanings are set through the edit path.
    func notebook() throws -> VocabularyStore {
        let store = try makeStore()
        let step = try store.collect(
            VocabularyDraft(
                expression: "take a step back", language: "en", context: "Let's take a step back.",
                polishBefore: nil, polishAfter: nil))
        try store.update(step, expression: step.expression, meaning: "退一步，从新的角度重新审视。")
        let letter = try store.collect(
            VocabularyDraft(
                expression: "手紙", language: "ja", context: "手紙を書きます。",
                polishBefore: nil, polishAfter: nil))
        try store.update(letter, expression: letter.expression, meaning: "信。")
        return store
    }

    @Test func searchMatchesTheExpressionAndTheMeaning() throws {
        let store = try notebook()
        let entries = try store.entries()
        // The container owns the model objects, so it has to outlive every assertion that reads them.
        withExtendedLifetime(store) {
            #expect(VocabularyFilter.apply(entries, search: "step", language: nil).count == 1)
            #expect(VocabularyFilter.apply(entries, search: "STEP", language: nil).count == 1)
            #expect(VocabularyFilter.apply(entries, search: "新的角度", language: nil).count == 1)
        }
    }

    @Test func languageFilterKeepsOneLanguage() throws {
        let store = try notebook()
        let entries = try store.entries()
        withExtendedLifetime(store) {
            let japanese = VocabularyFilter.apply(entries, search: "", language: "ja")
            #expect(japanese.count == 1)
            #expect(japanese.first?.expression == "手紙")
        }
    }

    @Test func searchAndLanguageFilterCombine() throws {
        let store = try notebook()
        let entries = try store.entries()
        withExtendedLifetime(store) {
            #expect(VocabularyFilter.apply(entries, search: "手紙", language: "en").isEmpty)
            #expect(VocabularyFilter.apply(entries, search: "手紙", language: "ja").count == 1)
        }
    }

    @Test func noMatchIsEmptyAndClearingTheFilterRestoresEveryEntry() throws {
        let store = try notebook()
        let entries = try store.entries()
        withExtendedLifetime(store) {
            #expect(VocabularyFilter.apply(entries, search: "no-match-example", language: nil).isEmpty)
            #expect(VocabularyFilter.apply(entries, search: "", language: nil).count == entries.count)
        }
    }

    @Test func languagesListsEachTagOnce() throws {
        let store = try notebook()
        _ = try store.collect(
            VocabularyDraft(
                expression: "follow up", language: "en", context: "I will follow up.",
                polishBefore: nil, polishAfter: nil))
        #expect(VocabularyFilter.languages(in: try store.entries()) == ["en", "ja"])
    }
}

@MainActor
struct CollectionActionTests {
    let meaningResponse = learningJSON(
        #"{"items":[{"text":"follow up","language":"en","kind":"phrase","meaning":"跟进，后续联系。","context":"I will follow up tomorrow."}]}"#
    )

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

    @Test func learningMembershipTogglesImmediatelyWithoutModelRequests() throws {
        let store = try makeStore()
        let client = ModelClient(transport: { _ in
            Issue.record("Toggling a recommendation must not call the model")
            throw URLError(.unsupportedURL)
        })
        let action = CollectionAction(store: store, client: client, config: { nil })
        let other = try store.collect(VocabularyDraft(expression: "別の語", language: "ja", context: "別の語"))
        #expect(action.setCollected(true, draft: draft(), meaning: "跟进"))
        #expect(try store.entry(language: "en", expression: "follow up")?.meaning == "跟进")
        // Reopening the panel uses the same stored membership; selecting again never duplicates it.
        #expect(action.setCollected(true, draft: draft(), meaning: "跟进"))
        #expect(try store.entries().count == 2)
        #expect(action.setCollected(false, draft: draft(), meaning: "跟进"))
        #expect(try store.entry(language: "en", expression: "follow up") == nil)
        #expect(try store.entries().map(\.expression) == [other.expression])
        #expect(action.setCollected(true, draft: draft(), meaning: "跟进"))
        #expect(try store.entries().count == 2)
        #expect(action.task == nil)
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
            return try await stub(body: learningBody(self.meaningResponse))(request)
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

    @Test func collectingAnExistingExpressionAppendsWithoutASecondMeaningRequest() async throws {
        let store = try makeStore()
        let calls = Mutex(0)
        let client = ModelClient(transport: { request in
            calls.withLock { $0 += 1 }
            return try await stub(body: learningBody(self.meaningResponse))(request)
        })
        let action = CollectionAction(store: store, client: client, config: { testConfig })
        let first = try #require(action.collect(draft()))
        await action.task?.value
        #expect(first.meaning == "跟进，后续联系。")

        let second = try #require(
            action.collect(
                VocabularyDraft(
                    expression: "follow up", language: "en",
                    context: "She will follow up next week.", polishBefore: nil, polishAfter: nil)))
        #expect(second === first)
        #expect(try store.entries().count == 1)
        #expect(second.contexts.count == 2)
        // The stored meaning is not overwritten, and the append spends no second model request.
        #expect(second.meaning == "跟进，后续联系。")
        #expect(calls.withLock { $0 } == 1)
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
    func polishModel() async throws -> TextProcessingModel {
        let content =
            #"{"source_language":"en","target_language":"en","segments":[{"source":"This are bad.","target":"This is bad."}]}"#
        let model = TextProcessingModel(
            client: ModelClient(transport: stub(body: chatBody(content))), config: { testConfig })
        model.operation = .polish
        model.input = "This are bad."
        await model.process(to: "zh-Hans")?.value
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
        let model = TextProcessingModel(client: ModelClient(), config: { testConfig })
        model.input = "Hello"
        #expect(VocabularyDraft.from(region: .source, model: model, selection: nil) == nil)
    }

    /// Collecting from the result of a translation: the expression is English but the 原句 kept with
    /// it is the Chinese source, so each needs its own language (BDR-0008's 语境归因).
    @Test func aTranslatedResultKeepsTheSourceSentenceLanguage() async throws {
        let content =
            #"{"source_language":"zh-Hans","target_language":"en","segments":[{"source":"我明天会跟进。","target":"I will follow up tomorrow."}]}"#
        let model = TextProcessingModel(
            client: ModelClient(transport: stub(body: chatBody(content))), config: { testConfig })
        model.input = "我明天会跟进。"
        await model.process(to: "en")?.value

        let draft = try #require(
            VocabularyDraft.from(region: .result, model: model, selection: "follow up"))
        #expect(draft.expression == "follow up")
        #expect(draft.language == "en")
        #expect(draft.context == "I will follow up tomorrow.")
        // The entry's own language says nothing about the sentence beside it.
        #expect(draft.contextLanguage == "zh-Hans")

        let store = try makeVocabularyStore()
        let entry = try store.collect(draft)
        #expect(entry.contexts.first?.language == "zh-Hans")
        #expect(entry.language == "en")
    }
}

@MainActor
struct LearningResultTests {
    @Test func parsesTheMatchingItemAndItsMeaning() throws {
        let content = learningJSON(
            #"{"items":[{"text":"follow up","language":"en","kind":"phrase","meaning":"跟进。","context":"I will follow up."}]}"#
        )
        let item = try LearningResult.item(content, expression: "follow up")
        #expect(item.meaning == "跟进。")
        #expect(item.kind == "phrase")
    }

    @Test func rejectsARejectedOrUnknownKind() {
        let content = learningJSON(
            #"{"items":[{"text":"follow up","language":"en","kind":"idiom","meaning":"跟进。","context":"I will follow up."}]}"#
        )
        #expect(throws: ModelError.format) {
            try LearningResult.item(content, expression: "follow up")
        }
    }

    @Test func rejectsAnItemThatDoesNotMatchTheExpression() {
        let content = learningJSON(
            #"{"items":[{"text":"other","language":"en","kind":"word","meaning":"别的。","context":"I will follow up."}]}"#
        )
        #expect(throws: ModelError.format) {
            try LearningResult.item(content, expression: "follow up")
        }
    }
}
