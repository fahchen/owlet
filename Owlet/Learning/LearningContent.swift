import Foundation
import Observation

/// The inputs a learning request needs, kept separate so the model can tell a stale request from a
/// fresh one and only re-request when the user's result actually changed.
struct LearningRequest: Equatable {
    var text: String
    var operation: Operation
    /// The result language; ignored for polish, whose result stays in the source language.
    var targetLanguage: String
    var result: String
    /// Consumes the one automatic decision for this result; the model owns that state, so a view
    /// rebuilt for an old result cannot spend a request the switch did not ask for at the time.
    var claimAutoRequest: @MainActor () -> Bool

    init(
        text: String, operation: Operation, targetLanguage: String, result: String,
        claimAutoRequest: @escaping @MainActor () -> Bool = { true }
    ) {
        self.text = text
        self.operation = operation
        self.targetLanguage = targetLanguage
        self.result = result
        self.claimAutoRequest = claimAutoRequest
    }

    /// Two requests describe the same result when their displayed content matches; the claim closure
    /// is deliberately left out, so a rebuilt view still compares equal to the request it reused.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.text == rhs.text && lhs.operation == rhs.operation
            && lhs.targetLanguage == rhs.targetLanguage && lhs.result == rhs.result
    }

    /// Builds the request from a finished result; nil until the model has one to reason about, and nil
    /// for a polish of the reader's own language, which has nothing to teach (BDR-0012). The entry
    /// point is built from this too, so the nil hides the button as well as skipping the request.
    @MainActor static func from(
        _ model: TextProcessingModel, defaults: UserDefaults = .standard
    ) -> LearningRequest? {
        guard case .success(let text) = model.state, let languages = model.languages else {
            return nil
        }
        if model.operation == .polish, !SettingsStore.learnsFrom(languages.source, in: defaults) {
            return nil
        }
        return LearningRequest(
            text: model.input, operation: model.operation, targetLanguage: languages.target,
            result: text, claimAutoRequest: { model.claimAutoLearningRequest() })
    }
}

/// Owns the optional Study Expressions disclosure: it stays silent until the user expands it, then spends at
/// most one request and never touches the main result.
@MainActor @Observable
final class LearningModel {
    enum State: Equatable {
        case idle
        case loading
        case failure(String)
        case success([LearningResult.Item])
    }

    /// The disclosure state; the section requests only when this turns true or the auto-request switch is on.
    var isExpanded = false
    private(set) var state: State = .idle
    /// The recommendation indices the user checked, so only what they chose reaches the notebook.
    var selected: Set<Int> = []
    /// The per-operation auto-request switch; off unless the user turned it on in settings.
    var autoRequest: (Operation) -> Bool = { SettingsStore.autoRequestsLearning(for: $0) }
    /// The request in flight; tests await it, the views only observe `state`.
    private(set) var task: Task<Void, Never>?

    private let client: ModelClient
    private let config: () -> ServiceConfig?
    /// Identifies the current request, so a late response cannot land on a newer operation.
    private var requestID = 0

    init(
        client: ModelClient = ModelClient(),
        config: @escaping () -> ServiceConfig? = SettingsStore.currentConfig
    ) {
        self.client = client
        self.config = config
    }

    /// Responds to expanding: requests once, and a later collapse and expand reuses whatever this produced.
    func generate(for request: LearningRequest) {
        guard state == .idle else { return }
        send(request)
    }

    /// Retries only a failed request, so one press of Retry costs exactly one request.
    func retry(for request: LearningRequest) {
        guard case .failure = state else { return }
        send(request)
    }

    /// Auto-requests on a finished result only when the switch is on, spending the one automatic
    /// decision first so neither a rebuilt view nor a toggled switch can request a seen result again.
    func generateIfAutoRequested(for request: LearningRequest) {
        guard request.claimAutoRequest() else { return }
        guard autoRequest(request.operation) else { return }
        guard state == .idle else { return }
        // The switch means "show me what there is to learn", so the column opens with the request and
        // stays open until Back closes it. Back is then the only thing that decides whether the column
        // is showing: one state, so no second flag can keep it open behind the user's back.
        isExpanded = true
        generate(for: request)
    }

    /// Drops the items and ignores any in-flight response, because they describe the old result.
    func reset() {
        task?.cancel()
        task = nil
        requestID += 1
        state = .idle
        selected = []
        isExpanded = false
    }

    /// Collects exactly the checked recommendations, carrying the meaning the learning response
    /// already returned so no checked item spends a second request.
    func collectSelected(into collection: CollectionAction, for request: LearningRequest) {
        guard case .success(let items) = state else { return }
        let polish = request.operation == .polish
        for index in selected.sorted() where items.indices.contains(index) {
            let item = items[index]
            collection.collect(
                VocabularyDraft(
                    expression: item.text, language: item.language, context: item.context,
                    contextLanguage: item.language,
                    polishBefore: polish ? request.text : nil,
                    polishAfter: polish ? request.result : nil,
                    lemma: item.lemma, definitionLocale: request.targetLanguage),
                meaning: item.meaning)
        }
    }

    private func send(_ request: LearningRequest) {
        guard let config = config() else {
            state = .failure(L10n.shared.string("The model service is not configured"))
            return
        }
        task?.cancel()
        requestID += 1
        let id = requestID
        state = .loading
        let client = client
        task = Task {
            do {
                let items = try await client.learning(
                    text: request.text, operation: request.operation,
                    targetLanguage: request.targetLanguage, result: request.result,
                    config: config)
                try Task.checkCancellation()
                guard id == self.requestID else { return }
                self.state = .success(items)
            } catch is CancellationError {
                // A newer request or a reset owns the state; leaving it alone avoids overwriting it.
            } catch {
                guard id == self.requestID else { return }
                let message = (error as? ModelError)?.message ?? error.localizedDescription
                self.state = .failure(message)
            }
        }
    }
}
