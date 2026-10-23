import Foundation
import Observation

/// Turns a successful result into a history entry by watching the translating model, so the
/// processing layer stays unaware of history and can neither lose a result nor double-record one.
@MainActor
final class HistoryRecorder {
    private let store: HistoryStore
    private var watched: [ObjectIdentifier: Watched] = [:]
    /// The latest recording scheduled by an observed change; tests await it to assert without polling.
    private(set) var task: Task<Void, Never>?

    private struct Watched {
        weak var model: TextProcessingModel?
        var lastState: TextProcessingModel.State
    }

    init(store: HistoryStore = .shared) {
        self.store = store
    }

    /// Observes a model once; a repeated call for the same model is ignored, so re-opening a window
    /// cannot start a second recording chain.
    func observe(_ model: TextProcessingModel) {
        let id = ObjectIdentifier(model)
        guard watched[id] == nil else { return }
        watched[id] = Watched(model: model, lastState: model.state)
        track(id)
    }

    /// Awaits the recording the last observed change scheduled.
    func flush() async {
        await task?.value
    }

    private func track(_ id: ObjectIdentifier) {
        withObservationTracking {
            _ = watched[id]?.model?.state
        } onChange: { [weak self] in
            // Every watched model mutates on the main actor, so the handler can re-enter it directly.
            MainActor.assumeIsolated {
                self?.stateWillChange(id)
            }
        }
    }

    private func stateWillChange(_ id: ObjectIdentifier) {
        guard let previous = watched[id]?.lastState else { return }
        // Re-register before reading the new value, so a second mutation in the same run loop is caught.
        track(id)
        task = Task { @MainActor [weak self] in
            guard let self, let model = self.watched[id]?.model else { return }
            let current = model.state
            self.watched[id]?.lastState = current
            // Only a request that ran records; a cache hit re-publishes an older success.
            guard case .success(let result) = current, case .loading = previous,
                let languages = model.languages
            else { return }
            do {
                try self.store.record(
                    operation: model.operation, source: model.input, result: result,
                    language: languages.target, sourceImage: model.sourceImage)
            } catch {
                self.store.report(error)
            }
        }
    }
}
