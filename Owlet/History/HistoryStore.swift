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

    private var context: ModelContext { container.mainContext }

    init(container: ModelContainer) {
        self.container = container
    }

    /// Appends one finished result; nothing expires, so this is the only write path.
    @discardableResult
    func record(
        operation: Operation, source: String, result: String, language: String,
        at createdAt: Date = Date()
    ) throws -> HistoryRecord {
        let record = HistoryRecord(
            operation: operation, source: source, result: result, language: language,
            createdAt: createdAt)
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
        context.delete(record)
        try context.save()
    }

    /// Clears every record; models other than `HistoryRecord` in the shared container are unaffected.
    func deleteAll() throws {
        try context.delete(model: HistoryRecord.self)
        try context.save()
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
