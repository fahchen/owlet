import Testing

@testable import Owlet

/// The model row keeps one control per provider: the list only changes the picker's options, so a
/// save never turns the model name into something else.
@MainActor
struct ServiceModelOptionsTests {
    @Test func aSavedModelStaysSelectableWhenTheListArrives() {
        #expect(
            ServiceSettingsView.modelOptions(for: .loaded(["a", "b"]), model: "c") == ["c", "a", "b"])
    }

    @Test func theListIsUsedAsItIsWhenItAlreadyOffersTheSavedModel() {
        #expect(ServiceSettingsView.modelOptions(for: .loaded(["a", "b"]), model: "b") == ["a", "b"])
    }

    /// Before the first list arrives the picker still shows the saved name rather than nothing.
    @Test func theSavedModelIsTheOnlyOptionWhileTheListIsLoading() {
        #expect(ServiceSettingsView.modelOptions(for: .loading, model: "a") == ["a"])
        #expect(ServiceSettingsView.modelOptions(for: .idle, model: "a") == ["a"])
        #expect(ServiceSettingsView.modelOptions(for: .failed("x"), model: "a") == ["a"])
    }

    @Test func nothingIsOfferedWhenNoModelIsSaved() {
        #expect(ServiceSettingsView.modelOptions(for: .loading, model: "").isEmpty)
    }
}
