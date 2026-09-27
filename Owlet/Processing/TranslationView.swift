import AppKit
import SwiftUI

@MainActor @Observable
final class TranslationModel {
    enum State: Equatable {
        case idle
        case loading
        case success(String)
        case failure(String)
        case missingConfig
    }

    var input = ""
    private(set) var state: State = .idle
    private let client: ModelClient
    private let config: () -> ServiceConfig?
    private var operationID = 0
    private var task: Task<Void, Never>?

    init(client: ModelClient, config: @escaping () -> ServiceConfig?) {
        self.client = client
        self.config = config
    }

    /// Starts a translation; any in-flight one is cancelled and its result ignored.
    @discardableResult
    func translate(to targetLanguage: String) -> Task<Void, Never>? {
        task?.cancel()
        operationID += 1
        let id = operationID
        let text = input
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            state = .idle
            return nil
        }
        guard let config = config() else {
            state = .missingConfig
            return nil
        }
        state = .loading
        let client = client
        let task = Task {
            let result: State
            do {
                result = .success(
                    try await client.translate(text, to: targetLanguage, config: config))
            } catch let error as ModelError {
                result = .failure(error.message)
            } catch is CancellationError {
                return
            } catch {
                result = .failure(error.localizedDescription)
            }
            guard id == self.operationID else { return }
            self.state = result
        }
        self.task = task
        return task
    }
}

struct TranslationView: View {
    @Bindable var model: TranslationModel
    @AppStorage(SettingsStore.targetLanguageKey) private var targetLanguage =
        SettingsStore.defaultTargetLanguage

    static let languages = [
        ("zh-Hans", "简体中文"), ("zh-Hant", "繁體中文"), ("en", "English"), ("ja", "日本語"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextEditor(text: $model.input)
                .font(.body)
                .frame(minHeight: 120)
            HStack {
                Button("Translate") { model.translate(to: targetLanguage) }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(model.state == .loading)
                if model.state == .loading { ProgressView().controlSize(.small) }
            }
            resultView
            Spacer(minLength: 0)
        }
        .padding()
        .frame(minWidth: 480, minHeight: 360)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Picker("Target Language", selection: $targetLanguage) {
                    ForEach(Self.languages, id: \.0) { Text($0.1).tag($0.0) }
                }
            }
        }
    }

    @ViewBuilder private var resultView: some View {
        switch model.state {
        case .idle, .loading:
            EmptyView()
        case .success(let text):
            VStack(alignment: .leading) {
                Text(text).textSelection(.enabled)
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
            }
        case .failure(let message):
            HStack {
                Text(message).foregroundStyle(.red)
                Button("Retry") { model.translate(to: targetLanguage) }
            }
        case .missingConfig:
            HStack {
                Text("Service is not configured: Base URL, model and API key are required.")
                SettingsLink { Text("Open Service Settings") }
            }
        }
    }
}
