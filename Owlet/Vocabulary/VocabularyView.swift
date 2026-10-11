import SwiftData
import SwiftUI

struct VocabularyView: View {
    let collection: CollectionAction
    let openProcessing: () -> Void
    @Query(sort: \VocabularyEntry.createdAt, order: .reverse) private var entries: [VocabularyEntry]
    @State private var search = ""
    @State private var language = ""
    @State private var selection: Set<PersistentIdentifier> = []
    @State private var errorMessage: String?
    @State private var confirmingDelete = false

    private var filtered: [VocabularyEntry] {
        VocabularyFilter.apply(entries, search: search, language: language.isEmpty ? nil : language)
    }

    private var selectedEntries: [VocabularyEntry] {
        filtered.filter { selection.contains($0.persistentModelID) }
    }

    private var selectedEntry: VocabularyEntry? {
        selectedEntries.count == 1 ? selectedEntries.first : nil
    }

    var body: some View {
        page
            .navigationTitle("生词本")
            .focusedSceneValue(\.copyText, selectedEntry?.expression)
            // The count lives under the title, so the list starts with its first row.
            .navigationSubtitle("\(filtered.count) 个表达")
            .searchable(text: $search, placement: .toolbar, prompt: "搜索表达或释义")
            .toolbar { toolbar }
            .onChange(of: filtered.map(\.persistentModelID), initial: true) { _, ids in
                selection.formIntersection(ids)
                if selection.isEmpty, let first = ids.first { selection = [first] }
            }
            .confirmationDialog(
                "删除所选 \(selection.count) 个表达？", isPresented: $confirmingDelete, titleVisibility: .visible
            ) {
                Button("删除", role: .destructive) { deleteSelected() }
                Button("取消", role: .cancel) {}
            }
            .alert(
                "操作失败",
                isPresented: Binding(
                    get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
            ) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
    }

    /// The list beside the selected expression, or a single empty state when nothing matches.
    @ViewBuilder private var page: some View {
        if filtered.isEmpty {
            emptyState
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            WorkspaceSplit {
                List(selection: $selection) {
                    ForEach(filtered) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.expression)
                                .font(.system(size: PanelMetrics.sourceTextSize, weight: PanelMetrics.textWeight))
                                .lineLimit(1)
                            Text(entry.meaning.isEmpty ? "尚无中文释义" : entry.meaning)
                                .foregroundStyle(.secondary).lineLimit(1)
                            Text("\(LanguageCatalog.name(for: entry.language)) · \(entry.contexts.count) 个语境")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                        .tag(entry.persistentModelID)
                    }
                }
                .workspaceList()
            } detail: { _ in
                if let entry = selectedEntry {
                    VocabularyDetail(entry: entry, collection: collection)
                } else if selection.count > 1 {
                    ContentUnavailableView(
                        "已选择 \(selection.count) 个表达", systemImage: "checkmark.circle",
                        description: Text("可使用工具栏删除所选内容。"))
                } else {
                    ContentUnavailableView(
                        "选择一个表达", systemImage: "sidebar.left",
                        description: Text("在左侧列表中选择内容以查看详情。"))
                }
            }
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Menu {
                Picker("筛选语言", selection: $language) {
                    Text("全部语言").tag("")
                    ForEach(VocabularyFilter.languages(in: entries), id: \.self) { tag in
                        Text(LanguageCatalog.name(for: tag)).tag(tag)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label("筛选语言", systemImage: "line.3.horizontal.decrease")
            }
            .labelStyle(.iconOnly).hoverTip("筛选语言")
        }
        ToolbarItemGroup(placement: .principal) {
            Button("上一条", systemImage: "chevron.up") { if let previous { selection = [previous] } }
                .labelStyle(.iconOnly).keyboardShortcut(KeyHint.previous.shortcut).hoverTip(KeyHint.previous)
                .disabled(previous == nil)
            Button("下一条", systemImage: "chevron.down") { if let next { selection = [next] } }
                .labelStyle(.iconOnly).keyboardShortcut(KeyHint.next.shortcut).hoverTip(KeyHint.next)
                .disabled(next == nil)
        }
        ToolbarSpacer(.fixed, placement: .primaryAction)
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                confirmingDelete = true
            } label: {
                Label("删除", systemImage: "trash")
            }
            .labelStyle(.iconOnly).disabled(selection.isEmpty)
            .keyboardShortcut(KeyHint.delete.shortcut).hoverTip(KeyHint.delete, title: "删除所选内容")
        }
        ToolbarSpacer(.fixed, placement: .primaryAction)
        DefaultToolbarItem(kind: .search, placement: .primaryAction)
    }

    private var previous: PersistentIdentifier? {
        adjacentSelection(in: filtered.map(\.persistentModelID), to: selectedEntry?.persistentModelID, offset: -1)
    }

    private var next: PersistentIdentifier? {
        adjacentSelection(in: filtered.map(\.persistentModelID), to: selectedEntry?.persistentModelID, offset: 1)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(entries.isEmpty ? "生词本为空" : "无匹配结果", systemImage: "books.vertical")
        } description: {
            Text(entries.isEmpty ? "在学习区选择表达，即可加入生词本。" : "试试其他搜索词或筛选条件。")
        } actions: {
            if entries.isEmpty {
                Button("前往翻译", action: openProcessing).buttonStyle(.glass)
            } else {
                Button("清除筛选") {
                    search = ""; language = ""
                }.buttonStyle(.glass)
            }
        }
    }

    private func deleteSelected() {
        guard !selectedEntries.isEmpty else { return }
        do {
            try collection.store.delete(selectedEntries)
            selection = []
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }
}

/// One expression: the expression itself, its meaning reading heavier than the
/// sentences it was collected from, and each sentence below a quiet heading.
private struct VocabularyDetail: View {
    let entry: VocabularyEntry
    let collection: CollectionAction

    /// The meaning is text in its own language (BDR-0005's recorded one, Simplified Chinese for
    /// now), so a word in it is explained the way a source in that language is: through the mapping.
    private var meaningOrigin: LookupOrigin {
        let language = entry.lookupOrigin.definitionLanguage
        return LookupOrigin(
            language: language,
            definitionLanguage: SettingsStore.targetMapping().target(forSource: LanguageTag.key(language)))
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(
                        "\(LanguageCatalog.name(for: entry.language)) · \(entry.contexts.count) 个语境 · 收藏于 \(HistoryTime.display(entry.createdAt))"
                    )
                    .font(.caption).foregroundStyle(.secondary)
                    LookupText(
                        text: entry.expression, size: 22, weight: .semibold, lineSpacing: 0, label: "表达",
                        origin: entry.lookupOrigin)
                    if entry.meaning.isEmpty {
                        MissingMeaningView(entry: entry, collection: collection)
                    } else {
                        LookupText(
                            text: entry.meaning, size: PanelMetrics.textSize, weight: .medium, label: "释义",
                            origin: meaningOrigin)
                    }
                    Divider().padding(.vertical, 4)
                    Text("原句语境").font(.caption).foregroundStyle(.secondary)
                    ForEach(entry.contexts) { context in
                        VocabularyContextView(context: context, origin: entry.lookupOrigin)
                            .padding(.bottom, 8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // A reading column: long lines stop at 640pt instead of running across a wide window.
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, PanelMetrics.contentInset)
                .padding(.horizontal, 32)
                .panelBottomPadding()
            }
            .scrollBounceBehavior(.basedOnSize)
            CardButton(title: "复制表达", symbol: "document.on.document", key: .copy, bindsKey: false) {
                Clipboard.copy(entry.expression)
            }
            .padding([.trailing, .bottom], PanelMetrics.contentInset)
        }
    }
}
