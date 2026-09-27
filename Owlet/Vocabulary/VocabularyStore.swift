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

    /// Saves the edited expression and meaning, rejecting a rename that would collide with another
    /// entry of the same language, since language plus trimmed expression stays the identity.
    func update(_ entry: VocabularyEntry, expression: String, meaning: String) throws {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw VocabularyError.emptyExpression }
        if let clash = try self.entry(language: entry.language, expression: trimmed), clash !== entry {
            throw VocabularyError.duplicateExpression
        }
        entry.expression = trimmed
        entry.meaning = meaning.trimmingCharacters(in: .whitespacesAndNewlines)
        try context.save()
    }

    /// Removes an entry; the cascade takes its contexts with it, so no orphan sentence survives.
    func delete(_ entry: VocabularyEntry) throws {
        context.delete(entry)
        try context.save()
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
    case duplicateExpression

    var errorDescription: String? {
        switch self {
        case .emptyExpression: "没有可收藏的内容"
        case .duplicateExpression: "同语言下已存在相同的表达"
        }
    }
}

/// The notebook's search and language filter; one rule shared by the list view and the tests.
enum VocabularyFilter {
    /// Keeps entries matching the search text against expression or meaning and, when set, one language.
    static func apply(_ entries: [VocabularyEntry], search: String, language: String?) -> [VocabularyEntry] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return entries.filter { entry in
            (language == nil || entry.language == language)
                && (query.isEmpty
                    || entry.expression.localizedStandardContains(query)
                    || entry.meaning.localizedStandardContains(query))
        }
    }

    /// The distinct languages the notebook holds, so the filter menu never offers an empty choice.
    static func languages(in entries: [VocabularyEntry]) -> [String] {
        var seen = Set<String>()
        return entries.compactMap { seen.insert($0.language).inserted ? $0.language : nil }.sorted()
    }
}
