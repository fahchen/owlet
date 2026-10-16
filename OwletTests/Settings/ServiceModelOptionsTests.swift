import Foundation
import Testing

@testable import Owlet

/// The service rows: the effort field's value, the preset table, and what switching services writes.
@MainActor
struct ServiceModelOptionsTests {
    /// The field stores the raw value, whatever its capitalization, so what it shows is what is sent; an
    /// empty field is Automatic, and a value no level uses is kept as typed.
    @Test func theEffortFieldKeepsItsRawValues() {
        #expect(ModelSettingsPane.storedEffort(typed: "LOW") == "low")
        // Clearing the field and never touching it are the same choice.
        #expect(ModelSettingsPane.storedEffort(typed: "  ") == "automatic")
        #expect(ModelSettingsPane.storedEffort(typed: "xhigh") == "xhigh")
        // A level's title is not a value: it is not translated into one.
        #expect(ModelSettingsPane.storedEffort(typed: "Highest") == "Highest")
    }

    /// The Test button runs a real translation of the 蒹葭 line: a valid reply passes with its text,
    /// an HTTP failure reports the same message a real request would, and both carry the elapsed time.
    @Test func theTestRunsTheRealTranslationPath() async throws {
        let segments = try JSONSerialization.data(withJSONObject: [
            "source_language": "zh-Hant", "target_language": "en",
            "segments": [["source": ModelSettingsPane.testSentence, "target": "Reeds grow lush."]],
        ])
        let passed = await ModelSettingsPane.runTest(
            config: testConfig, target: "en",
            client: ModelClient(transport: stub(body: chatBody(String(decoding: segments, as: UTF8.self)))))
        guard case .passed(let reply, let seconds) = passed else { Issue.record("\(passed)"); return }
        #expect(reply == "Reeds grow lush.")
        #expect(seconds >= 0)

        let failed = await ModelSettingsPane.runTest(
            config: testConfig, target: "en", client: ModelClient(transport: stub(status: 401, body: "")))
        guard case .failed(let message, let elapsed) = failed else { Issue.record("\(failed)"); return }
        #expect(message == ModelError.unauthorized.message)
        #expect(elapsed != nil)
    }

    let suite = "ServiceModelOptionsTests.\(UUID().uuidString)"
    var defaults: UserDefaults { UserDefaults(suiteName: suite)! }

    /// A local agent the scan cannot find is marked, never hidden: the file chooser is the only way back
    /// for a machine whose shell configuration the app cannot guess, and the user can only choose what
    /// the list still shows (BDR-0013 §10). Expected text is the same lookup the app does, so the
    /// assertion does not depend on the run's language.
    @Test func everyLocalAgentIsOfferedEvenWhenItIsNotInstalled() {
        #expect(ModelSettingsPane.offeredAgents() == [.claudeCode, .codexCLI])
        let claude = L10n.shared.string(Provider.claudeCode.title.key)
        #expect(
            ModelSettingsPane.providerTitle(.claudeCode, installed: [], scanned: true)
                == L10n.shared.string("%@ (not detected)", claude))
        // Before the first scan answers, nothing is marked.
        #expect(ModelSettingsPane.providerTitle(.claudeCode, installed: [], scanned: false) == claude)
        #expect(
            ModelSettingsPane.providerTitle(.claudeCode, installed: [.claudeCode], scanned: true)
                == claude)
        // A remote service is never marked, whatever the scan found.
        #expect(
            ModelSettingsPane.providerTitle(.openAICompatible, installed: [], scanned: true)
                == L10n.shared.string(Provider.openAICompatible.title.key))
    }

    /// A path the user picked by hand survives a later scan; only a missing or no-longer-runnable one is
    /// replaced by what the lookup found (BDR-0013 §8).
    @Test func aManuallyChosenPathSurvivesAScan() {
        let runnable = { (_: String) in true }
        #expect(
            !ModelSettingsPane.adoptsFoundPath(
                adopt: false, saved: "/usr/local/bin/claude", isExecutable: runnable))
        #expect(
            ModelSettingsPane.adoptsFoundPath(
                adopt: true, saved: "/usr/local/bin/claude", isExecutable: runnable))
        #expect(
            ModelSettingsPane.adoptsFoundPath(adopt: false, saved: nil, isExecutable: { _ in false }))
        #expect(
            ModelSettingsPane.adoptsFoundPath(
                adopt: false, saved: "/gone/claude", isExecutable: { _ in false }))
    }

    /// The preset table is data, so its invariants are asserted directly: unique ids, a real address
    /// for every entry but OpenAI Compatible, a default model for every vendor (a protocol entry leaves
    /// the model to the user), and a keychain account that matches the id except for the custom entry.
    @Test func thePresetTableIsWellFormed() throws {
        let ids = ServicePreset.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(ServicePreset.all.first == .custom)
        for preset in ServicePreset.all {
            #expect(!preset.title.isEmpty)
            if preset.id == ServicePreset.customID {
                #expect(preset.baseURL == nil)
                #expect(preset.defaultModel.isEmpty)
                #expect(preset.keychainAccount == "default")
            } else {
                let base = try #require(preset.baseURL)
                let url = try #require(URL(string: base))
                #expect(["http", "https"].contains(url.scheme ?? ""))
                #expect(preset.defaultModel.isEmpty == ServicePreset.protocols.contains(preset))
                #expect(preset.keychainAccount == preset.id)
            }
        }
        #expect(ServicePreset.preset(id: ServicePreset.deepSeekID) == .deepSeek)
        #expect(ServicePreset.preset(id: "nope") == nil)
    }

    /// The picker's first group has one entry per HTTP protocol, each on its own protocol; every vendor
    /// speaks one of them (BDR-0016).
    @Test func theProtocolGroupCoversEveryHTTPProtocol() {
        let http = Provider.allCases.filter { !$0.isLocalAgent }
        #expect(ServicePreset.protocols.map(\.provider) == http)
        #expect(ServicePreset.protocols.first == .custom)
        for vendor in ServicePreset.vendors { #expect(http.contains(vendor.provider)) }
        #expect(ServiceChoice.choice(id: "anthropic")?.provider == .anthropic)
        #expect(ServiceChoice.choice(id: "gemini")?.provider == .gemini)
        #expect(ServiceChoice.choice(id: "openAIResponses")?.provider == .openAIResponses)
    }

    /// The vendors the task named, at the addresses their own documentation publishes. A vendor that
    /// could not be confirmed is deliberately absent rather than carrying an invented URL.
    @Test func theNamedVendorsCarryTheirDocumentedAddresses() {
        #expect(ServicePreset.vendors == [.deepSeek, .openRouter, .ollama])
        #expect(ServicePreset.deepSeek.baseURL == "https://api.deepseek.com")
        #expect(ServicePreset.openRouter.baseURL == "https://openrouter.ai/api/v1")
        #expect(ServicePreset.ollama.baseURL == "http://localhost:11434/v1")
    }

    /// Only vendors whose own documentation shows the OpenAI `json_schema` shape claim the capability;
    /// everything else asks for `json_object` and carries the shape in the prompt, which fails safer
    /// than a request a service rejects (BDR-0015 §3).
    @Test func onlyDocumentedVendorsClaimJSONSchema() {
        for entry in ServicePreset.protocols { #expect(entry.supportsJSONSchema) }
        #expect(!ServicePreset.deepSeek.supportsJSONSchema)
        // OpenRouter's structured output is per endpoint, so the safe answer is no.
        #expect(!ServicePreset.openRouter.supportsJSONSchema)
        #expect(!ServicePreset.ollama.supportsJSONSchema)
    }

    /// Choosing a vendor fills in its address and default model, and persists the choice immediately.
    @Test func choosingAPresetWritesItsAddressAndModel() {
        let model = SettingsStore.selectService(
            ServicePreset.openRouter.id, currentModel: "", in: defaults)
        #expect(model == "openrouter/auto")
        #expect(defaults.string(forKey: SettingsStore.baseURLKey) == "https://openrouter.ai/api/v1")
        #expect(defaults.string(forKey: SettingsStore.modelKey) == "openrouter/auto")
        #expect(SettingsStore.serviceID(in: defaults) == ServicePreset.openRouter.id)
        #expect(SettingsStore.choice(in: defaults).provider == .openAICompatible)
        #expect(SettingsStore.choice(in: defaults).preset == .openRouter)
    }

    /// An address the user edited belongs to that service: switching away and back restores it, and a
    /// service never edited gets its preset's address.
    @Test func eachServiceRemembersItsOwnAddress() {
        SettingsStore.selectService(ServicePreset.anthropic.id, currentModel: "", in: defaults)
        defaults.set("https://proxy.example/v1", forKey: SettingsStore.baseURLKey)
        SettingsStore.selectService(ServicePreset.deepSeekID, currentModel: "", in: defaults)
        #expect(defaults.string(forKey: SettingsStore.baseURLKey) == "https://api.deepseek.com")
        SettingsStore.selectService(ServicePreset.anthropic.id, currentModel: "", in: defaults)
        #expect(defaults.string(forKey: SettingsStore.baseURLKey) == "https://proxy.example/v1")
    }

    /// A typed effort is kept apart from the levels, so the request can send it verbatim.
    @Test func aTypedEffortIsReadAsCustom() {
        defaults.set("xhigh", forKey: SettingsStore.effortKey)
        #expect(SettingsStore.customEffort(in: defaults) == "xhigh")
        defaults.set("high", forKey: SettingsStore.effortKey)
        #expect(SettingsStore.customEffort(in: defaults) == nil)
    }

    /// OpenAI Compatible writes no address: whatever the user typed stays, which is the whole point of the entry
    /// the preset list is built on.
    @Test func theCustomEntryLeavesTheAddressAlone() {
        defaults.set("https://my.gateway/v1", forKey: SettingsStore.baseURLKey)
        _ = SettingsStore.selectService(ServicePreset.customID, currentModel: "m", in: defaults)
        #expect(defaults.string(forKey: SettingsStore.baseURLKey) == "https://my.gateway/v1")
        #expect(SettingsStore.serviceID(in: defaults) == ServicePreset.customID)
        #expect(SettingsStore.choice(in: defaults).preset == .custom)
    }

    /// An install that predates presets stored the same choice under `service.provider`, whose values
    /// are all valid service ids; reading it back must yield the same service, keychain account and
    /// model slot, without a migration write.
    @Test func aPrePresetProviderResolvesToTheSameService() {
        defaults.set("deepSeek", forKey: SettingsStore.providerKey)
        #expect(SettingsStore.serviceID(in: defaults) == ServicePreset.deepSeekID)
        #expect(SettingsStore.choice(in: defaults).preset == .deepSeek)
        #expect(SettingsStore.choice(in: defaults).keychainAccount == "deepSeek")
        defaults.set("deepseek-chat", forKey: "service.model.deepSeek")
        #expect(
            SettingsStore.model(forService: ServicePreset.deepSeekID, in: defaults) == "deepseek-chat")

        defaults.set("claudeCode", forKey: SettingsStore.providerKey)
        #expect(SettingsStore.choice(in: defaults).provider == .claudeCode)
    }

    /// A stored service id wins over the pre-preset key, so once a choice is made the old key can never
    /// pull the pane back to a previous service.
    @Test func theStoredChoiceBeatsTheLegacyProviderKey() {
        _ = SettingsStore.selectService(ServicePreset.openRouter.id, currentModel: "", in: defaults)
        defaults.set("claudeCode", forKey: SettingsStore.providerKey)
        #expect(SettingsStore.serviceID(in: defaults) == ServicePreset.openRouter.id)
    }

    /// The model name each service starts as the first time it is chosen: a vendor's default model, and
    /// empty for anything that picks its own — the picker's first row.
    @Test func everyServiceNamesItsDefaultModel() {
        #expect(ServiceChoice.preset(.custom).defaultModel.isEmpty)
        #expect(ServiceChoice.preset(.deepSeek).defaultModel == "deepseek-chat")
        #expect(ServiceChoice.preset(.openRouter).defaultModel == "openrouter/auto")
        #expect(ServiceChoice.agent(.claudeCode).defaultModel.isEmpty)
        #expect(ServiceChoice.agent(.codexCLI).defaultModel.isEmpty)
    }

    /// One slot per service, and the vendors keep the slots an older install wrote under the provider
    /// name each one used to have. An empty string is a value like any other, so an agent's "own
    /// default" survives a round trip instead of reading back as never chosen.
    @Test func aRememberedModelRoundTripsPerService() {
        SettingsStore.setModel("sonnet", forService: Provider.claudeCode.rawValue, in: defaults)
        #expect(SettingsStore.model(forService: "claudeCode", in: defaults) == "sonnet")
        #expect(SettingsStore.model(forService: "codexCLI", in: defaults) == nil)
        #expect(SettingsStore.model(forService: ServicePreset.deepSeekID, in: defaults) == nil)

        SettingsStore.setModel("", forService: "codexCLI", in: defaults)
        #expect(SettingsStore.model(forService: "codexCLI", in: defaults) == "")

        SettingsStore.setModel(nil, forService: "claudeCode", in: defaults)
        #expect(SettingsStore.model(forService: "claudeCode", in: defaults) == nil)
        // Clearing one service must not touch another's name.
        #expect(SettingsStore.model(forService: "codexCLI", in: defaults) == "")
    }

    /// A switch files the text under the service it was typed for — the outgoing one, not the newly
    /// selected — so switching back restores it instead of losing it to the new service's slot.
    @Test func switchingServicesRemembersAndRestoresTheModelName() {
        let toOpenRouter = SettingsStore.selectService(
            ServicePreset.openRouter.id, currentModel: "gpt-6-sol", in: defaults)
        #expect(toOpenRouter == "openrouter/auto")
        #expect(SettingsStore.model(forService: ServicePreset.customID, in: defaults) == "gpt-6-sol")
        #expect(SettingsStore.model(forService: ServicePreset.openRouter.id, in: defaults) == nil)

        // A name typed for OpenRouter is not stored under the service now selected.
        let toAgent = SettingsStore.selectService(
            Provider.claudeCode.rawValue, currentModel: "openrouter/auto", in: defaults)
        #expect(toAgent.isEmpty)
        #expect(SettingsStore.model(forService: ServicePreset.openRouter.id, in: defaults) == "openrouter/auto")
        #expect(SettingsStore.model(forService: "claudeCode", in: defaults) == nil)

        // Switching back restores the name rather than falling back to the default.
        let back = SettingsStore.selectService(
            ServicePreset.customID, currentModel: "", in: defaults)
        #expect(back == "gpt-6-sol")
        // OpenRouter's own default does not follow the user across services.
        #expect(SettingsStore.model(forService: ServicePreset.openRouter.id, in: defaults) == "openrouter/auto")
    }
}
