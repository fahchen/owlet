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
                    Button("删除", systemImage: "trash") { remove(tag) }
                        .labelStyle(.iconOnly)
                        .disabled(languages.count <= 1)
                        .accessibilityLabel("移除\(LanguageCatalog.name(for: tag))")
                }
            }
            Picker("添加语言", selection: $pending) {
                Text("选择要添加的语言").tag("")
                ForEach(available) { Text($0.name).tag($0.tag) }
            }
            .onChange(of: pending) { _, tag in
                guard !tag.isEmpty else { return }
                append(tag)
                pending = ""
            }
        } header: {
            Text("语言")
        } footer: {
            Text("只有这里选中的语言会出现在目标语言、兜底目标和映射表里；至少保留一种。")
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
