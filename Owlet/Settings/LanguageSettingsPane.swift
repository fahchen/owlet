import SwiftUI

/// 语言 pane: which languages are in play, and where each detected source language goes. The two
/// sections are one group of settings — the mapping can only use what the selection offers — so they
/// share a pane.
struct LanguageSettingsPane: View {
    /// Owned here so the mapping below re-reads its rows when the selection changes.
    @State private var languages = SettingsStore.languages()

    var body: some View {
        Form {
            LanguageSettingsView(languages: $languages)
            TargetMappingSettingsView(languages: languages)
        }
        .formStyle(.grouped)
        .onAppear { languages = SettingsStore.languages() }
    }
}
