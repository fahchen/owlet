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
            ModelSettingsPane.providerTitle(.deepSeek, installed: [], scanned: true)
                == L10n.shared.string(Provider.deepSeek.title.key))
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

    /// What each provider's model name starts as the first time it is chosen: its preset model for an
    /// HTTP service, and empty for anything that picks its own — the picker's first row.
    @Test func everyProviderNamesItsDefaultModel() {
        #expect(Provider.openAICompatible.defaultModel.isEmpty)
        #expect(Provider.deepSeek.defaultModel == "deepseek-chat")
        #expect(Provider.claudeCode.defaultModel.isEmpty)
        #expect(Provider.codexCLI.defaultModel.isEmpty)
    }

    /// One slot per provider, and an empty string is a value like any other, so an agent's "own
    /// default" survives a round trip instead of reading back as never chosen.
    @Test func aRememberedModelRoundTripsPerProvider() {
        SettingsStore.setModel("sonnet", for: .claudeCode, in: defaults)
        #expect(SettingsStore.model(for: .claudeCode, in: defaults) == "sonnet")
        #expect(SettingsStore.model(for: .codexCLI, in: defaults) == nil)

        SettingsStore.setModel("", for: .codexCLI, in: defaults)
        #expect(SettingsStore.model(for: .codexCLI, in: defaults) == "")

        SettingsStore.setModel(nil, for: .claudeCode, in: defaults)
        #expect(SettingsStore.model(for: .claudeCode, in: defaults) == nil)
        // Clearing one provider must not touch the other's name.
        #expect(SettingsStore.model(for: .codexCLI, in: defaults) == "")
    }

    /// A switch files the text under the provider it was typed for — `old`, not the provider now
    /// selected — so switching back restores it instead of losing it to the new provider's slot.
    @Test func switchingProvidersRemembersAndRestoresTheModelName() {
        let toDeepSeek = ModelSettingsPane.switchedModel(
            from: .openAICompatible, to: .deepSeek, current: "gpt-6-sol", in: defaults)
        #expect(toDeepSeek == "deepseek-chat")
        #expect(SettingsStore.model(for: .openAICompatible, in: defaults) == "gpt-6-sol")
        #expect(SettingsStore.model(for: .deepSeek, in: defaults) == nil)

        // A name typed for DeepSeek is not stored under the provider now selected.
        let toAgent = ModelSettingsPane.switchedModel(
            from: .deepSeek, to: .claudeCode, current: "deepseek-chat", in: defaults)
        #expect(toAgent.isEmpty)
        #expect(SettingsStore.model(for: .deepSeek, in: defaults) == "deepseek-chat")
        #expect(SettingsStore.model(for: .claudeCode, in: defaults) == nil)

        // Switching back restores the name rather than falling back to the default.
        let back = ModelSettingsPane.switchedModel(
            from: .claudeCode, to: .openAICompatible, current: "", in: defaults)
        #expect(back == "gpt-6-sol")
    }
}
