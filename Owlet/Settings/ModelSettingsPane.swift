import AppKit
import SwiftUI

/// 模型 pane: how the app reaches the service, and which model and thinking level it asks for. There
/// is no save button: every control is either a `@AppStorage` binding or writes on commit, which is
/// how a settings window is expected to behave.
struct ModelSettingsPane: View {
    /// One-shot request from the panel's contract-error entry; it belongs to the prompt editors, which
    /// live on this pane.
    @Binding var promptFocus: Operation?
    @AppStorage(SettingsStore.providerKey) private var provider = Provider.openAICompatible
    @AppStorage(SettingsStore.baseURLKey) private var baseURL = ""
    @AppStorage(SettingsStore.modelKey) private var model = ""
    @AppStorage(SettingsStore.effortKey) private var effort = EffortLevel.off
    /// The key is only read back from the Keychain, never stored in defaults, so it is a draft that
    /// commits when the field is done.
    @State private var apiKey = ""
    /// The local agent's executable, kept per provider in defaults rather than in a binding, because
    /// which path applies depends on which agent is selected.
    @State private var agentExecutable = ""
    @State private var agent: Agent = .idle
    /// Which agents this machine actually has, from the scan that runs whenever the pane opens: an agent
    /// that is not installed is not offered at all.
    @State private var installed: Set<Provider> = []
    @State private var scanned = false
    @State private var models: Models = .idle
    @FocusState private var editingKey: Bool

    enum Models: Equatable {
        case idle, loading
        case loaded([String])
        case failed(String)
    }

    /// What the last lookup found. A failure leaves the saved path alone: a path the user picked by
    /// hand is better than nothing just because the lookup could not run.
    enum Agent: Equatable {
        case idle, checking
        case found(version: String)
        case failed(String)
    }

    var body: some View {
        Form {
            Section {
                Picker(L10n.shared.string("Provider"), selection: $provider) {
                    // Two sections, so the menu separates the remote services from the local agents. An
                    // empty group is left out rather than showing a separator with nothing under it.
                    Section {
                        ForEach(remoteProviders, id: \.self) { providerRow($0) }
                    }
                    if !agentProviders.isEmpty {
                        Section {
                            ForEach(agentProviders, id: \.self) { providerRow($0) }
                        }
                    }
                }
                if provider.isLocalAgent {
                    agentRows
                } else {
                    // Verbatim, or the placeholder URL renders as a link.
                    TextField(
                        L10n.shared.string("Base URL"), text: $baseURL,
                        prompt: Text(verbatim: "https://api.openai.com/v1"))
                    SecureField(L10n.shared.string("API Key"), text: $apiKey, prompt: Text(L10n.shared.string("sk-…")))
                        .focused($editingKey)
                        .onSubmit(commitKey)
                        .onChange(of: editingKey) { _, editing in
                            if !editing { commitKey() }
                        }
                }
            } header: {
                Text(L10n.shared.string("Service"))
            } footer: {
                Text(serviceFooter)
            }
            Section(L10n.shared.string("Model")) {
                modelField
                modelStatus
                Picker(L10n.shared.string("Reasoning Effort"), selection: $effort) {
                    ForEach(EffortLevel.allCases, id: \.self) {
                        Text(verbatim: L10n.shared.string($0.title.key)).tag($0)
                    }
                }
            }
            PromptSettingsView(promptFocus: $promptFocus)
        }
        .formStyle(.grouped)
        .onAppear {
            apiKey = SettingsStore.apiKey(for: provider) ?? ""
            agentExecutable = SettingsStore.agentPath(for: provider) ?? ""
            loadModels()
        }
        // The scan is async, so it is a task rather than part of `onAppear`; it runs once per opening.
        .task { await scanAgents() }
        // Leaving the pane or closing the window also ends the edit, so a key typed and left alone
        // is not lost.
        .onDisappear(perform: commitKey)
        // A different provider is a different key, its own preset and its own executable.
        .onChange(of: provider) { old, new in
            if let preset = new.preset { (baseURL, model) = preset }
            // An HTTP model name means nothing to a CLI, and the agent's own default is the better
            // starting point; a name typed for one agent survives a switch between two of them.
            if new.isLocalAgent && !old.isLocalAgent { model = "" }
            apiKey = SettingsStore.apiKey(for: new) ?? ""
            agentExecutable = SettingsStore.agentPath(for: new) ?? ""
            agent = .idle
            // Choosing an agent looks for it right away, so the row is filled in without pressing anything.
            if new.isLocalAgent { Task { await look(adopt: false) } }
            loadModels()
        }
    }

    private func providerRow(_ option: Provider) -> some View {
        Text(verbatim: L10n.shared.string(option.title.key)).tag(option)
    }

    /// The remote services, always offered.
    private var remoteProviders: [Provider] { Provider.allCases.filter { !$0.isLocalAgent } }

    /// The agents this machine has. Until the first scan answers, all of them are listed so the menu does
    /// not grow under the pointer; afterwards an agent that is not installed is gone. A path the user
    /// chose by hand keeps its agent available even when the login shell cannot find it, and the current
    /// choice stays visible even when its CLI has been removed, so the user sees what is wrong instead of
    /// a blank row.
    private var agentProviders: [Provider] {
        Provider.allCases.filter { candidate in
            guard candidate.isLocalAgent else { return false }
            if !scanned || installed.contains(candidate) || candidate == provider { return true }
            guard let saved = SettingsStore.agentPath(for: candidate) else { return false }
            return FileManager.default.isExecutableFile(atPath: saved)
        }
    }

    /// The local agent's own rows: where its executable is, a way to find one, and its version.
    @ViewBuilder private var agentRows: some View {
        LabeledContent(L10n.shared.string("Executable")) {
            Text(verbatim: agentExecutable.isEmpty ? L10n.shared.string("Not set") : agentExecutable)
                .foregroundStyle(agentExecutable.isEmpty ? .red : .secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(agentExecutable)
        }
        HStack(spacing: 12) {
            Button(L10n.shared.string("Detect"), systemImage: "magnifyingglass", action: detect)
            Button(L10n.shared.string("Choose…"), action: chooseExecutable)
            Spacer(minLength: 0)
            if agent == .checking { ProgressView().controlSize(.small) }
        }
        agentStatus
    }

    @ViewBuilder private var agentStatus: some View {
        switch agent {
        case .idle, .checking:
            EmptyView()
        case .found(let version):
            Label(detectedText(version), systemImage: "checkmark.circle")
                .foregroundStyle(.secondary)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
        }
    }

    private func detectedText(_ version: String) -> String {
        L10n.shared.string("Detected: %@", version)
    }

    private var serviceFooter: String {
        provider.isLocalAgent
            ? L10n.shared.string(
                "The agent uses its own sign-in, so no API key is needed here. Its tools, skills, project context and session files stay switched off."
            )
            : L10n.shared.string("The API key is kept in the keychain, and applies when the field loses focus.")
    }

    /// The manual 「检测」: look the agent up and take what it found.
    private func detect() {
        guard provider.isLocalAgent else { return }
        agent = .checking
        Task { await look(adopt: true) }
    }

    /// Looks for every agent on this machine. What is not installed is not offered, and the scan is
    /// also what fills the executable in the first time an agent is chosen.
    private func scanAgents() async {
        var found: Set<Provider> = []
        for candidate in Provider.allCases where candidate.isLocalAgent {
            guard let kind = candidate.localAgent, await LocalAgent.locate(kind) != nil else { continue }
            found.insert(candidate)
        }
        installed = found
        scanned = true
        // The selected agent gets its version too, so the row reads the same however the pane was opened.
        if provider.isLocalAgent { await look(adopt: false) }
    }

    /// Asks the selected agent for its executable and version. `adopt` is what the button does; a scan
    /// only fills a path when the saved one cannot be run, because a path chosen by hand is the user's.
    private func look(adopt: Bool) async {
        guard let kind = provider.localAgent else { return }
        switch await LocalAgent.detect(kind) {
        case .found(let executable, let version):
            let saved = SettingsStore.agentPath(for: provider)
            if adopt || saved == nil || !FileManager.default.isExecutableFile(atPath: saved ?? "") {
                agentExecutable = executable.path
                SettingsStore.setAgentPath(executable.path, for: provider)
            }
            installed.insert(provider)
            agent = .found(version: version)
        case .failed(let message):
            agent = .failed(message)
        }
    }

    private func chooseExecutable() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = L10n.shared.string("Choose the agent's executable file.")
        panel.prompt = L10n.shared.string("Choose")
        // These CLIs usually live in a hidden directory such as `~/.local/bin`.
        panel.showsHiddenFiles = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        agentExecutable = url.path
        SettingsStore.setAgentPath(url.path, for: provider)
        agent = .idle
    }

    @ViewBuilder private var modelField: some View {
        if provider == .deepSeek {
            // The row keeps the same control whatever the list is doing, instead of turning the name
            // into a loading field.
            Picker(L10n.shared.string("Model Name"), selection: $model) {
                ForEach(modelOptions, id: \.self) { Text($0).tag($0) }
            }
        } else {
            TextField(
                L10n.shared.string("Model Name"), text: $model, prompt: Text(modelPrompt))
        }
    }

    private var modelPrompt: String {
        provider.isLocalAgent
            ? L10n.shared.string("Leave empty to use the agent's own default model")
            : L10n.shared.string("Enter the model name the provider gives you")
    }

    private var modelOptions: [String] { Self.modelOptions(for: models, model: model) }

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
            // As everywhere else: a red message and a plain retry.
            HStack(spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                Spacer(minLength: 0)
                Button(L10n.shared.string("Retry"), systemImage: "arrow.clockwise") { loadModels() }
                    .buttonStyle(.plain)
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
