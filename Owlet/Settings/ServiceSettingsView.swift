import SwiftUI

struct ServiceSettingsView: View {
    /// Focus request from the panel's format-error entry point; cleared by the page once applied.
    @Binding var promptFocus: Operation?
    @AppStorage(SettingsStore.providerKey) private var provider = Provider.openAICompatible
    @AppStorage(SettingsStore.baseURLKey) private var baseURL = ""
    @AppStorage(SettingsStore.modelKey) private var model = ""
    @AppStorage(SettingsStore.panelPositionKey) private var panelPosition = PanelPosition.fixed
    @AppStorage(SettingsStore.displayModeKey) private var displayMode =
        TranslationDisplayMode.sectioned
    @AppStorage(SettingsStore.translateLearningKey) private var translateLearning = false
    @AppStorage(SettingsStore.polishLearningKey) private var polishLearning = false
    @State private var apiKey = ""
    @State private var saved = false
    @State private var models: Models = .idle
    @State private var translatePrompt = ""
    @State private var polishPrompt = ""
    /// Operations whose saved prompt differs from the built-in default, so the badge only changes
    /// after a successful save rather than while the draft is being edited.
    @State private var customized: Set<Operation> = []
    /// Operation whose draft was blank on the last save attempt, shown beside that editor.
    @State private var invalidPrompt: Operation?
    /// Drives the prompt editor focus from the page, so it survives the Section wrapper.
    @FocusState private var focusedPrompt: Operation?

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
            Section("文本处理") {
                Picker("翻译显示方式", selection: $displayMode) {
                    ForEach(TranslationDisplayMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }
            Section("学习") {
                Toggle("翻译后自动请求学习表达", isOn: $translateLearning)
                Toggle("润色后自动请求学习表达", isOn: $polishLearning)
            }
            Section("浮窗") {
                Picker("浮窗位置", selection: $panelPosition) {
                    ForEach(PanelPosition.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }
            PromptSettingsView(
                translateDraft: $translatePrompt,
                polishDraft: $polishPrompt,
                focused: $focusedPrompt,
                customized: customized,
                invalid: invalidPrompt)
        }
        .formStyle(.grouped)
        .safeAreaBar(edge: .bottom) {
            PageFooter {
                if saved { Label("已保存", systemImage: "checkmark") }
                // Feedback for the list read sits by the action that started it, not in the row.
                if models == .loading { ProgressView().controlSize(.small) }
            } trailing: {
                Button("保存设置", action: save)
                    .buttonStyle(.glassProminent)
            }
        }
        .navigationTitle("设置")
        .onAppear {
            apiKey = SettingsStore.apiKey(for: provider) ?? ""
            loadModels()
            loadPrompts()
            applyPromptFocus()
        }
        .onChange(of: promptFocus) { _, _ in applyPromptFocus() }
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

    /// Loads the effective prompts into the drafts and remembers which ones are customised.
    private func loadPrompts() {
        translatePrompt = SettingsStore.prompt(for: .translate)
        polishPrompt = SettingsStore.prompt(for: .polish)
        customized = Self.customizedOperations()
        invalidPrompt = nil
    }

    /// Saves service settings and both prompts; a blank prompt blocks the whole save so the settings
    /// can never be left half applied.
    private func save() {
        let drafts: [Operation: String] = [.translate: translatePrompt, .polish: polishPrompt]
        if let blank = SettingsStore.setPrompts(drafts) {
            invalidPrompt = blank
            saved = false
            return
        }
        invalidPrompt = nil
        customized = Self.customizedOperations()
        saved = SettingsStore.setAPIKey(apiKey, for: provider)
        if saved { loadModels() }
    }

    private static func customizedOperations() -> Set<Operation> {
        Set(Operation.allCases.filter { SettingsStore.isCustomized($0) })
    }

    /// Focuses the editor the panel's format-error entry asked for, then clears the one-shot request.
    private func applyPromptFocus() {
        guard let operation = promptFocus else { return }
        focusedPrompt = operation
        promptFocus = nil
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
