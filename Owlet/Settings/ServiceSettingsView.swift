import SwiftUI

struct ServiceSettingsView: View {
    @AppStorage(SettingsStore.providerKey) private var provider = Provider.openAICompatible
    @AppStorage(SettingsStore.baseURLKey) private var baseURL = ""
    @AppStorage(SettingsStore.modelKey) private var model = ""
    @AppStorage(SettingsStore.panelPositionKey) private var panelPosition = PanelPosition.fixed
    @State private var apiKey = ""
    @State private var saved = false
    @State private var models: Models = .idle

    enum Models: Equatable {
        case idle, loading
        case loaded([String])
        case failed(String)
    }

    var body: some View {
        Form {
            Section("模型服务") {
                Picker("服务商", selection: $provider) {
                    ForEach(Provider.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                TextField("Base URL", text: $baseURL, prompt: Text("https://api.openai.com/v1"))
                SecureField("API Key", text: $apiKey, prompt: Text("sk-…"))
                modelField
                modelStatus
            }
            Section("浮窗") {
                Picker("浮窗位置", selection: $panelPosition) {
                    ForEach(PanelPosition.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }
        }
        .formStyle(.grouped)
        .safeAreaBar(edge: .bottom) {
            PageFooter {
                if saved { Label("已保存", systemImage: "checkmark") }
                // Feedback for the list read sits by the action that started it, not in the row.
                if models == .loading { ProgressView().controlSize(.small) }
            } trailing: {
                Button("保存设置") {
                    saved = SettingsStore.setAPIKey(apiKey, for: provider)
                    if saved { loadModels() }
                }
                .buttonStyle(.glassProminent)
            }
        }
        .navigationTitle("设置")
        .onAppear {
            apiKey = SettingsStore.apiKey(for: provider) ?? ""
            loadModels()
        }
        .onChange(of: provider) { _, new in
            if let preset = new.preset { (baseURL, model) = preset }
            apiKey = SettingsStore.apiKey(for: new) ?? ""
            saved = false
            loadModels()
        }
    }

    @ViewBuilder private var modelField: some View {
        if provider == .deepSeek {
            // The row keeps the same control whatever the list is doing: a save reloads the options
            // underneath a picker that stays put, instead of turning the name into a loading field.
            Picker("模型名称", selection: $model) {
                ForEach(modelOptions, id: \.self) { Text($0).tag($0) }
            }
        } else {
            modelText
        }
    }

    private var modelOptions: [String] { Self.modelOptions(for: models, model: model) }

    /// What the picker offers: the last list that loaded, plus the saved model so a name the list
    /// no longer offers stays selectable. Before the first list arrives that is just the saved name.
    static func modelOptions(for models: Models, model: String) -> [String] {
        guard case .loaded(let ids) = models else { return model.isEmpty ? [] : [model] }
        return model.isEmpty || ids.contains(model) ? ids : [model] + ids
    }

    /// The failure sits under the control rather than replacing it, so a bad key never changes what
    /// the model row is.
    @ViewBuilder private var modelStatus: some View {
        if case .failed(let message) = models {
            HStack(spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                GlassEffectContainer {
                    Button("重试") { loadModels() }.buttonStyle(.glass)
                }
            }
        }
    }

    private var modelText: some View {
        TextField("模型名称", text: $model, prompt: Text("填写服务商提供的模型名称"))
    }

    /// DeepSeek only: fetch the model list once a key is saved; other providers stay free-form.
    private func loadModels() {
        guard provider == .deepSeek, let url = URL(string: baseURL),
            let key = SettingsStore.apiKey(for: provider), !key.isEmpty
        else {
            models = .idle
            return
        }
        models = .loading
        Task {
            do {
                models = .loaded(try await ModelClient().listModels(baseURL: url, apiKey: key))
            } catch {
                models = .failed((error as? ModelError)?.message ?? error.localizedDescription)
            }
        }
    }
}
