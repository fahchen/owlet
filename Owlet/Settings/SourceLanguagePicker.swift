import SwiftUI

/// The source-language control on the input side: 自动 follows what the text looks like, and an
/// explicit choice is what the mapping is looked up with — the request itself still lets the model
/// read the language, so this only decides which target the mapping picks.
struct SourceLanguagePicker: View {
    /// The text the 自动 label resolves from.
    let text: String
    @Binding var pinnedSource: String

    var body: some View {
        Picker("源语言", selection: $pinnedSource) {
            Text(autoTitle).tag("")
            ForEach(LanguageCatalog.options(for: SettingsStore.languages())) {
                Text($0.name).tag($0.tag)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
    }

    private var autoTitle: String {
        guard let source = SettingsStore.autoSource(for: text) else { return "自动（未识别）" }
        return "自动（\(LanguageCatalog.name(for: source))）"
    }
}
