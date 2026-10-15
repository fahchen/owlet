import SwiftUI

/// The source-language control on the input side: Automatic follows what the text looks like, and an
/// explicit choice is what the mapping is looked up with — the request itself still lets the model
/// read the language, so this only decides which target the mapping picks.
struct SourceLanguagePicker: View {
    /// The text the Automatic label resolves from.
    let text: String
    @Binding var pinnedSource: String

    var body: some View {
        Picker(L10n.shared.string("Source Language"), selection: $pinnedSource) {
            Text(autoTitle).tag("")
            ForEach(LanguageCatalog.options(for: SettingsStore.languages())) {
                Text($0.name).tag($0.tag)
            }
        }
        .labelsHidden()
        .fixedSize()
    }

    /// The chosen language's name, for a control that shows only the current choice.
    var title: String {
        pinnedSource.isEmpty ? autoTitle : LanguageCatalog.name(for: pinnedSource)
    }

    private var autoTitle: String {
        guard let source = SettingsStore.autoSource(for: text) else {
            return L10n.shared.string("Automatic (not detected)")
        }
        return L10n.shared.string("Automatic (%@)", LanguageCatalog.name(for: source))
    }
}
