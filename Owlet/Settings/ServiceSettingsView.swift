import SwiftUI

struct ServiceSettingsView: View {
    @AppStorage(SettingsStore.baseURLKey) private var baseURL = ""
    @AppStorage(SettingsStore.modelKey) private var model = ""
    @State private var apiKey = SettingsStore.apiKey() ?? ""
    @State private var saved = false

    var body: some View {
        Form {
            TextField("Base URL", text: $baseURL, prompt: Text("https://api.openai.com/v1"))
            TextField("Model", text: $model)
            SecureField("API Key", text: $apiKey)
            HStack {
                Button("Save API Key") { saved = SettingsStore.setAPIKey(apiKey) }
                if saved { Text("Saved").foregroundStyle(.secondary) }
            }
        }
        .padding()
        .frame(width: 420)
    }
}
