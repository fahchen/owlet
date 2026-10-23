import Foundation
import SwiftData

/// The history side of the app's one Application Support store; it shares the container with the
/// notebook but relates to nothing in it, so clearing history can never delete a collection.
@MainActor @Observable
final class HistoryStore {
    /// The store the app reads and writes; the floating panel and the window share this instance.
    static let shared = HistoryStore(container: VocabularyStore.shared.container)
    let container: ModelContainer
    /// The last storage failure, so the history page can say what went wrong; the result stays on screen.
    private(set) var lastError: String?
    /// Whether the page is showing the clear confirmation; nothing is removed until the user confirms,
    /// so routing the destructive action through the store makes cancelling provably a no-op.
    private(set) var isConfirmingClear = false

    private var context: ModelContext { container.mainContext }

    init(container: ModelContainer) {
        self.container = container
    }

    /// Appends one finished result; nothing expires, so this is the only write path.
    @discardableResult
    func record(
        operation: Operation, source: String, result: String, language: String,
        sourceImage: Data? = nil, at createdAt: Date = Date()
    ) throws -> HistoryRecord {
        let record = HistoryRecord(
            operation: operation, source: source, result: result, language: language,
            createdAt: createdAt, sourceImage: sourceImage)
        context.insert(record)
        try context.save()
        lastError = nil
        return record
    }

    /// Newest first, which is the order the history page lists them in.
    func records() throws -> [HistoryRecord] {
        try context.fetch(
            FetchDescriptor<HistoryRecord>(
                sortBy: [SortDescriptor(\HistoryRecord.createdAt, order: .reverse)]))
    }

    /// Reads one record by identity, which is what a detail route needs after a reload.
    func record(id: PersistentIdentifier) -> HistoryRecord? {
        context.model(for: id) as? HistoryRecord
    }

    /// Removes one record; the notebook is a separate model and stays untouched.
    func delete(_ record: HistoryRecord) throws {
        try delete([record])
    }

    func delete(_ items: [HistoryRecord]) throws {
        for item in items { context.delete(item) }
        try context.save()
    }

    /// Clears every record; models other than `HistoryRecord` in the shared container are unaffected.
    func deleteAll() throws {
        try context.delete(model: HistoryRecord.self)
        try context.save()
    }

    /// Opens the clear confirmation without removing anything.
    func requestClear() {
        isConfirmingClear = true
    }

    /// Closes the clear confirmation and keeps every record.
    func cancelClear() {
        isConfirmingClear = false
    }

    /// Runs the clear only after the user confirms, then closes the confirmation.
    func confirmClear() throws {
        try deleteAll()
        isConfirmingClear = false
    }

    /// Records a failure from a source that cannot present it, so the page can.
    func report(_ error: Error) {
        lastError = error.localizedDescription
    }

    /// Clears the failure banner once the user has read it.
    func dismissError() {
        lastError = nil
    }
}

/// The history page's search and type filter; one rule shared by the list view and the tests.
enum HistoryFilter {
    /// Keeps records whose source or result contains the search text and, when set, whose type matches.
    static func apply(
        _ records: [HistoryRecord], search: String, operation: Operation?
    ) -> [HistoryRecord] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return records.filter { record in
            (operation == nil || record.operationKind == operation)
                && (query.isEmpty
                    || record.source.localizedStandardContains(query)
                    || record.result.localizedStandardContains(query))
        }
    }
}
