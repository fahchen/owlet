import Foundation

/// Which region of the current result the user is collecting from.
enum CollectedRegion {
    case source
    case result
}

/// Runs the collect action: it saves the draft first, then asks the model for the Chinese meaning
/// an explicit action requested, so a failed request never costs the saved content.
@MainActor @Observable
final class CollectionAction {
    enum Status: Equatable {
        case idle
        case saved
        case filling(VocabularyEntry)
        case meaningFailed(VocabularyEntry, String)
        case saveFailed(String)
    }

    let store: VocabularyStore
    private let client: ModelClient
    private let config: () -> ServiceConfig?
    private(set) var status: Status = .idle
    /// Bumped whenever the notebook gains or loses an entry. The store is SwiftData, and a surface
    /// outside its container — the lookup card's bookmark — does not observe it, so a view that
    /// mirrors membership reads this to be redrawn the moment a click lands.
    private(set) var revision = 0
    /// The meaning request in flight; tests await it, the views only observe `status`.
    private(set) var task: Task<Void, Never>?

    init(
        store: VocabularyStore = .shared, client: ModelClient = ModelClient(),
        config: @escaping () -> ServiceConfig? = SettingsStore.currentConfig
    ) {
        self.store = store
        self.client = client
        self.config = config
    }

    /// Records that membership may have changed.
    private func notebookChanged() {
        revision &+= 1
    }

    /// Saves the draft at once; a missing meaning is then filled by the model.
    @discardableResult
    func collect(_ draft: VocabularyDraft) -> VocabularyEntry? {
        do {
            let entry = try store.collect(draft)
            notebookChanged()
            if entry.meaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                fillMeaning(for: entry)
            } else {
                status = .saved
            }
            return entry
        } catch {
            status = .saveFailed(error.localizedDescription)
            return nil
        }
    }

    /// Saves a checked learning recommendation together with the Chinese meaning the learning
    /// response already returned, so collecting it is immediate and costs no second request.
    @discardableResult
    func collect(_ draft: VocabularyDraft, meaning: String) -> VocabularyEntry? {
        do {
            let entry = try store.collect(draft)
            notebookChanged()
            var changed = false
            // The dictionary form a recommendation knew is worth keeping even when the meaning it
            // came with is not written, so the notebook still shows the lemma (BDR-0009).
            if let lemma = draft.lemma, entry.lemma.isEmpty {
                entry.lemma = lemma
                changed = true
            }
            let trimmed = meaning.trimmingCharacters(in: .whitespacesAndNewlines)
            if entry.meaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !trimmed.isEmpty {
                entry.meaning = trimmed
                changed = true
            }
            if changed { try store.save() }
            status = .saved
            return entry
        } catch {
            status = .saveFailed(error.localizedDescription)
            return nil
        }
    }

    /// Learning rows mirror stored membership, including entries collected outside this panel.
    @discardableResult
    func setCollected(_ selected: Bool, draft: VocabularyDraft, meaning: String) -> Bool {
        if selected { return collect(draft, meaning: meaning) != nil }
        do {
            if let entry = try store.entry(
                language: draft.language,
                expression: draft.expression.trimmingCharacters(in: .whitespacesAndNewlines))
            {
                try store.delete(entry)
                notebookChanged()
            }
            status = .idle
            return true
        } catch {
            status = .saveFailed(error.localizedDescription)
            return false
        }
    }

    /// Whether the notebook already holds this language and expression; the lookup card mirrors the
    /// stored membership, including entries collected anywhere else. An unknown language is never a
    /// stored entry, so nothing is ever keyed under an empty tag.
    func isCollected(language: String, expression: String) -> Bool {
        guard !language.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return
            (try? store.entry(
                language: language,
                expression: expression.trimmingCharacters(in: .whitespacesAndNewlines))) != nil
    }

    /// The lookup card's own toggle: adding saves what the lookup already answered, and removing
    /// deletes the entry exactly as the learning rows do. A failed save or delete leaves the stored
    /// membership alone, so the card's state still reflects the notebook.
    @discardableResult
    func setCollected(_ selected: Bool, query: LookupQuery, result: LookupResult) -> Bool {
        let draft = VocabularyDraft.from(query, result: result)
        guard !draft.language.isEmpty else {
            status = .saveFailed("未能确定这段文字的语言")
            return false
        }
        if selected {
            do {
                _ = try store.collect(draft, in: query, result: result)
                notebookChanged()
                status = .saved
                return true
            } catch {
                status = .saveFailed(error.localizedDescription)
                return false
            }
        }
        if let entry = try? store.entry(language: draft.language, expression: draft.expression) {
            do {
                try store.delete(entry)
            } catch {
                status = .saveFailed(error.localizedDescription)
                return false
            }
            notebookChanged()
        }
        status = .idle
        return true
    }

    /// Runs or retries the meaning request for an entry that has none yet.
    func fillMeaning(for entry: VocabularyEntry) {
        guard let config = config() else {
            status = .meaningFailed(entry, "模型服务未配置")
            return
        }
        task?.cancel()
        status = .filling(entry)
        let client = client
        let expression = entry.expression
        let language = entry.language
        // The context only shapes the explanation; a 原句 collected from 历史详情 is in the record's
        // other language, so the expression stands in for it there.
        let stored = entry.contexts.first?.source ?? ""
        let context = stored.localizedStandardContains(expression) ? stored : expression
        let definitionLocale = entry.lookupOrigin.definitionLanguage
        task = Task { [store] in
            do {
                let meaning = try await client.fillMeaning(
                    expression: expression, language: language, context: context,
                    definitionLocale: definitionLocale, config: config)
                try Task.checkCancellation()
                entry.meaning = meaning
                // Recorded with the meaning it produced, so a later regenerate keeps asking in the
                // same language even after the target mapping changes (BDR-0005).
                entry.definitionLocale = definitionLocale
                try store.save()
                notebookChanged()
                status = .saved
            } catch is CancellationError {
                // A newer collect owns the status; leaving it alone avoids overwriting the new one.
            } catch {
                let message = (error as? ModelError)?.message ?? error.localizedDescription
                status = .meaningFailed(entry, message)
            }
        }
    }
}

extension VocabularyDraft {
    /// Builds the snapshot for a collect action: the user's selection wins over the whole region,
    /// and a polish pair is kept whenever the current operation produced one.
    @MainActor static func from(
        region: CollectedRegion, model: TextProcessingModel, selection: String?
    ) -> VocabularyDraft? {
        guard case .success(let result) = model.state, let languages = model.languages else {
            return nil
        }
        let source = model.input
        let regionText = region == .source ? source : result
        let trimmed = selection?.trimmingCharacters(in: .whitespacesAndNewlines)
        let expression = (trimmed?.isEmpty == false ? trimmed : nil) ?? regionText
        let language = region == .source ? languages.source : languages.target
        // The meaning uses the language this region's text is explained in (BDR-0005).
        let origin =
            region == .source
            ? LookupOrigin(
                language: language,
                definitionLanguage: SettingsStore.targetMapping().target(
                    forSource: LanguageTag.key(language)))
            : LookupOrigin.result(
                of: model.operation, languages: languages, mapping: SettingsStore.targetMapping())
        let polish = model.operation == .polish
        return VocabularyDraft(
            expression: expression,
            language: language,
            context: regionText,
            // The whole region is the expression's context, and for a translation's result that
            // sentence is the source text, in the source language.
            contextLanguage: model.languages?.source,
            polishBefore: polish ? source : nil,
            polishAfter: polish ? result : nil,
            definitionLocale: origin.definitionLanguage)
    }

    /// Builds the snapshot for adding a lookup's answer to the notebook: the queried form, the
    /// sentence it was read in, and the language and dictionary form the lookup established.
    static func from(_ query: LookupQuery, result: LookupResult?) -> VocabularyDraft {
        VocabularyDraft(
            expression: query.text,
            language: query.lookupLanguage(from: result) ?? "",
            context: query.context ?? "",
            contextLanguage: query.context == nil ? nil : query.lookupLanguage(from: result),
            lemma: result?.lemma,
            definitionLocale: query.definitionLanguage)
    }

    /// Builds the snapshot for collecting from 历史详情: the result is the expression and the record's
    /// own source text is the context, so the entry keeps its 原句 after the history is deleted, and a
    /// polish record keeps the before/after comparison it was collected from.
    @MainActor static func from(
        record: HistoryRecord, mapping: TargetMapping = SettingsStore.targetMapping()
    ) -> VocabularyDraft {
        let polish = record.operationKind == .polish
        return VocabularyDraft(
            expression: record.result,
            language: record.language,
            context: record.source,
            // A polish record's source is in its own language; a translation's source language was
            // never stored, and a wrong tag would make the model explain the wrong words.
            contextLanguage: polish ? record.language : nil,
            polishBefore: polish ? record.source : nil,
            polishAfter: polish ? record.result : nil,
            definitionLocale: record.lookupOrigins(mapping: mapping).result.definitionLanguage)
    }
}
