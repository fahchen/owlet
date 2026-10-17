import AppKit
import SwiftUI

@MainActor @Observable
final class TextProcessingModel {
    enum State: Equatable {
        case idle
        case loading
        case success(String)
        /// The message the user reads, and what kind of problem it was, so a view can choose the way
        /// out by the failure itself instead of by its (translated) wording.
        case failure(String, kind: ModelError.Kind = .service)
        case missingConfig
    }

    var input = "" {
        didSet {
            // A result belongs to the text it was computed from, so it is dropped the moment that
            // text changes: there is no cache across texts.
            if input != oldValue {
                results.removeAll()
                languages = nil
                segments = []
                lastResultText = nil
                receiving = nil
            }
        }
    }
    var operation: Operation = .translate
    private(set) var state: State = .idle
    /// Segments a still-running stream has already completed, for display only (BDR-0017). They have
    /// never been through `TranslationResult.parse`, so they are not a result: no copy, no replace,
    /// no history. nil once the request is over or nothing displayable has arrived yet.
    private(set) var receiving: [TranslationResult.Segment]?
    /// Whether a request is streaming and has shown something: while true, the result actions must
    /// wait and a press on them owes the user a visible reason.
    var isReceiving: Bool {
        receiving?.isEmpty == false && state == .loading
    }
    /// The text of the latest finished result for this input, kept through a later failure: a good
    /// result is not lost to a retry that did not work, and the page shows it beside the error.
    private(set) var lastResultText: String?
    /// Languages of the latest successful result, so a collected expression keeps its own language.
    private(set) var languages: (source: String, target: String)?
    /// Source/target pairs of the latest successful result, so Sentence by Sentence groups by the response's own
    /// pairing instead of guessing from punctuation or display lines.
    private(set) var segments: [TranslationResult.Segment] = []
    /// Results already computed for the current text, so switching the operation back and forth does
    /// not pay for the same request twice.
    private var results: [ResultKey: TranslationResult] = [:]

    private struct ResultKey: Hashable {
        let operation: Operation
        let language: String
    }
    private let client: ModelClient
    private let config: () -> ServiceConfig?
    private var operationID = 0
    private var task: Task<Void, Never>?
    /// True once a produced result still owes its one automatic learning decision; the claim below
    /// clears it, so a result the user has already seen is never retroactively requested.
    private var autoLearningPending = false

    /// Consumes the pending automatic learning decision for the newest result, returning true only
    /// for the first caller; the model keeps it so rebuilding a view cannot re-run an old request.
    func claimAutoLearningRequest() -> Bool {
        defer { autoLearningPending = false }
        return autoLearningPending
    }

    init(client: ModelClient, config: @escaping () -> ServiceConfig?) {
        self.client = client
        self.config = config
    }

    /// Cancels any in-flight processing and ignores its late result.
    func cancel() {
        task?.cancel()
        operationID += 1
        if state == .loading { state = .idle }
        // A stopped stream's text is not a result; it must not survive into what comes next.
        receiving = nil
    }

    /// Shows an error that happened outside a processing request.
    func fail(_ message: String) {
        cancel()
        state = .failure(message)
    }

    /// Whether changing the operation or languages should request a new result.
    var shouldReprocessOnOptionChange: Bool {
        switch state {
        case .success, .failure, .missingConfig: true
        case .idle, .loading: false
        }
    }

    /// Starts the current operation; any in-flight one is cancelled and its result ignored. A result
    /// already computed for this text and this pair of settings is served from the cache instead.
    ///
    /// `onFirstPartial` is called once, on the main actor, when the stream has completed its first
    /// displayable piece; a panel uses it to expand and show the arrival.
    @discardableResult
    func process(
        to targetLanguage: String, onFirstPartial: (@MainActor () -> Void)? = nil
    ) -> Task<Void, Never>? {
        task?.cancel()
        operationID += 1
        autoLearningPending = false
        let id = operationID
        let text = input
        let operation = operation
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            state = .idle
            receiving = nil
            return nil
        }
        guard let config = config() else {
            state = .missingConfig
            receiving = nil
            return nil
        }
        let key = ResultKey(operation: operation, language: targetLanguage)
        if let ready = results[key] {
            lastResultText = ready.text
            // A finished task, so a caller that awaits the request behaves the same either way — the
            // panel's one-shot write-back has to reach the result whether it was computed or cached.
            state = .success(ready.text)
            languages = (ready.sourceLanguage, ready.targetLanguage)
            segments = ready.segments
            receiving = nil
            return Task {}
        }
        state = .loading
        receiving = nil
        let client = client
        let task = Task {
            let outcome: State
            var full: TranslationResult?
            do {
                let result = try await client.processResult(
                    text, operation: operation, to: targetLanguage, config: config,
                    // The enclosing Task already owns `self` until the request completes, so a
                    // weak capture here would only diverge from it.
                    partial: { accumulated in
                        await self.deliver(accumulated, id: id, then: onFirstPartial)
                    })
                full = result
                outcome = .success(result.text)
            } catch let error as ModelError {
                outcome = .failure(error.message, kind: error.kind)
            } catch is CancellationError {
                return
            } catch {
                outcome = .failure(error.localizedDescription)
            }
            guard id == self.operationID else { return }
            if let full {
                self.results[key] = full
                self.lastResultText = full.text
                self.languages = (full.sourceLanguage, full.targetLanguage)
                self.segments = full.segments
            }
            self.state = outcome
            // The arrival is over either way: a finished result replaces it, a failure must never
            // leave partial text behind.
            self.receiving = nil
            if case .success = outcome { self.autoLearningPending = true }
        }
        self.task = task
        return task
    }

    /// One step of the arriving stream: the segments the accumulated content has completed become
    /// the display's incoming text. Everything else — raw JSON, later changes, a superseded
    /// request's late content — is dropped, and the first displayable piece wakes the listener once.
    private func deliver(
        _ accumulated: String, id: Int, then onFirstPartial: (@MainActor () -> Void)?
    ) {
        guard id == operationID, case .loading = state, !Task.isCancelled else { return }
        let pairs = PartialReply.segments(from: accumulated)
        let first = (receiving ?? []).isEmpty && !pairs.isEmpty
        guard first || pairs.count != receiving?.count else { return }
        receiving = pairs
        if first { onFirstPartial?() }
    }
}
