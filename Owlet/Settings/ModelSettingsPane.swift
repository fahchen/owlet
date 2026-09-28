import SwiftUI

/// 模型 pane: how the app reaches the service, and which model and thinking level it asks for. There
/// is no save button: every control is either a `@AppStorage` binding or writes on commit, which is
/// how a settings window is expected to behave.
struct ModelSettingsPane: View {
    @AppStorage(SettingsStore.providerKey) private var provider = Provider.openAICompatible
    @AppStorage(SettingsStore.baseURLKey) private var baseURL = ""
    @AppStorage(SettingsStore.modelKey) private var model = ""
    @AppStorage(SettingsStore.effortKey) private var effort = EffortLevel.automatic
    /// The key is only read back from the Keychain, never stored in defaults, so it is a draft that
    /// commits when the field is done.
    @State private var apiKey = ""
    @State private var models: Models = .idle
    @FocusState private var editingKey: Bool

    enum Models: Equatable {
        case idle, loading
        case loaded([String])
        case failed(String)
    }

    var body: some View {
        Form {
            Section {
                Picker("服务商", selection: $provider) {
                    ForEach(Provider.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                TextField("Base URL", text: $baseURL, prompt: Text("https://api.openai.com/v1"))
                SecureField("API Key", text: $apiKey, prompt: Text("sk-…"))
                    .focused($editingKey)
                    .onSubmit(commitKey)
                    .onChange(of: editingKey) { _, editing in
                        if !editing { commitKey() }
                    }
            } header: {
                Text("服务")
            } footer: {
                Text("API Key 存在钥匙串里；离开输入框后生效。")
            }
            Section("模型") {
                modelField
                modelStatus
                effortField
            }
        }
        .formStyle(.grouped)
        .onAppear {
            apiKey = SettingsStore.apiKey(for: provider) ?? ""
            loadModels()
        }
        // Leaving the pane or closing the window also ends the edit, so a key typed and left alone
        // is not lost.
        .onDisappear(perform: commitKey)
        // A different provider is a different key and its own preset, so the row is re-read.
        .onChange(of: provider) { _, new in
            if let preset = new.preset { (baseURL, model) = preset }
            apiKey = SettingsStore.apiKey(for: new) ?? ""
            loadModels()
        }
    }

    @ViewBuilder private var modelField: some View {
        if provider == .deepSeek {
            // The row keeps the same control whatever the list is doing, instead of turning the name
            // into a loading field.
            Picker("模型名称", selection: $model) {
                ForEach(modelOptions, id: \.self) { Text($0).tag($0) }
            }
        } else {
            TextField("模型名称", text: $model, prompt: Text("填写服务商提供的模型名称"))
        }
    }

    private var modelOptions: [String] { Self.modelOptions(for: models, model: model) }

    /// 思考强度 sits under the model row; the hint shows what the current model will actually
    /// receive, since the same level maps to different values per model (see `ModelEffort`).
    private var effortField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker("思考强度", selection: $effort) {
                ForEach(EffortLevel.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Text(ModelEffort.summary(for: effort, model: model))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    /// What the picker offers: the last list that loaded, plus the saved model so a name the list no
    /// longer offers stays selectable. Before the first list arrives that is just the saved name.
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

    /// Writes the key on leaving the field, then reads the model list the key unlocks.
    private func commitKey() {
        SettingsStore.setAPIKey(apiKey, for: provider)
        loadModels()
    }

    /// DeepSeek only: fetch the model list once a key is stored; other providers stay free-form.
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
