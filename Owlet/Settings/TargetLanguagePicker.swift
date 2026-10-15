import SwiftUI

/// The target-language control shared by the window toolbar, the floating panel and the Text
/// menu: Automatic resolves from the mapping for the current text, and an explicit choice pins that
/// language until the user returns to Automatic. All three read the same stored value, so they stay in step.
struct TargetLanguagePicker: View {
    /// The text the Automatic label resolves from.
    let text: String
    @Binding var pinnedTarget: String

    var body: some View {
        Picker(L10n.shared.string("Target Language"), selection: $pinnedTarget) {
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
        pinnedTarget.isEmpty ? autoTitle : LanguageCatalog.name(for: pinnedTarget)
    }

    private var autoTitle: String {
        L10n.shared.string(
            "Automatic (%@)", LanguageCatalog.name(for: SettingsStore.autoTarget(for: text)))
    }
}
