import SwiftUI

/// 目标语言 group of the settings form (BDR-0003): the fallback target plus one row per source
/// language. The table starts empty, and every edit is saved at once like the other pickers here.
/// Both columns offer only the languages chosen in the 语言 group.
struct TargetMappingSettingsView: View {
    /// The languages in play, from the 语言 group above.
    let languages: [String]
    @AppStorage(SettingsStore.targetLanguageKey) private var fallbackTarget =
        SettingsStore.defaultTargetLanguage
    @State private var rows: [Row] = []

    /// One mapping row; the `id` keeps a row stable while its two pickers change.
    struct Row: Identifiable, Equatable {
        let id = UUID()
        var source: String
        var target: String
    }

    var body: some View {
        Section {
            Picker("Fallback Target", selection: $fallbackTarget) {
                ForEach(options) { Text($0.name).tag($0.tag) }
            }
            ForEach($rows) { $row in
                mappingRow($row)
            }
            Button("Add Mapping", systemImage: "plus", action: addRow)
                .buttonStyle(.borderless)
                .disabled(rows.count >= options.count)
        } header: {
            Text("Translation Target")
        } footer: {
            Text(
                "The source is detected from the text. The fallback is used when it cannot be detected or has no row; one source keeps one mapping."
            )
        }
        .onAppear(perform: load)
        // A language leaving the selection also leaves the table, so the rows are read again.
        .onChange(of: languages) { _, _ in load() }
        .onChange(of: rows) { _, _ in save() }
        .onChange(of: fallbackTarget) { _, _ in save() }
    }

    private var options: [LanguageOption] { LanguageCatalog.options(for: languages) }

    /// One row's two pickers and its delete. The source list hides what other rows already map, so
    /// the table cannot end up with two targets for one language.
    private func mappingRow(_ row: Binding<Row>) -> some View {
        HStack(spacing: 10) {
            Picker("Source Language", selection: row.source) {
                ForEach(sourceOptions(for: row.wrappedValue)) { Text($0.name).tag($0.tag) }
            }
            .labelsHidden()
            // The toolbar's source → target mark.
            Image(systemName: "chevron.forward.2")
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Picker("Target Language", selection: row.target) {
                ForEach(options) { Text($0.name).tag($0.tag) }
            }
            .labelsHidden()
            Spacer(minLength: 12)
            Button("Delete", systemImage: "trash") { remove(row.wrappedValue.id) }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .accessibilityLabel("Remove the mapping for \(LanguageCatalog.name(for: row.wrappedValue.source))")
        }
    }

    private func sourceOptions(for row: Row) -> [LanguageOption] {
        let used = Set(rows.filter { $0.id != row.id }.map(\.source))
        return options.filter { !used.contains($0.tag) }
    }

    private func addRow() {
        let used = Set(rows.map(\.source))
        guard let next = options.first(where: { !used.contains($0.tag) }) else {
            return
        }
        rows.append(Row(source: next.tag, target: fallbackTarget))
    }

    private func remove(_ id: Row.ID) {
        rows.removeAll { $0.id == id }
    }

    /// Reads the saved mapping, listed by language name so the table does not depend on insertion order.
    private func load() {
        rows =
            SettingsStore.targetMapping().targets
            .map { Row(source: $0.key, target: $0.value) }
            .sorted {
                LanguageCatalog.name(for: $0.source)
                    .localizedStandardCompare(LanguageCatalog.name(for: $1.source))
                    == .orderedAscending
            }
    }

    private func save() {
        SettingsStore.setTargetMapping(
            TargetMapping(
                targets: Dictionary(rows.map { ($0.source, $0.target) }, uniquingKeysWith: { _, last in last }),
                fallback: fallbackTarget))
    }
}
