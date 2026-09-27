import ApplicationServices
import Foundation
import SwiftData
import Testing

@testable import Owlet

/// A panel that never goes on screen, so a write-back can fail without a window fighting for key.
@MainActor
private final class SilentPanel: FloatingPanel {
    override func show(anchor: PanelPlacement.Anchor) {}
}

/// Releases a stubbed response only when the test asks, so cancellation can be driven deterministically.
@MainActor
private final class Gate {
    private var continuations: [CheckedContinuation<Void, Never>] = []
    var isWaiting: Bool { !continuations.isEmpty }
    func wait() async { await withCheckedContinuation { continuations.append($0) } }
    func release() { continuations.removeFirst().resume() }
}

@MainActor
struct HistoryStoreTests {
    /// One fresh in-memory container per test, shared by history and the notebook as in the app.
    func makeStores() throws -> (HistoryStore, VocabularyStore) {
        let schema = Schema([HistoryRecord.self, VocabularyEntry.self, VocabularyContext.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return (HistoryStore(container: container), VocabularyStore(container: container))
    }

    func draft(_ expression: String = "follow up") -> VocabularyDraft {
        VocabularyDraft(
            expression: expression, language: "en", context: "I will follow up tomorrow.",
            polishBefore: nil, polishAfter: nil)
    }

    // MARK: - Recording

    @Test func aSuccessfulTranslationIsRecorded() async throws {
        let (store, _) = try makeStores()
        let model = TranslationModel(
            client: ModelClient(transport: stub(body: chatBody(TestReplies.reply(for: "Hello")))),
            config: { testConfig })
        let recorder = HistoryRecorder(store: store)
        recorder.observe(model)
        model.input = "Hello"
        await model.translate(to: "zh-Hans")?.value
        await recorder.flush()

        let record = try #require(try store.records().first)
        #expect(try store.records().count == 1)
        #expect(record.operationKind == .translate)
        #expect(record.source == "Hello")
        #expect(record.result == "T:Hello")
        #expect(record.language == "zh-Hans")
    }

    @Test func aSuccessfulPolishIsRecordedWithTheSourceLanguage() async throws {
        let (store, _) = try makeStores()
        let content =
            #"{"source_language":"en","target_language":"en","segments":[{"source":"This are bad.","target":"This is bad."}]}"#
        let model = TranslationModel(
            client: ModelClient(transport: stub(body: chatBody(content))), config: { testConfig })
        let recorder = HistoryRecorder(store: store)
        recorder.observe(model)
        model.operation = .polish
        model.input = "This are bad."
        await model.translate(to: "zh-Hans")?.value
        await recorder.flush()

        let record = try #require(try store.records().first)
        #expect(record.operationKind == .polish)
        #expect(record.source == "This are bad.")
        #expect(record.result == "This is bad.")
        #expect(record.language == "en")
    }

    @Test func aFailedRequestIsNotRecorded() async throws {
        let (store, _) = try makeStores()
        let model = TranslationModel(
            client: ModelClient(transport: { _ in throw URLError(.notConnectedToInternet) }),
            config: { testConfig })
        let recorder = HistoryRecorder(store: store)
        recorder.observe(model)
        model.input = "Hello"
        await model.translate(to: "zh-Hans")?.value
        await recorder.flush()
        #expect(try store.records().isEmpty)
    }

    @Test func aCancelledRequestIsNotRecorded() async throws {
        let (store, _) = try makeStores()
        let gate = Gate()
        let client = ModelClient(transport: { request in
            await gate.wait()
            return try await stub(body: chatBody(TestReplies.reply(for: "Hello")))(request)
        })
        let model = TranslationModel(client: client, config: { testConfig })
        let recorder = HistoryRecorder(store: store)
        recorder.observe(model)
        model.input = "Hello"
        let task = model.translate(to: "zh-Hans")
        for _ in 0..<100 where !gate.isWaiting { await Task.yield() }
        model.cancel()
        gate.release()
        await task?.value
        await recorder.flush()
        #expect(try store.records().isEmpty)
    }

    @Test func aWriteBackFailureStillRecordsTheTranslation() async throws {
        let (store, _) = try makeStores()
        let model = TranslationModel(
            client: ModelClient(transport: stub(body: chatBody(TestReplies.reply(for: "Hello")))),
            config: { testConfig })
        let recorder = HistoryRecorder(store: store)
        recorder.observe(model)
        let panel = PanelController(
            model: model,
            defaults: UserDefaults(suiteName: "HistoryStoreTests.\(UUID().uuidString)")!)
        panel.makeWindow = { SilentPanel(rootView: $0) }
        panel.read = { completion in
            completion(
                .success(
                    Selection(
                        text: "Hello", element: AXUIElementCreateApplication(1), app: nil,
                        range: SelectedRange(location: 0, length: 5))))
        }
        panel.write = { _, _ in .refused }
        panel.trigger(replace: true)
        for _ in 0..<100 where panel.writebackRefusal == nil {
            try? await Task.sleep(for: .milliseconds(20))
        }

        #expect(panel.writebackRefusal == .unwritten)
        await recorder.flush()
        let record = try #require(try store.records().first)
        #expect(try store.records().count == 1)
        #expect(record.source == "Hello")
        #expect(record.result == "T:Hello")
    }

    @Test func aRepublishedCachedResultIsNotRecordedTwice() async throws {
        let (store, _) = try makeStores()
        let model = TranslationModel(
            client: ModelClient(transport: stub(body: chatBody(TestReplies.reply(for: "Hello")))),
            config: { testConfig })
        let recorder = HistoryRecorder(store: store)
        recorder.observe(model)
        model.input = "Hello"
        await model.translate(to: "zh-Hans")?.value
        await recorder.flush()
        await model.translate(to: "zh-Hans")?.value
        await recorder.flush()
        #expect(try store.records().count == 1)
    }

    // MARK: - Reading, deleting and isolation

    @Test func recordsStayReadableFromAFreshContext() throws {
        let (store, _) = try makeStores()
        try store.record(operation: .translate, source: "Hello", result: "你好", language: "zh-Hans")
        let fresh = ModelContext(store.container)
        #expect(try fresh.fetch(FetchDescriptor<HistoryRecord>()).count == 1)
    }

    @Test func fetchesOneRecordByIdentity() throws {
        let (store, _) = try makeStores()
        let record = try store.record(
            operation: .translate, source: "Hello", result: "你好", language: "zh-Hans")
        #expect(store.record(id: record.persistentModelID)?.persistentModelID == record.persistentModelID)
    }

    @Test func deletesOneRecordAndKeepsTheOther() throws {
        let (store, _) = try makeStores()
        let first = try store.record(
            operation: .translate, source: "Hello", result: "你好", language: "zh-Hans",
            at: Date(timeIntervalSince1970: 1))
        let second = try store.record(
            operation: .polish, source: "This are bad.", result: "This is bad.", language: "en",
            at: Date(timeIntervalSince1970: 2))
        try store.delete(first)
        let remaining = try store.records()
        #expect(remaining.count == 1)
        #expect(remaining.first?.persistentModelID == second.persistentModelID)
        #expect(remaining.first?.operationKind == .polish)
    }

    @Test func clearingHistoryLeavesTheNotebookUntouched() throws {
        let (store, vocabulary) = try makeStores()
        _ = try vocabulary.collect(draft())
        try store.record(
            operation: .translate, source: "Hello", result: "你好", language: "zh-Hans")
        try store.deleteAll()
        #expect(try store.records().isEmpty)
        #expect(try vocabulary.entries().count == 1)
        #expect(try vocabulary.entries().first?.expression == "follow up")
    }

    @Test func deletingOneRecordLeavesTheNotebookUntouched() throws {
        let (store, vocabulary) = try makeStores()
        _ = try vocabulary.collect(draft())
        let record = try store.record(
            operation: .translate, source: "Hello", result: "你好", language: "zh-Hans")
        try store.delete(record)
        #expect(try store.records().isEmpty)
        #expect(try vocabulary.entries().count == 1)
    }

    @Test func recordsListNewestFirst() throws {
        let (store, _) = try makeStores()
        try store.record(
            operation: .translate, source: "old", result: "旧", language: "zh-Hans",
            at: Date(timeIntervalSince1970: 1))
        try store.record(
            operation: .translate, source: "new", result: "新", language: "zh-Hans",
            at: Date(timeIntervalSince1970: 2))
        #expect(try store.records().map(\.source) == ["new", "old"])
    }

    @Test func aStorageFailureIsReportedAndClearedByTheNextSave() throws {
        let (store, _) = try makeStores()
        store.report(URLError(.cannotWriteToFile))
        #expect(store.lastError != nil)
        store.dismissError()
        #expect(store.lastError == nil)

        store.report(URLError(.cannotWriteToFile))
        try store.record(
            operation: .translate, source: "Hello", result: "你好", language: "zh-Hans")
        #expect(store.lastError == nil)
    }
}
