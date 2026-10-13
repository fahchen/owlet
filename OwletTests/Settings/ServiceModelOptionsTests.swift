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
}
