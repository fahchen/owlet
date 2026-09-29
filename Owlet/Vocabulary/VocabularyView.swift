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
        HSplitView {
            List(selection: $selection) {
                Text("\(filtered.count) 个表达")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 12, trailing: 0))
                    .selectionDisabled()
                    .listRowSeparator(.hidden)
                ForEach(filtered) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.expression).font(.headline).lineLimit(1)
                        Text(entry.meaning.isEmpty ? "尚无中文释义" : entry.meaning)
                            .foregroundStyle(.secondary).lineLimit(1)
                        Text("\(LanguageDisplay.name(entry.language)) · \(entry.contexts.count) 个语境")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 12)
                    .tag(entry.persistentModelID)
                }
            }
            .listStyle(.inset)
            .contentMargins(.top, 0, for: .scrollContent)
            .frame(minWidth: 200, idealWidth: 280, maxWidth: 380)
            if let entry = selectedEntry {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        Text("\(LanguageDisplay.name(entry.language)) · \(entry.contexts.count) 个语境")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(entry.expression).font(.title).textSelection(.enabled)
                        VStack(alignment: .leading, spacing: 12) {
                            Text("释义").font(.headline)
                            GroupBox {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(entry.meaning.isEmpty ? "尚无中文释义" : entry.meaning)
                                        .textSelection(.enabled)
                                    if entry.meaning.isEmpty {
                                        MeaningAction(entry: entry, collection: collection)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            Text("原句语境").font(.headline)
                            ForEach(entry.contexts) { context in
                                GroupBox {
                                    ContextView(context: context)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minWidth: 260, maxWidth: .infinity, maxHeight: .infinity)
            } else if selection.count > 1 {
                ContentUnavailableView(
                    "已选择 \(selection.count) 个表达", systemImage: "checkmark.circle",
                    description: Text("可使用工具栏删除所选内容。")
                )
                .frame(minWidth: 260, maxWidth: .infinity, maxHeight: .infinity)
            } else if !filtered.isEmpty {
                ContentUnavailableView(
                    "选择一个表达", systemImage: "sidebar.left",
                    description: Text("在左侧列表中选择内容以查看详情。")
                )
                .frame(minWidth: 260, maxWidth: .infinity, maxHeight: .infinity)
            } else {
                emptyState
                    .frame(minWidth: 260, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // Keep the native divider inside the content safe area, below the unified toolbar.
        .padding(.top, 1)
        .navigationTitle("")
        .searchable(text: $search, placement: .toolbar, prompt: "搜索表达或释义")
        .toolbar { toolbar }
        .onChange(of: filtered.map(\.persistentModelID), initial: true) { _, ids in
            selection.formIntersection(ids)
            if selection.isEmpty, let first = ids.first { selection = [first] }
        }
        .confirmationDialog("删除所选 \(selection.count) 个表达？", isPresented: $confirmingDelete, titleVisibility: .visible) {
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

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Menu {
                Picker("筛选语言", selection: $language) {
                    Text("全部语言").tag("")
                    ForEach(VocabularyFilter.languages(in: entries), id: \.self) { tag in
                        Text(LanguageDisplay.name(tag)).tag(tag)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label("筛选语言", systemImage: "line.3.horizontal.decrease")
            }
            .labelStyle(.iconOnly).help("筛选语言")
        }
        ToolbarItemGroup(placement: .principal) {
            Button("上一条", systemImage: "chevron.up") { if let previous { selection = [previous] } }
                .labelStyle(.iconOnly).help("上一条").disabled(previous == nil)
            Button("下一条", systemImage: "chevron.down") { if let next { selection = [next] } }
                .labelStyle(.iconOnly).help("下一条").disabled(next == nil)
        }
        ToolbarSpacer(.fixed, placement: .primaryAction)
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                confirmingDelete = true
            } label: {
                Label("删除", systemImage: "trash")
            }
            .labelStyle(.iconOnly).disabled(selection.isEmpty).help("删除所选内容")
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
            Label(entries.isEmpty ? "生词本为空" : "无匹配结果", systemImage: "book.closed")
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

/// Retry entry shown while an entry has no Chinese meaning yet.
private struct MeaningAction: View {
    let entry: VocabularyEntry
    let collection: CollectionAction

    var body: some View {
        switch collection.status {
        case .filling(let filling) where filling == entry:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("补充中").foregroundStyle(.secondary)
            }
        case .meaningFailed(let failed, let message) where failed == entry:
            HStack(spacing: 10) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Button("重试") { collection.fillMeaning(for: entry) }.buttonStyle(.glass)
            }
        default:
            Button("补充中文释义") { collection.fillMeaning(for: entry) }.buttonStyle(.glass)
        }
    }
}

private struct ContextView: View {
    let context: VocabularyContext

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(context.source)
                .font(.system(size: 14))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let before = context.polishBefore, let after = context.polishAfter {
                comparison(title: "润色前", text: before)
                comparison(title: "润色后", text: after)
            }
        }
    }

    private func comparison(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(text).font(.system(size: 13)).textSelection(.enabled)
        }
        .padding(.horizontal, 14)
    }
}

/// In-place result of a collect action, shown next to the result so the user is not pulled away.
struct CollectionFeedback: View {
    let collection: CollectionAction
    let openNotebook: (() -> Void)?

    var body: some View {
        switch collection.status {
        case .saved:
            Label("已加入生词本", systemImage: "checkmark")
            if let openNotebook {
                Button("查看", action: openNotebook).buttonStyle(.glass)
            }
        case .filling:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("补充中文释义中")
            }
        case .meaningFailed(let entry, let message):
            Label("释义补充失败：\(message)", systemImage: "exclamationmark.triangle")
            Button("重试") { collection.fillMeaning(for: entry) }.buttonStyle(.glass)
        case .saveFailed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
        case .idle:
            EmptyView()
        }
    }
}

/// Language chip and header text for the notebook; unknown tags fall back to the raw BCP 47 value.
enum LanguageDisplay {
    static func code(_ tag: String) -> String {
        let primary =
            tag.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init) ?? tag
        return primary.uppercased()
    }

    static func name(_ tag: String) -> String {
        switch code(tag) {
        case "EN": "英语"
        case "JA": "日语"
        case "ZH": "中文"
        case "KO": "韩语"
        case "FR": "法语"
        case "DE": "德语"
        case "ES": "西班牙语"
        default: tag
        }
    }
}
