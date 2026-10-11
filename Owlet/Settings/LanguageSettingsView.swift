import SwiftUI

/// 语言 group of the settings form: the subset every other language control offers. The system list
/// is hundreds of languages long, so it is only seen here, while adding one; the rest of the app
/// stays on what was picked.
struct LanguageSettingsView: View {
    @Binding var languages: [String]
    /// The language chosen in the add control. Cleared right after it is appended, so the control
    /// stays an action instead of holding a selection.
    @State private var pending = ""

    var body: some View {
        Section {
            ForEach(languages, id: \.self) { tag in
                LabeledContent(LanguageCatalog.name(for: tag)) {
                    Button("Delete", systemImage: "trash") { remove(tag) }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .disabled(languages.count <= 1)
                        .accessibilityLabel("Remove \(LanguageCatalog.name(for: tag))")
                }
            }
            Picker("Add Language", selection: $pending) {
                Text("Choose a language to add").tag("")
                ForEach(available) { Text($0.name).tag($0.tag) }
            }
            .onChange(of: pending) { _, tag in
                guard !tag.isEmpty else { return }
                append(tag)
                pending = ""
            }
        } header: {
            Text("Languages")
        } footer: {
            Text(
                "Only the languages chosen here appear in the target, the fallback and the mapping; keep at least one.")
        }
        .onAppear { languages = SettingsStore.languages() }
    }

    private var available: [LanguageOption] {
        LanguageCatalog.targets.filter { !languages.contains($0.tag) }
    }

    /// The store is written before the binding, so the rest of the page re-reads an already
    /// reconciled mapping instead of racing the cleanup.
    private func append(_ tag: String) {
        var next = languages
        next.append(tag)
        SettingsStore.setLanguages(next)
        languages = next
    }

    private func remove(_ tag: String) {
        guard languages.count > 1 else { return }
        var next = languages
        next.removeAll { $0 == tag }
        SettingsStore.setLanguages(next)
        languages = next
    }
}
