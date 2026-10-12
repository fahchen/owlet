import SwiftUI

/// The 语言 page's two language settings: where a translation goes (BDR-0003 — the fallback target plus
/// one row per source language), and which languages learning should leave alone (BDR-0012). The table
/// starts empty, and every edit is saved at once like the other pickers here. Both sections offer only
/// the languages chosen in the 语言 group.
struct TargetMappingSettingsView: View {
    /// The languages in play, from the 语言 group above.
    let languages: [String]
    @AppStorage(SettingsStore.targetLanguageKey) private var fallbackTarget =
        SettingsStore.defaultTargetLanguage
    /// The languages the reader already speaks; empty means 未指定, which leaves learning exactly as it
    /// was before the setting existed. Held as state with the mapping rows, so one `load`/`save` pair
    /// owns this page's settings.
    @State private var nativeLanguages: [String] = []
    @State private var rows: [Row] = []

    /// One mapping row; the `id` keeps a row stable while its two pickers change.
    struct Row: Identifiable, Equatable {
        let id = UUID()
        var source: String
        var target: String
    }

    var body: some View {
        Section {
            Picker(L10n.shared.string("Fallback Target"), selection: $fallbackTarget) {
                ForEach(options) { Text($0.name).tag($0.tag) }
            }
            ForEach($rows) { $row in
                mappingRow($row)
            }
            Button(L10n.shared.string("Add Mapping"), systemImage: "plus", action: addRow)
                .buttonStyle(.borderless)
                .disabled(rows.count >= options.count)
        } header: {
            Text(L10n.shared.string("Translation Target"))
        } footer: {
            Text(
                L10n.shared.string(
                    "The source is detected from the text. The fallback is used when it cannot be detected or has no row; one source keeps one mapping."
                ))
        }
        // Its own section: 母语 decides what learning may recommend, which is a different concern from
        // where a translation goes — it only happens to be chosen from the same set of languages. The
        // info glyph carries the explanation, since a footer here would read as part of the mapping.
        Section {
            LabeledContent {
                // A menu of toggles, not a picker: more than one language can be a reader's own, and a
                // picker holds one value (BDR-0012).
                Menu {
                    ForEach(options) { option in
                        Toggle(option.name, isOn: nativeBinding(option.tag))
                    }
                } label: {
                    Text(nativeSummary)
                }
            } label: {
                HStack(spacing: 4) {
                    Text(L10n.shared.string("Native Languages"))
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(nativeExplanation)
                        .hoverTip(nativeExplanation)
                }
            }
        }
        .onAppear(perform: load)
        // A language leaving the selection also leaves the table, so the rows are read again.
        .onChange(of: languages) { _, _ in load() }
        .onChange(of: rows) { _, _ in save() }
        .onChange(of: nativeLanguages) { _, _ in SettingsStore.setNativeLanguages(nativeLanguages) }
        .onChange(of: fallbackTarget) { _, _ in save() }
    }

    private var options: [LanguageOption] { LanguageCatalog.options(for: languages) }

    /// One row's two pickers and its delete. The source list hides what other rows already map, so
    /// the table cannot end up with two targets for one language.
    private func mappingRow(_ row: Binding<Row>) -> some View {
        HStack(spacing: 10) {
            Picker(L10n.shared.string("Source Language"), selection: row.source) {
                ForEach(sourceOptions(for: row.wrappedValue)) { Text($0.name).tag($0.tag) }
            }
            .labelsHidden()
            // The toolbar's source → target mark.
            Image(systemName: "chevron.forward.2")
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Picker(L10n.shared.string("Target Language"), selection: row.target) {
                ForEach(options) { Text($0.name).tag($0.tag) }
            }
            .labelsHidden()
            Spacer(minLength: 12)
            Button(L10n.shared.string("Delete"), systemImage: "trash") { remove(row.wrappedValue.id) }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .accessibilityLabel(
                    L10n.shared.string("Remove the mapping for %@", LanguageCatalog.name(for: row.wrappedValue.source)))
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
    /// What the setting does, and what it deliberately does not do, in one place: it is both the
    /// hover tip and the accessibility label of the info glyph.
    private var nativeExplanation: String {
        L10n.shared.string(
            "Learning content skips the languages you already speak; it does not change the language explanations are written in."
        )
    }

    /// The chosen languages as names, or 未指定 when none is chosen.
    private var nativeSummary: String {
        let chosen = options.filter { nativeLanguages.contains($0.tag) }
        return chosen.isEmpty
            ? L10n.shared.string("Not Specified")
            : chosen.map(\.name).joined(separator: "、")
    }

    private func nativeBinding(_ tag: String) -> Binding<Bool> {
        Binding(
            get: { nativeLanguages.contains(tag) },
            set: { isOn in
                if isOn {
                    guard !nativeLanguages.contains(tag) else { return }
                    nativeLanguages.append(tag)
                } else {
                    nativeLanguages.removeAll { $0 == tag }
                }
            })
    }

    private func load() {
        // A language leaving the 语言 selection leaves this list too, like the mapping rows.
        nativeLanguages = SettingsStore.nativeLanguages().filter { tag in
            options.contains { $0.tag == tag }
        }
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
