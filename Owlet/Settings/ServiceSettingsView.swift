import SwiftUI

struct ServiceSettingsView: View {
    @AppStorage(SettingsStore.providerKey) private var provider = Provider.openAICompatible
    @AppStorage(SettingsStore.baseURLKey) private var baseURL = ""
    @AppStorage(SettingsStore.modelKey) private var model = ""
    @State private var apiKey = ""
    @State private var saved = false

    var body: some View {
        Form {
            Picker("Provider", selection: $provider) {
                ForEach(Provider.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            TextField("Base URL", text: $baseURL, prompt: Text("https://api.openai.com/v1"))
            TextField("Model", text: $model)
            SecureField("API Key", text: $apiKey)
            HStack {
                Button("Save API Key") { saved = SettingsStore.setAPIKey(apiKey, for: provider) }
                if saved { Text("Saved").foregroundStyle(.secondary) }
            }
        }
        .padding()
        .frame(width: 420)
        .onAppear { apiKey = SettingsStore.apiKey(for: provider) ?? "" }
        .onChange(of: provider) { _, new in
            if let preset = new.preset { (baseURL, model) = preset }
            apiKey = SettingsStore.apiKey(for: new) ?? ""
            saved = false
        }
    }
}
