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
    var operation: Operation = .translate
    private(set) var state: State = .idle
    private let client: ModelClient
    private let config: () -> ServiceConfig?
    private var operationID = 0
    private var task: Task<Void, Never>?

    init(client: ModelClient, config: @escaping () -> ServiceConfig?) {
        self.client = client
        self.config = config
    }

    /// Cancels any in-flight translation and ignores its late result.
    func cancel() {
        task?.cancel()
        operationID += 1
        if state == .loading { state = .idle }
    }

    /// Shows an error that happened outside a translation request.
    func fail(_ message: String) {
        cancel()
        state = .failure(message)
    }

    /// Starts the current operation; any in-flight one is cancelled and its result ignored.
    @discardableResult
    func translate(to targetLanguage: String) -> Task<Void, Never>? {
        task?.cancel()
        operationID += 1
        let id = operationID
        let text = input
        let operation = operation
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
                    try await client.process(
                        text, operation: operation, to: targetLanguage, config: config))
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
    /// Used where `SettingsLink` has no scene, e.g. the floating panel.
    var openSettings: (() -> Void)?
    /// Writes the result back to the original selection; nil when there is no source.
    var replace: ((String) -> Void)?
    var replaceMessage: String?
    @AppStorage(SettingsStore.targetLanguageKey) private var targetLanguage =
        SettingsStore.defaultTargetLanguage

    /// Prototype rose accent (oklch(0.55 0.16 5) approximated in sRGB).
    static let accent = Color(red: 0.72, green: 0.24, blue: 0.42)

    static let languages = [
        ("zh-Hans", "简体中文"), ("zh-Hant", "繁體中文"), ("en", "English"), ("ja", "日本語"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextEditor(text: $model.input)
                .font(.body)
                .frame(minHeight: 120)
            HStack {
                Button(model.operation.title) { model.translate(to: targetLanguage) }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(model.state == .loading)
                if model.state == .loading { ProgressView().controlSize(.small) }
            }
            resultView
            Spacer(minLength: 0)
        }
        .padding()
        .frame(minWidth: 560, minHeight: 360)
        .tint(Self.accent)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Image("OwletMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .accessibilityLabel("Owlet")
            }
            .sharedBackgroundVisibility(.hidden)
            ToolbarItemGroup(placement: .primaryAction) {
                if model.operation == .translate {
                    Picker("Target Language", selection: $targetLanguage) {
                        ForEach(Self.languages, id: \.0) { Text($0.1).tag($0.0) }
                    }
                }
                Picker("Operation", selection: $model.operation) {
                    ForEach(Operation.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    @ViewBuilder private var resultView: some View {
        switch model.state {
        case .idle, .loading:
            EmptyView()
        case .success(let text):
            VStack(alignment: .leading, spacing: 10) {
                Text("Result").font(.caption).foregroundStyle(.secondary)
                Text(text).textSelection(.enabled)
                Divider()
                HStack {
                    Spacer()
                    Button("Copy", systemImage: "doc.on.doc") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    }
                    if let replace {
                        Button("Replace") { replace(text) }
                            .buttonStyle(.glassProminent)
                    }
                }
                if let replaceMessage { Text(replaceMessage).foregroundStyle(.red) }
            }
        case .failure(let message):
            HStack {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                Button("Retry") { model.translate(to: targetLanguage) }
                settingsButton
            }
        case .missingConfig:
            HStack {
                Label("Service is not configured: Base URL, model and API key are required.", systemImage: "gearshape")
                settingsButton
            }
        }
    }

    @ViewBuilder private var settingsButton: some View {
        if let openSettings {
            Button("Open Service Settings", action: openSettings)
        } else {
            SettingsLink { Text("Open Service Settings") }
        }
    }
}
