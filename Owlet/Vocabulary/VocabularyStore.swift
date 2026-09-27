import Foundation
import SwiftData

/// The one local store for collected expressions; tests build an in-memory container per test.
@MainActor
final class VocabularyStore {
    /// The app's single Application Support store, shared by the window and the floating panel.
    static let shared = VocabularyStore(container: makeContainer())
    let container: ModelContainer

    private var context: ModelContext { container.mainContext }

    init(container: ModelContainer) {
        self.container = container
    }

    /// Saves a draft at once, reusing the entry for the same language and trimmed expression;
    /// appending a second context to that entry belongs to T11.
    @discardableResult
    func collect(_ draft: VocabularyDraft) throws -> VocabularyEntry {
        let expression = draft.expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !expression.isEmpty else { throw VocabularyError.emptyExpression }
        if let existing = try entry(language: draft.language, expression: expression) {
            return existing
        }
        let entry = VocabularyEntry(expression: expression, language: draft.language)
        entry.contexts = [
            VocabularyContext(
                source: draft.context, polishBefore: draft.polishBefore,
                polishAfter: draft.polishAfter)
        ]
        context.insert(entry)
        try context.save()
        return entry
    }

    /// Newest first, which is the order the notebook lists them in.
    func entries() throws -> [VocabularyEntry] {
        try context.fetch(
            FetchDescriptor<VocabularyEntry>(
                sortBy: [SortDescriptor(\VocabularyEntry.createdAt, order: .reverse)]))
    }

    /// Finds the entry for a language and an already-trimmed expression.
    func entry(language: String, expression: String) throws -> VocabularyEntry? {
        var descriptor = FetchDescriptor<VocabularyEntry>(
            predicate: #Predicate { $0.language == language && $0.expression == expression })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func save() throws {
        try context.save()
    }

    private static func makeContainer() -> ModelContainer {
        do {
            // History shares this container; the two model sets are unrelated, so neither can cascade
            // into the other.
            return try ModelContainer(
                for: VocabularyEntry.self, VocabularyContext.self, HistoryRecord.self)
        } catch {
            // Without its store the app cannot keep a collection, so failing loudly beats losing it.
            fatalError("Could not open the vocabulary store: \(error)")
        }
    }
}

enum VocabularyError: LocalizedError {
    case emptyExpression

    var errorDescription: String? {
        switch self {
        case .emptyExpression: "没有可收藏的内容"
        }
    }
}
