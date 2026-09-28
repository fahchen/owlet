import SwiftUI

/// 目标语言 group of the settings form (BDR-0003): the fallback target plus one row per source
/// language. The table starts empty, and every edit is saved at once like the other pickers here.
struct TargetMappingSettingsView: View {
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
            Picker("兜底目标", selection: $fallbackTarget) {
                ForEach(LanguageCatalog.targets) { Text($0.name).tag($0.tag) }
            }
            ForEach($rows) { $row in
                mappingRow($row)
            }
            Button("添加映射", action: addRow)
                .disabled(rows.count >= LanguageCatalog.targets.count)
        } header: {
            Text("目标语言")
        } footer: {
            Text("源语言由原文自动识别。未识别出源语言、或源语言没有对应行时使用兜底目标；一个源语言只保留一条映射。")
        }
        .onAppear(perform: load)
        .onChange(of: rows) { _, _ in save() }
        .onChange(of: fallbackTarget) { _, _ in save() }
    }

    /// One row's two pickers and its delete. The source list hides what other rows already map, so
    /// the table cannot end up with two targets for one language.
    private func mappingRow(_ row: Binding<Row>) -> some View {
        HStack(spacing: 10) {
            Picker("源语言", selection: row.source) {
                ForEach(sourceOptions(for: row.wrappedValue)) { Text($0.name).tag($0.tag) }
            }
            .labelsHidden()
            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Picker("目标语言", selection: row.target) {
                ForEach(LanguageCatalog.targets) { Text($0.name).tag($0.tag) }
            }
            .labelsHidden()
            Spacer(minLength: 12)
            Button("删除", systemImage: "trash") { remove(row.wrappedValue.id) }
                .labelStyle(.iconOnly)
                .accessibilityLabel("删除\(LanguageCatalog.name(for: row.wrappedValue.source))的映射")
        }
    }

    private func sourceOptions(for row: Row) -> [LanguageOption] {
        let used = Set(rows.filter { $0.id != row.id }.map(\.source))
        return LanguageCatalog.targets.filter { !used.contains($0.tag) }
    }

    private func addRow() {
        let used = Set(rows.map(\.source))
        guard let next = LanguageCatalog.targets.first(where: { !used.contains($0.tag) }) else {
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
