import SwiftUI

struct ServiceSettingsView: View {
    @AppStorage(SettingsStore.providerKey) private var provider = Provider.openAICompatible
    @AppStorage(SettingsStore.baseURLKey) private var baseURL = ""
    @AppStorage(SettingsStore.modelKey) private var model = ""
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
            Section("Service") {
                Picker("Provider", selection: $provider) {
                    ForEach(Provider.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                TextField("Base URL", text: $baseURL, prompt: Text("https://api.openai.com/v1"))
                modelField
                SecureField("API Key", text: $apiKey)
                HStack {
                    Spacer()
                    if saved { Text("Saved").foregroundStyle(.secondary) }
                    Button("Save API Key") {
                        saved = SettingsStore.setAPIKey(apiKey, for: provider)
                        if saved { loadModels() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .formStyle(.grouped)
        .tint(TranslationView.accent)
        .frame(width: 560)
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
        switch models {
        case .loaded(let ids):
            Picker("Model", selection: $model) {
                // Keep a saved model selectable even if the list no longer offers it.
                ForEach(ids.contains(model) ? ids : [model] + ids, id: \.self) { Text($0).tag($0) }
            }
        case .loading:
            HStack {
                TextField("Model", text: $model)
                ProgressView().controlSize(.small)
            }
        case .failed(let message):
            TextField("Model", text: $model)
            HStack {
                Text(message).foregroundStyle(.secondary)
                Button("Retry") { loadModels() }
            }
        case .idle:
            TextField("Model", text: $model)
        }
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
