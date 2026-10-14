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
        case loaded([ModelOption])
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
                effortSupport
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
        // A different provider is a different key, its own preset, its own executable and its own
        // remembered model name.
        .onChange(of: provider) { old, new in
            model = Self.switchedModel(from: old, to: new, current: model)
            if let preset = new.preset { baseURL = preset.baseURL }
            apiKey = SettingsStore.apiKey(for: new) ?? ""
            agentExecutable = SettingsStore.agentPath(for: new) ?? ""
            agent = .idle
            // Choosing an agent looks for it right away, so the row is filled in without pressing anything.
            if new.isLocalAgent { Task { await look(adopt: false) } }
            loadModels()
        }
    }

    private func providerRow(_ option: Provider) -> some View {
        Text(verbatim: Self.providerTitle(option, installed: installed, scanned: scanned))
            .tag(option)
    }

    /// What a provider's row reads. A local agent the scan could not find is marked rather than hidden:
    /// the user can only point the app at a CLI by hand if the agent is still in the list
    /// (BDR-0013 §10).
    static func providerTitle(_ option: Provider, installed: Set<Provider>, scanned: Bool) -> String {
        let title = L10n.shared.string(option.title.key)
        guard option.isLocalAgent, scanned, !installed.contains(option) else { return title }
        return L10n.shared.string("%@ (not detected)", title)
    }

    /// The remote services, always offered.
    private var remoteProviders: [Provider] { Provider.allCases.filter { !$0.isLocalAgent } }

    /// The local agents the list offers: every one of them, always. A machine whose shell configuration
    /// the app cannot guess must still be able to point it at a CLI by hand, so a not-detected agent is
    /// marked and selectable, never hidden (BDR-0013 §10).
    static func offeredAgents() -> [Provider] {
        Provider.allCases.filter(\.isLocalAgent)
    }

    private var agentProviders: [Provider] { Self.offeredAgents() }

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
            if Self.adoptsFoundPath(
                adopt: adopt, saved: saved,
                isExecutable: { FileManager.default.isExecutableFile(atPath: $0) })
            {
                agentExecutable = executable.path
                SettingsStore.setAgentPath(executable.path, for: provider)
            }
            installed.insert(provider)
            agent = .found(version: version)
            await scanFlags(executable)
        case .failed(let message):
            agent = .failed(message)
        }
        // The model list comes from the executable, so it is read once that is known.
        loadModels()
    }

    /// Whether a lookup's answer may replace the saved path. A path the user chose by hand is theirs:
    /// only an absent or no-longer-runnable one is replaced (BDR-0013 §8).
    static func adoptsFoundPath(adopt: Bool, saved: String?, isExecutable: (String) -> Bool) -> Bool {
        adopt || saved == nil || !isExecutable(saved ?? "")
    }

    /// Caches what this CLI version has and accepts, so a request never sends a `--disable` name it
    /// would reject (BDR-0013 §2). A scan that fails leaves the last answer in place, which keeps the
    /// failure mode at "fewer flags this run".
    private func scanFlags(_ executable: URL) async {
        guard provider == .codexCLI,
            let scan = await LocalAgent.codexScan(executable: executable)
        else { return }
        SettingsStore.setAgentFeatures(scan.features, for: provider)
        SettingsStore.setAgentOverrides(scan.overrides, for: provider)
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
        // The user has just said where the CLI is, so the row no longer reads as "not detected".
        installed.insert(provider)
        agent = .idle
    }

    @ViewBuilder private var modelField: some View {
        if provider == .deepSeek {
            // The row keeps the same control whatever the list is doing, instead of turning the name
            // into a loading field.
            Picker(L10n.shared.string("Model Name"), selection: $model) {
                ForEach(modelOptions, id: \.self) { Text(verbatim: $0.label).tag($0.id) }
            }
        } else if listsModels {
            // An agent whose list this app can read gets the same picker as the HTTP services, with its
            // own default as a real first choice.
            Picker(L10n.shared.string("Model Name"), selection: $model) {
                ForEach(agentModelOptions, id: \.self) { modelRow($0) }
            }
        } else {
            TextField(
                L10n.shared.string("Model Name"), text: $model, prompt: Text(modelPrompt))
        }
    }

    /// Whether the model name is a picker, from what the agent can offer and what the last read made of
    /// it. A command source always gets one: it answers on demand, so the saved name is a real option
    /// even before the answer. A cached catalog only gets one once it really produced a list, and
    /// otherwise keeps the free-form field — an empty picker would read as "this agent has no models"
    /// when the truth is that nothing could be read.
    private var listsModels: Bool { Self.listsModels(provider.localAgent?.modelSource, models: models) }

    static func listsModels(_ source: LocalAgentKind.ModelSource?, models: Models) -> Bool {
        guard let source else { return false }
        if source.emptyAnswerIsFinal { return true }
        guard case .loaded(let options) = models else { return false }
        return !options.isEmpty
    }

    private var modelPrompt: String {
        provider.isLocalAgent
            ? L10n.shared.string("Leave empty to use the agent's own default model")
            : L10n.shared.string("Enter the model name the provider gives you")
    }

    /// The agent's own default comes first: leaving the model empty is a real choice for a CLI that
    /// picks its own model, not an omission.
    private var agentModelOptions: [ModelOption] { [ModelOption(id: "")] + modelOptions }

    @ViewBuilder private func modelRow(_ option: ModelOption) -> some View {
        if option.id.isEmpty {
            Text(L10n.shared.string("The agent's own default")).tag("")
        } else {
            Text(verbatim: option.label).tag(option.id)
        }
    }

    private var modelOptions: [ModelOption] { Self.modelOptions(for: models, model: model) }

    /// What the picker offers: the last list that loaded, plus the saved model so a name the list no
    /// longer offers stays selectable. Before the first list arrives that is just the saved name.
    static func modelOptions(for models: Models, model: String) -> [ModelOption] {
        guard case .loaded(let options) = models else {
            return model.isEmpty ? [] : [ModelOption(id: model)]
        }
        return model.isEmpty || options.contains { $0.id == model }
            ? options : [ModelOption(id: model)] + options
    }

    /// What a provider switch leaves in the shared model field: the name the user had is remembered for
    /// the provider it was typed for, then the new provider's remembered name takes its place — or its
    /// default the first time round. It takes `old` explicitly because that is who the text belongs to,
    /// and the pane's `provider` has already moved on by the time this runs.
    static func switchedModel(
        from old: Provider, to new: Provider, current: String, in defaults: UserDefaults = .standard
    ) -> String {
        SettingsStore.setModel(current, for: old, in: defaults)
        return SettingsStore.model(for: new, in: defaults) ?? new.defaultModel
    }

    /// What the selected agent model said it accepts, next to the model it belongs to (E2). The value
    /// sent is the nearest lower level in that list; a model that reasons not at all gets no parameter.
    @ViewBuilder private var effortSupport: some View {
        if let efforts = selectedEfforts {
            if efforts.isEmpty {
                Text(L10n.shared.string("This model does not use reasoning effort"))
                    .foregroundStyle(.secondary)
            } else {
                Text(
                    L10n.shared.string(
                        "This model supports: %@",
                        efforts.map { L10n.shared.string($0.title.key) }.joined(separator: "／"))
                )
                .foregroundStyle(.secondary)
            }
        }
    }

    /// The levels the selected model accepts, from the list the scan stored.
    private var selectedEfforts: [EffortLevel]? {
        guard provider.isLocalAgent else { return nil }
        return SettingsStore.supportedEfforts(for: provider, model: model)
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

    /// Reads the list a provider can offer: DeepSeek's `GET /models` once a key is stored, or the list
    /// the agent's own source gives once its executable is known. Providers with neither stay free-form.
    private func loadModels() {
        if provider == .deepSeek {
            guard let url = URL(string: baseURL), let key = SettingsStore.apiKey(for: provider),
                !key.isEmpty
            else {
                models = .idle
                return
            }
            models = .loading
            Task {
                do {
                    models = .loaded(
                        try await ModelClient().listModels(baseURL: url, apiKey: key).map {
                            ModelOption(id: $0)
                        })
                } catch {
                    models = .failed((error as? ModelError)?.message ?? error.localizedDescription)
                }
            }
            return
        }
        guard let kind = provider.localAgent else {
            models = .idle
            return
        }
        let path = agentExecutable.isEmpty ? SettingsStore.agentPath(for: provider) : agentExecutable
        guard let path, FileManager.default.isExecutableFile(atPath: path) else {
            models = .idle
            return
        }
        models = .loading
        Task {
            do {
                let options = try await LocalAgent.models(
                    kind, executable: URL(fileURLWithPath: path))
                // Remember what each model accepts, so a request never sends a level it rejects.
                for option in options {
                    SettingsStore.setSupportedEfforts(
                        option.efforts, for: provider, model: option.id)
                }
                SettingsStore.setSupportedEfforts(nil, for: provider, model: "")
                models = .loaded(options)
            } catch {
                models = .failed((error as? ModelError)?.message ?? error.localizedDescription)
            }
        }
    }
}
