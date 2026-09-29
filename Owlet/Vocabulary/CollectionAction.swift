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

    /// Saves the draft at once; a missing meaning is then filled by the model.
    @discardableResult
    func collect(_ draft: VocabularyDraft) -> VocabularyEntry? {
        do {
            let entry = try store.collect(draft)
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
            let trimmed = meaning.trimmingCharacters(in: .whitespacesAndNewlines)
            if entry.meaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !trimmed.isEmpty {
                entry.meaning = trimmed
                try store.save()
            }
            status = .saved
            return entry
        } catch {
            status = .saveFailed(error.localizedDescription)
            return nil
        }
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
        // The meaning contract only validates when the expression appears in its context, and a 原句
        // collected from 历史详情 is in the record's other language, so the expression stands in for it.
        let stored = entry.contexts.first?.source ?? ""
        let context = stored.localizedStandardContains(expression) ? stored : expression
        task = Task { [store] in
            do {
                let meaning = try await client.fillMeaning(
                    expression: expression, language: language, context: context, config: config)
                try Task.checkCancellation()
                entry.meaning = meaning
                try store.save()
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
        let polish = model.operation == .polish
        return VocabularyDraft(
            expression: expression,
            language: region == .source ? languages.source : languages.target,
            context: regionText,
            polishBefore: polish ? source : nil,
            polishAfter: polish ? result : nil)
    }

    /// Builds the snapshot for collecting from 历史详情: the result is the expression and the record's
    /// own source text is the context, so the entry keeps its 原句 after the history is deleted, and a
    /// polish record keeps the before/after comparison it was collected from.
    @MainActor static func from(record: HistoryRecord) -> VocabularyDraft {
        let polish = record.operationKind == .polish
        return VocabularyDraft(
            expression: record.result,
            language: record.language,
            context: record.source,
            polishBefore: polish ? record.source : nil,
            polishAfter: polish ? record.result : nil)
    }
}
