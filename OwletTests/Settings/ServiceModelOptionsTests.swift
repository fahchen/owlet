import Foundation
import Testing

@testable import Owlet

/// The model row keeps one control per provider: the list only changes the picker's options, so a
/// save never turns the model name into something else.
@MainActor
struct ServiceModelOptionsTests {
    /// One picker row per id. A row built from a name alone carries the name as its label and says
    /// nothing about effort, which is what the picker invents for a saved name the list does not have.
    func options(_ ids: [String]) -> [ModelOption] { ids.map { ModelOption(id: $0) } }

    @Test func aSavedModelStaysSelectableWhenTheListArrives() {
        #expect(
            ModelSettingsPane.modelOptions(for: .loaded(options(["a", "b"])), model: "c")
                == options(["c", "a", "b"]))
    }

    @Test func theListIsUsedAsItIsWhenItAlreadyOffersTheSavedModel() {
        #expect(
            ModelSettingsPane.modelOptions(for: .loaded(options(["a", "b"])), model: "b")
                == options(["a", "b"]))
    }

    /// The options the agent reported keep the label and the effort facts it gave them; the picker
    /// shows what the provider said rather than rebuilding each row from its id.
    @Test func aLoadedOptionKeepsItsLabelAndEfforts() {
        let option = ModelOption(id: "gpt-6-sol", label: "GPT-6-Sol", efforts: [])
        #expect(ModelSettingsPane.modelOptions(for: .loaded([option]), model: "gpt-6-sol") == [option])
    }

    /// Before the first list arrives the picker still shows the saved name rather than nothing.
    @Test func theSavedModelIsTheOnlyOptionWhileTheListIsLoading() {
        #expect(ModelSettingsPane.modelOptions(for: .loading, model: "a") == options(["a"]))
        #expect(ModelSettingsPane.modelOptions(for: .idle, model: "a") == options(["a"]))
        #expect(ModelSettingsPane.modelOptions(for: .failed("x"), model: "a") == options(["a"]))
    }

    @Test func nothingIsOfferedWhenNoModelIsSaved() {
        #expect(ModelSettingsPane.modelOptions(for: .loading, model: "").isEmpty)
    }

    /// A name saved before the cache changed is still the one in the field, and the picker still offers
    /// it rather than dropping a configuration that works.
    @Test func aSavedClaudeModelTheCatalogDoesNotOfferStaysSelectable() {
        let listed = [ModelOption(id: "claude-opus-5-5", label: "Opus 5.5", efforts: [.low, .high])]
        #expect(
            ModelSettingsPane.modelOptions(for: .loaded(listed), model: "claude-opus-4-6")
                == [ModelOption(id: "claude-opus-4-6")] + listed)
    }

    /// Only an agent that really has a list gets the picker. A listing command answers on demand, so its
    /// picker stands whatever the load is doing; a cached catalog only gets one once it produced rows,
    /// because an empty picker would read as "this agent has no models" when nothing was readable.
    @Test func onlyAnAgentWithAListGetsThePicker() {
        let command = LocalAgentKind.codexCLI.modelSource
        let cache = LocalAgentKind.claudeCode.modelSource
        let listed = options(["claude-opus-5-5"])

        // No model source at all: an HTTP service, or a provider that only lists through its API.
        #expect(!ModelSettingsPane.listsModels(nil, models: .loaded(listed)))

        #expect(ModelSettingsPane.listsModels(command, models: .idle))
        #expect(ModelSettingsPane.listsModels(command, models: .loading))
        #expect(ModelSettingsPane.listsModels(command, models: .failed("x")))
        #expect(ModelSettingsPane.listsModels(command, models: .loaded([])))

        #expect(!ModelSettingsPane.listsModels(cache, models: .idle))
        #expect(!ModelSettingsPane.listsModels(cache, models: .loading))
        #expect(!ModelSettingsPane.listsModels(cache, models: .failed("x")))
        #expect(!ModelSettingsPane.listsModels(cache, models: .loaded([])))
        #expect(ModelSettingsPane.listsModels(cache, models: .loaded(listed)))
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

    /// The vendor table is data, so its invariants are asserted directly: unique ids, a real address
    /// for every vendor (自定义 is the one entry that asks for one), a default model to fill in, and a
    /// keychain account that matches the id except for the custom entry.
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
                #expect(!preset.defaultModel.isEmpty)
                #expect(preset.keychainAccount == preset.id)
            }
        }
        #expect(ServicePreset.preset(id: ServicePreset.deepSeekID) == .deepSeek)
        #expect(ServicePreset.preset(id: "nope") == nil)
    }

    /// The vendors the task named, at the addresses their own documentation publishes. A vendor that
    /// could not be confirmed is deliberately absent rather than carrying an invented URL.
    @Test func theNamedVendorsCarryTheirDocumentedAddresses() {
        #expect(ServicePreset.deepSeek.baseURL == "https://api.deepseek.com")
        #expect(ServicePreset.moonshot.baseURL == "https://api.moonshot.cn/v1")
        #expect(ServicePreset.zhipu.baseURL == "https://open.bigmodel.cn/api/paas/v4")
        #expect(ServicePreset.qwen.baseURL == "https://dashscope.aliyuncs.com/compatible-mode/v1")
        #expect(ServicePreset.xAI.baseURL == "https://api.x.ai/v1")
        #expect(ServicePreset.openRouter.baseURL == "https://openrouter.ai/api/v1")
        #expect(ServicePreset.ollama.baseURL == "http://localhost:11434/v1")
        #expect(ServicePreset.lmStudio.baseURL == "http://localhost:1234/v1")
    }

    /// Only vendors whose own documentation shows the OpenAI `json_schema` shape claim the capability;
    /// everything else asks for `json_object` and carries the shape in the prompt, which fails safer
    /// than a request a service rejects (BDR-0015 §3).
    @Test func onlyDocumentedVendorsClaimJSONSchema() {
        #expect(ServicePreset.custom.supportsJSONSchema)
        #expect(ServicePreset.moonshot.supportsJSONSchema)
        #expect(ServicePreset.xAI.supportsJSONSchema)
        #expect(!ServicePreset.deepSeek.supportsJSONSchema)
        #expect(!ServicePreset.zhipu.supportsJSONSchema)
        #expect(!ServicePreset.qwen.supportsJSONSchema)
        // OpenRouter's structured output is per endpoint, so the safe answer is no.
        #expect(!ServicePreset.openRouter.supportsJSONSchema)
        #expect(!ServicePreset.ollama.supportsJSONSchema)
        #expect(!ServicePreset.lmStudio.supportsJSONSchema)
    }

    /// DeepSeek keeps the model-list behaviour it had as a provider; no other vendor turns the field
    /// into a picker before its `/models` has been checked.
    @Test func onlyDeepSeekListsModels() {
        #expect(ServicePreset.all.filter(\.listsModels).map(\.id) == [ServicePreset.deepSeekID])
    }

    /// Choosing a vendor fills in its address and default model, and persists the choice immediately.
    @Test func choosingAPresetWritesItsAddressAndModel() {
        let model = SettingsStore.selectService(
            ServicePreset.moonshot.id, currentModel: "", in: defaults)
        #expect(model == "kimi-k3")
        #expect(defaults.string(forKey: SettingsStore.baseURLKey) == "https://api.moonshot.cn/v1")
        #expect(defaults.string(forKey: SettingsStore.modelKey) == "kimi-k3")
        #expect(SettingsStore.serviceID(in: defaults) == ServicePreset.moonshot.id)
        #expect(SettingsStore.choice(in: defaults).provider == .openAICompatible)
        #expect(SettingsStore.choice(in: defaults).preset == .moonshot)
    }

    /// 自定义 writes no address: whatever the user typed stays, which is the whole point of the entry
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
        _ = SettingsStore.selectService(ServicePreset.moonshot.id, currentModel: "", in: defaults)
        defaults.set("claudeCode", forKey: SettingsStore.providerKey)
        #expect(SettingsStore.serviceID(in: defaults) == ServicePreset.moonshot.id)
    }

    /// The model name each service starts as the first time it is chosen: a vendor's default model, and
    /// empty for anything that picks its own — the picker's first row.
    @Test func everyServiceNamesItsDefaultModel() {
        #expect(ServiceChoice.preset(.custom).defaultModel.isEmpty)
        #expect(ServiceChoice.preset(.deepSeek).defaultModel == "deepseek-chat")
        #expect(ServiceChoice.preset(.moonshot).defaultModel == "kimi-k3")
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
        let toMoonshot = SettingsStore.selectService(
            ServicePreset.moonshot.id, currentModel: "gpt-6-sol", in: defaults)
        #expect(toMoonshot == "kimi-k3")
        #expect(SettingsStore.model(forService: ServicePreset.customID, in: defaults) == "gpt-6-sol")
        #expect(SettingsStore.model(forService: ServicePreset.moonshot.id, in: defaults) == nil)

        // A name typed for Moonshot is not stored under the service now selected.
        let toAgent = SettingsStore.selectService(
            Provider.claudeCode.rawValue, currentModel: "kimi-k3", in: defaults)
        #expect(toAgent.isEmpty)
        #expect(SettingsStore.model(forService: ServicePreset.moonshot.id, in: defaults) == "kimi-k3")
        #expect(SettingsStore.model(forService: "claudeCode", in: defaults) == nil)

        // Switching back restores the name rather than falling back to the default.
        let back = SettingsStore.selectService(
            ServicePreset.customID, currentModel: "", in: defaults)
        #expect(back == "gpt-6-sol")
        // Moonshot's own default does not follow the user across services.
        #expect(SettingsStore.model(forService: ServicePreset.moonshot.id, in: defaults) == "kimi-k3")
    }
}
