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

    /// Saves a draft at once, reusing the entry for the same language and trimmed expression and
    /// appending the new context there, so collecting the same expression twice never forks an entry.
    @discardableResult
    func collect(_ draft: VocabularyDraft) throws -> VocabularyEntry {
        let expression = draft.expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !expression.isEmpty else { throw VocabularyError.emptyExpression }
        let newContext = VocabularyContext(
            source: draft.context, language: trimmed(draft.contextLanguage) ?? "",
            polishBefore: draft.polishBefore, polishAfter: draft.polishAfter)
        let entry = try collectedEntry(draft, expression: expression, context: newContext)
        try save()
        return entry
    }

    /// Saves a lookup's own snapshot: the queried form, the sentence it was read in (absent when the
    /// lookup had no source sentence), and the answer the model already gave, so adding a word from
    /// the lookup card never spends a second request.
    @discardableResult
    func collect(_ draft: VocabularyDraft, in query: LookupQuery, result: LookupResult) throws
        -> VocabularyEntry
    {
        let expression = draft.expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !expression.isEmpty else { throw VocabularyError.emptyExpression }
        let newContext = VocabularyContext(
            source: query.context ?? "", language: trimmed(draft.contextLanguage) ?? "",
            polishBefore: draft.polishBefore, polishAfter: draft.polishAfter)
        let entry = try collectedEntry(draft, expression: expression, context: newContext)
        let meaning = result.meaning.trimmingCharacters(in: .whitespacesAndNewlines)
        let locale = trimmed(draft.definitionLocale) ?? ""
        // The answer travels with the entry. The stored meaning is the user's once it exists, so a
        // later collection never rewrites it, but a first one fills in what was missing.
        if entry.meaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !meaning.isEmpty {
            entry.meaning = meaning
            entry.definitionLocale = locale
        } else if entry.definitionLocale.isEmpty, !locale.isEmpty {
            entry.definitionLocale = locale
        }
        try save()
        return entry
    }

    /// The entry for this language and expression, appending the new context there and filling in
    /// what is still unknown, so collecting the same expression twice never forks an entry.
    private func collectedEntry(
        _ draft: VocabularyDraft, expression: String, context newContext: VocabularyContext
    ) throws -> VocabularyEntry {
        if let existing = try entry(language: draft.language, expression: expression) {
            // The same context submitted again adds nothing, and an earlier context is never replaced.
            var changed = false
            // A lookup with no source sentence has none to keep, so it adds no context at all.
            if !draft.context.isEmpty,
                !existing.contexts.contains(where: { $0.hasSameContent(as: newContext) })
            {
                existing.contexts.append(newContext)
                changed = true
            }
            // The dictionary form and the meaning's language are only ever filled in, never corrected
            // by a later collection of the same expression (BDR-0005, BDR-0009).
            if existing.lemma.isEmpty, let lemma = trimmed(draft.lemma) {
                existing.lemma = lemma
                changed = true
            }
            if existing.definitionLocale.isEmpty, let locale = trimmed(draft.definitionLocale) {
                existing.definitionLocale = locale
                changed = true
            }
            if changed { try save() }
            return existing
        }
        let entry = VocabularyEntry(
            expression: expression, language: draft.language, lemma: trimmed(draft.lemma) ?? "",
            definitionLocale: trimmed(draft.definitionLocale) ?? "")
        if !draft.context.isEmpty { entry.contexts = [newContext] }
        context.insert(entry)
        return entry
    }

    /// An empty or whitespace-only optional value means the source did not know it.
    private func trimmed(_ value: String?) -> String? {
        value.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap {
            $0.isEmpty ? nil : $0
        }
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
        try delete([entry])
    }

    func delete(_ items: [VocabularyEntry]) throws {
        do {
            for item in items { context.delete(item) }
            try context.save()
        } catch {
            // Keep membership unchanged when a deletion cannot be persisted.
            context.rollback()
            throw error
        }
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
