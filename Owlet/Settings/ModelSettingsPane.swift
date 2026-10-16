import AppKit
import SwiftUI

/// Model pane: how the app reaches the service, and which model and thinking level it asks for. There
/// is no save button: every control is either a `@AppStorage` binding or writes on commit, which is
/// how a settings window is expected to behave.
struct ModelSettingsPane: View {
    /// One-shot request from the panel's contract-error entry; it belongs to the prompt editors, which
    /// live on this pane.
    @Binding var promptFocus: Operation?
    /// The chosen service's id: a vendor preset id or a local agent's raw value. Seeded from the store
    /// on appear and written back through `select`, because choosing a vendor also writes its address.
    @State private var serviceID = ServicePreset.customID
    @AppStorage(SettingsStore.baseURLKey) private var baseURL = ""
    @AppStorage(SettingsStore.modelKey) private var model = ""
    /// A level's raw value, or a value the user typed (`SettingsStore.customEffort`).
    @AppStorage(SettingsStore.effortKey) private var effort = EffortLevel.off.rawValue
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
    /// The models the last successful read produced. Kept through a reading or a failure, so the
    /// Presets menu never empties out from under the user mid-request.
    @State private var offered: [ModelOption] = []
    /// Why the last model-list read failed; a successful one clears it.
    @State private var listFailure: String?
    @FocusState private var editingKey: Bool
    @FocusState private var editingBaseURL: Bool
    @State private var check: Check = .idle

    /// Model lists and the Test button go through this client, so a preview can answer with fixtures.
    private let client: ModelClient
    /// Reads a service's key; injectable so a preview never touches the real keychain.
    private let readKey: (String) -> String?

    /// `check` lets the preview show a test result; the app always starts with none.
    init(
        promptFocus: Binding<Operation?>, client: ModelClient = ModelClient(),
        readKey: @escaping (String) -> String? = { SettingsStore.apiKey(account: $0) },
        check: Check = .idle
    ) {
        _promptFocus = promptFocus
        self.client = client
        self.readKey = readKey
        _check = State(initialValue: check)
    }

    /// The Test button's last run: the model's reply and how long it took, or why it failed.
    enum Check: Equatable {
        case idle, running
        case passed(reply: String, seconds: Double)
        /// No time when nothing was sent, because the settings are incomplete.
        case failed(String, seconds: Double?)
    }

    /// The first line of the Classic of Poetry's 蒹葭, the same text the website shows: short, and in a
    /// language few targets share, so a reply proves the model really translated.
    static let testSentence = "蒹葭蒼蒼，白露為霜。"

    /// What the last lookup found. A failure leaves the saved path alone: a path the user picked by
    /// hand is better than nothing just because the lookup could not run.
    enum Agent: Equatable {
        case idle, checking
        case found(version: String)
        case failed(String)
    }

    /// The chosen service, resolved from what is persisted. An unknown id falls back to OpenAI Compatible rather
    /// than leaving the pane without a selection.
    private var choice: ServiceChoice { ServiceChoice.choice(id: serviceID) ?? .preset(.custom) }
    private var provider: Provider { choice.provider }
    private var preset: ServicePreset? { choice.preset }

    var body: some View {
        Form {
            Section {
                Picker(L10n.shared.string("Provider"), selection: serviceSelection) {
                    // Three sections: protocols, then named vendors, then local agents. An empty group is
                    // left out rather than showing a separator with nothing under it.
                    Section {
                        ForEach(ServicePreset.protocols) { presetRow($0) }
                    }
                    Section {
                        ForEach(ServicePreset.vendors) { presetRow($0) }
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
                        prompt: Text(verbatim: "https://api.openai.com/v1")
                    )
                    .focused($editingBaseURL)
                    .onSubmit(loadModels)
                    .onChange(of: editingBaseURL) { _, editing in
                        if !editing { loadModels() }
                    }
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
                effortField
                effortSupport
                testRows
                modelError
            }
            PromptSettingsView(promptFocus: $promptFocus)
        }
        .formStyle(.grouped)
        .onAppear {
            // The store resolves a value written before presets existed into today's service id, so an
            // older install opens on the same service, key and capability it had.
            serviceID = SettingsStore.serviceID()
            apiKey = currentAPIKey
            agentExecutable = SettingsStore.agentPath(for: provider) ?? ""
            loadModels()
        }
        // The scan is async, so it is a task rather than part of `onAppear`; it runs once per opening.
        .task { await scanAgents() }
        // Leaving the pane or closing the window also ends the edit, so a key typed and left alone
        // is not lost.
        .onDisappear(perform: commitKey)
    }

    /// Choosing a service is not one persisted value: a vendor preset also writes its address, and the
    /// model name is carried over from the service being left. So the picker writes through a setter
    /// that runs the whole switch rather than binding straight to defaults.
    private var serviceSelection: Binding<String> {
        Binding(get: { serviceID }, set: { select($0) })
    }

    /// One service switch: the outgoing service keeps the model name typed for it, then the new one
    /// brings its own address, key, executable and remembered model.
    private func select(_ id: String) {
        guard id != serviceID, let chosen = ServiceChoice.choice(id: id) else { return }
        model = SettingsStore.selectService(id, currentModel: model)
        serviceID = id
        // The store restored this service's own address, or its preset's.
        baseURL = UserDefaults.standard.string(forKey: SettingsStore.baseURLKey) ?? baseURL
        apiKey = currentAPIKey
        check = .idle
        // The outgoing service's list is not this one's, and neither is its failure.
        offered = []
        listFailure = nil
        agentExecutable = chosen.isLocalAgent ? (SettingsStore.agentPath(for: chosen.provider) ?? "") : ""
        agent = .idle
        // Choosing an agent looks for it right away, so the row is filled in without pressing anything.
        if chosen.isLocalAgent { Task { await look(adopt: false) } }
        loadModels()
    }

    /// The key for the service now selected; a local agent has none.
    private var currentAPIKey: String {
        guard let account = choice.keychainAccount else { return "" }
        return readKey(account) ?? ""
    }

    private func presetRow(_ preset: ServicePreset) -> some View {
        Text(verbatim: L10n.shared.string(preset.title)).tag(preset.id)
    }

    private func providerRow(_ option: Provider) -> some View {
        Text(verbatim: Self.providerTitle(option, installed: installed, scanned: scanned))
            .tag(option.rawValue)
    }

    /// What a provider's row reads. A local agent the scan could not find is marked rather than hidden:
    /// the user can only point the app at a CLI by hand if the agent is still in the list
    /// (BDR-0013 §10).
    static func providerTitle(_ option: Provider, installed: Set<Provider>, scanned: Bool) -> String {
        let title = L10n.shared.string(option.title.key)
        guard option.isLocalAgent, scanned, !installed.contains(option) else { return title }
        return L10n.shared.string("%@ (not detected)", title)
    }

    /// The local agents the list offers: every one of them, always. A machine whose shell configuration
    /// the app cannot guess must still be able to point it at a CLI by hand, so a not-detected agent is
    /// marked and selectable, never hidden (BDR-0013 §10).
    static func offeredAgents() -> [Provider] { ServiceChoice.agents }

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

    /// The manual Detect: look the agent up and take what it found.
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

    /// The field takes any name, and the menu beside it lists what the service offers, so a name the
    /// list does not carry is still usable. Empty means the agent's own default for a local agent.
    private var modelField: some View {
        LabeledContent(L10n.shared.string("Model Name")) {
            HStack(spacing: 8) {
                TextField(L10n.shared.string("Model Name"), text: $model, prompt: Text(modelPrompt))
                    .labelsHidden()
                presetMenu(listedModels) { model = $0 }
            }
        }
    }

    /// The preset values one row offers, behind a plain button so the field itself stays free-form.
    private func presetMenu(_ values: [String], choose: @escaping (String) -> Void) -> some View {
        Menu(L10n.shared.string("Presets")) {
            ForEach(values, id: \.self) { value in
                Button(value) { choose(value) }
            }
        }
        .disabled(values.isEmpty)
        .fixedSize()
    }

    private var listedModels: [String] { offered.map(\.id) }

    private var modelPrompt: String {
        provider.isLocalAgent
            ? L10n.shared.string("Leave empty to use the agent's own default model")
            : L10n.shared.string("Enter the model name the provider gives you")
    }

    /// The effort row takes a raw value by name or any other value typed in, which is sent verbatim.
    /// The field holds the value itself rather than its title, so what is shown is what is sent.
    private var effortField: some View {
        LabeledContent(L10n.shared.string("Reasoning Effort")) {
            HStack(spacing: 8) {
                TextField(
                    L10n.shared.string("Reasoning Effort"),
                    text: Binding(
                        get: { effort },
                        set: { effort = Self.storedEffort(typed: $0) })
                )
                .labelsHidden()
                presetMenu(EffortLevel.allCases.map(\.rawValue)) { effort = $0 }
            }
        }
    }

    /// A raw value names its level however it is capitalized; empty is Automatic; anything else is kept
    /// as typed, for a level a newer model adds (`xhigh`, say).
    static func storedEffort(typed: String) -> String {
        let text = typed.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return EffortLevel.automatic.rawValue }
        return EffortLevel.allCases.first { $0.rawValue.caseInsensitiveCompare(text) == .orderedSame }
            .map(\.rawValue) ?? text
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

    /// The button carries the state — running, passed or failed, with the time it took — and a passed
    /// reply gets a line of its own below, where a long one has room.
    @ViewBuilder private var testRows: some View {
        Button(action: test) {
            Label {
                Text(verbatim: testTitle)
            } icon: {
                switch check {
                case .idle: Image(systemName: "bolt.horizontal")
                case .running: ProgressView().controlSize(.small)
                case .passed: Image(systemName: "checkmark.circle")
                case .failed: Image(systemName: "exclamationmark.triangle").foregroundStyle(.red)
                }
            }
        }
        .disabled(check == .running)
        if case .passed(let reply, _) = check {
            Text(verbatim: reply).foregroundStyle(.secondary).textSelection(.enabled)
        }
    }

    /// Every model failure shows here and nowhere else: reading the list and pressing Test fail for the
    /// same reasons, so one message serves both instead of the same text appearing twice. The failure
    /// sits under the controls rather than replacing them, so a bad key never changes what a row is.
    @ViewBuilder private var modelError: some View {
        if case .failed(let message, _) = check {
            errorRow(message, retry: test)
        } else if let message = listFailure {
            errorRow(message, retry: loadModels)
        }
    }

    private func errorRow(_ message: String, retry: @escaping () -> Void) -> some View {
        // As everywhere else: a red message and a plain retry, which repeats what just failed.
        HStack(spacing: 8) {
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
            Spacer(minLength: 0)
            Button(L10n.shared.string("Retry"), systemImage: "arrow.clockwise", action: retry)
                .buttonStyle(.plain)
        }
        .textSelection(.enabled)
    }

    /// "Test", with the time the last run took once there is one.
    private var testTitle: String {
        let title = L10n.shared.string("Test")
        switch check {
        case .passed(_, let seconds), .failed(_, .some(let seconds)):
            return L10n.shared.string("%@ · %@", title, Self.duration(seconds))
        case .idle, .running, .failed(_, nil):
            return title
        }
    }

    static func duration(_ seconds: Double) -> String { String(format: "%.2f s", seconds) }

    /// Sends one short translation with exactly what is saved, through the same path a real request
    /// takes, so a pass here means the panel will work too.
    private func test() {
        commitKey()
        guard let config = SettingsStore.currentConfig() else {
            check = .failed(L10n.shared.string("The model service is not configured"), seconds: nil)
            return
        }
        check = .running
        let target = SettingsStore.targetMapping().target(forSource: LanguageTag.key("zh-Hant"))
        Task { check = await Self.runTest(config: config, target: target, client: client) }
    }

    /// The test itself, apart from the button, so the preview and the unit tests run the same request.
    static func runTest(config: ServiceConfig, target: String, client: ModelClient) async -> Check {
        let start = ContinuousClock.now
        func elapsed() -> Double {
            let duration = ContinuousClock.now - start
            return Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        }
        do {
            let reply = try await client.translate(testSentence, to: target, config: config)
            return .passed(reply: reply, seconds: elapsed())
        } catch {
            return .failed((error as? ModelError)?.message ?? error.localizedDescription, seconds: elapsed())
        }
    }

    /// Writes the key on leaving the field, then reads the model list the key unlocks.
    private func commitKey() {
        guard let account = choice.keychainAccount else { return }
        SettingsStore.setAPIKey(apiKey, account: account)
        loadModels()
    }

    /// Reads the list a service can offer: its protocol's model list once an address and a key are
    /// stored, or the list the agent's own source gives once its executable is known. Without one the
    /// field still takes a typed name.
    private func loadModels() {
        if !provider.isLocalAgent {
            guard let url = URL(string: baseURL), url.scheme != nil, let account = choice.keychainAccount,
                let key = readKey(account), !key.isEmpty
            else {
                listFailure = nil
                return
            }
            Task {
                do {
                    offered = try await client.listModels(
                        baseURL: url, apiKey: key, provider: provider
                    ).map {
                        ModelOption(id: $0)
                    }
                    listFailure = nil
                } catch {
                    listFailure = (error as? ModelError)?.message ?? error.localizedDescription
                }
            }
            return
        }
        guard let kind = provider.localAgent else {
            listFailure = nil
            return
        }
        let path = agentExecutable.isEmpty ? SettingsStore.agentPath(for: provider) : agentExecutable
        guard let path, FileManager.default.isExecutableFile(atPath: path) else {
            listFailure = nil
            return
        }
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
                offered = options
                listFailure = nil
            } catch {
                listFailure = (error as? ModelError)?.message ?? error.localizedDescription
            }
        }
    }
}
