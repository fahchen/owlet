import Foundation
import SwiftData
import Synchronization
import Testing

@testable import Owlet

/// Collecting from 历史详情 (T17): the detail reuses the collect action, the 语境 is that record's
/// own snapshot, and the history lifecycle stays independent from the notebook.
@MainActor
struct HistoryCollectionTests {
    /// One in-memory container per test, shared by history and the notebook as in the app, so a
    /// history deletion gets a real chance to reach a collected entry.
    func makeStores() throws -> (HistoryStore, VocabularyStore) {
        let schema = Schema([HistoryRecord.self, VocabularyEntry.self, VocabularyContext.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return (HistoryStore(container: container), VocabularyStore(container: container))
    }

    func translated() throws -> (HistoryStore, VocabularyStore, HistoryRecord) {
        let (history, vocabulary) = try makeStores()
        let record = try history.record(
            operation: .translate, source: "I will follow up tomorrow.", result: "我明天会跟进。",
            language: "zh-Hans")
        return (history, vocabulary, record)
    }

    @Test func collectingFromADetailSavesTheRecordsOwnSourceAsTheContext() throws {
        let (_, vocabulary, record) = try translated()
        let entry = try vocabulary.collect(VocabularyDraft.from(record: record))
        #expect(entry.expression == "我明天会跟进。")
        #expect(entry.language == "zh-Hans")
        let context = try #require(entry.contexts.first)
        #expect(context.source == "I will follow up tomorrow.")
        // A translate record has no polish pair, so the entry shows one plain 原句.
        #expect(context.polishBefore == nil)
        #expect(context.polishAfter == nil)
    }

    @Test func aPolishRecordKeepsItsBeforeAndAfterComparison() throws {
        let (history, vocabulary, _) = try translated()
        let record = try history.record(
            operation: .polish, source: "This are bad.", result: "This is bad.", language: "en")
        let entry = try vocabulary.collect(VocabularyDraft.from(record: record))
        #expect(entry.expression == "This is bad.")
        #expect(entry.language == "en")
        let context = try #require(entry.contexts.first)
        #expect(context.source == "This are bad.")
        #expect(context.polishBefore == "This are bad.")
        #expect(context.polishAfter == "This is bad.")
    }

    @Test func theSameExpressionFromAnotherRecordAppendsItsContextOnce() throws {
        let (history, vocabulary, record) = try translated()
        let entry = try vocabulary.collect(VocabularyDraft.from(record: record))
        let second = try history.record(
            operation: .translate, source: "She followed up on the request.", result: "我明天会跟进。",
            language: "zh-Hans")
        let reused = try vocabulary.collect(VocabularyDraft.from(record: second))
        // The same language and expression reuse the entry and append the new 原句.
        #expect(reused === entry)
        #expect(try vocabulary.entries().count == 1)
        #expect(entry.contexts.count == 2)
        #expect(entry.contexts.last?.source == "She followed up on the request.")

        // Re-collecting the same record adds nothing, so one 收藏 press never forks a 语境.
        _ = try vocabulary.collect(VocabularyDraft.from(record: record))
        #expect(entry.contexts.count == 2)
    }

    @Test func aFailedMeaningRequestKeepsTheEntryAndItsContextAndCanBeRetried() async throws {
        let (_, vocabulary, record) = try translated()
        let calls = Mutex(0)
        let client = ModelClient(transport: { request in
            let call = calls.withLock { count -> Int in
                count += 1
                return count
            }
            if call == 1 { throw URLError(.notConnectedToInternet) }
            // A compliant model echoes the context it was sent, so the entry keeps the exact 原句 it
            // was collected with rather than the expression standing in for it.
            let request1 =
                try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
            let messages = request1?["messages"] as? [[String: Any]] ?? []
            let user = Data((messages.last?["content"] as? String ?? "{}").utf8)
            let sent = try JSONSerialization.jsonObject(with: user) as? [String: Any]
            let context = sent?["context"] as? String ?? ""
            let content = """
                {"items":[{"text":"我明天会跟进。","language":"zh-Hans","kind":"sentence",\
                "meaning":"用于承诺后续跟进。","context":"\(context)"}]}
                """
            return try await stub(body: learningBody(content))(request)
        })
        let action = CollectionAction(store: vocabulary, client: client, config: { testConfig })
        let entry = try #require(action.collect(VocabularyDraft.from(record: record)))
        await action.task?.value

        // The failure keeps what was already saved, its 原句 included.
        #expect(try vocabulary.entries().count == 1)
        #expect(entry.meaning.isEmpty)
        #expect(entry.contexts.first?.source == "I will follow up tomorrow.")
        guard case .meaningFailed(let failed, _) = action.status else {
            Issue.record("expected a failed meaning request, got \(action.status)")
            return
        }
        #expect(failed == entry)

        action.fillMeaning(for: entry)
        await action.task?.value
        #expect(entry.meaning == "用于承诺后续跟进。")
        #expect(entry.contexts.count == 1)
        #expect(action.status == .saved)
    }

    @Test func clearingHistoryKeepsTheCollectedEntryAndItsContext() throws {
        let (history, vocabulary, record) = try translated()
        _ = try vocabulary.collect(VocabularyDraft.from(record: record))
        history.requestClear()
        try history.confirmClear()
        #expect(try history.records().isEmpty)
        let entry = try #require(try vocabulary.entries().first)
        #expect(entry.expression == "我明天会跟进。")
        #expect(entry.contexts.first?.source == "I will follow up tomorrow.")
        // A fresh context proves the clear reached no cascade down to the 语境.
        let fresh = ModelContext(history.container)
        #expect(try fresh.fetchCount(FetchDescriptor<VocabularyContext>()) == 1)
    }

    @Test func deletingTheRecordKeepsTheCollectedEntryAndItsContext() throws {
        let (history, vocabulary, record) = try translated()
        _ = try vocabulary.collect(VocabularyDraft.from(record: record))
        try history.delete(record)
        #expect(try history.records().isEmpty)
        let entry = try #require(try vocabulary.entries().first)
        #expect(entry.expression == "我明天会跟进。")
        #expect(entry.contexts.first?.source == "I will follow up tomorrow.")
        let fresh = ModelContext(history.container)
        #expect(try fresh.fetchCount(FetchDescriptor<VocabularyContext>()) == 1)
    }
}
