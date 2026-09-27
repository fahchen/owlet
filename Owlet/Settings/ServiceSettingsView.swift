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

    @FocusState private var focus: Field?

    private enum Field { case baseURL, model, apiKey }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                GroupTitle("模型服务")
                FormRow(title: "服务商") {
                    SelectField(
                        title: "服务商", selection: $provider,
                        options: Provider.allCases.map { ($0, $0.title) }
                    )
                    .frame(width: 220)
                }
                VStack(alignment: .leading, spacing: 17) {
                    FormField(title: "Base URL") {
                        TextField("Base URL", text: $baseURL, prompt: Text("https://api.openai.com/v1"))
                            .textFieldStyle(.plain)
                            .focused($focus, equals: .baseURL)
                            .modifier(FieldBox(focused: focus == .baseURL))
                    }
                    FormField(title: "API Key") {
                        SecureField("API Key", text: $apiKey, prompt: Text("sk-…"))
                            .textFieldStyle(.plain)
                            .focused($focus, equals: .apiKey)
                            .modifier(FieldBox(focused: focus == .apiKey))
                    }
                    FormField(title: "模型名称") { modelField }
                }
                .padding(.vertical, 17)
                Picker("浮窗位置", selection: $panelPosition) {
                    ForEach(PanelPosition.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                .fixedSize()
                .padding(.vertical, 17)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
            PageFooter {
                if saved {
                    Label("已保存", systemImage: "checkmark")
                        .foregroundStyle(RoseGlass.green)
                }
            } trailing: {
                Button("保存设置") {
                    saved = SettingsStore.setAPIKey(apiKey, for: provider)
                    if saved { loadModels() }
                }
                .buttonStyle(MainButtonStyle(prominent: true))
            }
        }
        .foregroundStyle(RoseGlass.ink)
        .tint(RoseGlass.accent)
        .frame(width: 600)
        .fixedSize(horizontal: false, vertical: true)
        .background(RoseGlass.window)
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
        switch models {
        case .loaded(let ids):
            // Keep a saved model selectable even if the list no longer offers it.
            SelectField(
                title: "模型名称", selection: $model,
                options: (ids.contains(model) ? ids : [model] + ids).map { ($0, $0) })
        case .loading:
            modelText.overlay(alignment: .trailing) {
                ProgressView().controlSize(.small).padding(.trailing, 10)
            }
        case .failed(let message):
            modelText
            HStack(spacing: 8) {
                Text(message).foregroundStyle(RoseGlass.errorText)
                Spacer(minLength: 0)
                Button("重试") { loadModels() }
                    .buttonStyle(.plain)
                    .underline()
                    .foregroundStyle(RoseGlass.accent)
            }
            .font(.system(size: 11))
        case .idle:
            modelText
        }
    }

    private var modelText: some View {
        TextField("模型名称", text: $model, prompt: Text("填写服务商提供的模型名称"))
            .textFieldStyle(.plain)
            .focused($focus, equals: .model)
            .modifier(FieldBox(focused: focus == .model))
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
