import SwiftData
import SwiftUI

struct HistoryView: View {
    let store: HistoryStore
    let collection: CollectionAction
    let openProcessing: () -> Void
    @Query(sort: \HistoryRecord.createdAt, order: .reverse) private var records: [HistoryRecord]
    @State private var search = ""
    @State private var operationFilter: Operation?
    @State private var selection: Set<PersistentIdentifier> = []
    @State private var actionError: String?
    @State private var confirmingDelete = false
    @State private var learning = LearningModel()
    @State private var learningReveal = 0

    private var filtered: [HistoryRecord] {
        HistoryFilter.apply(records, search: search, operation: operationFilter)
    }

    private var selectedRecords: [HistoryRecord] {
        filtered.filter { selection.contains($0.persistentModelID) }
    }

    private var selectedRecord: HistoryRecord? {
        selectedRecords.count == 1 ? selectedRecords.first : nil
    }

    var body: some View {
        HSplitView {
            List(selection: $selection) {
                Text("\(filtered.count) 条记录")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 12, trailing: 0))
                    .selectionDisabled()
                    .listRowSeparator(.hidden)
                ForEach(filtered) { record in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(record.operationKind.title) · \(HistoryTime.display(record.createdAt))")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(record.source).font(.headline).lineLimit(1)
                        Text(record.result).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .padding(.vertical, 12)
                    .tag(record.persistentModelID)
                }
            }
            .listStyle(.inset)
            .contentMargins(.top, 0, for: .scrollContent)
            .frame(minWidth: 200, idealWidth: 280, maxWidth: 380)
            if let record = selectedRecord {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            Text(
                                "\(record.operationKind.title) · \(LanguageDisplay.name(record.language)) · \(HistoryTime.display(record.createdAt))"
                            )
                            .font(.caption).foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 12) {
                                Text("原文").font(.headline)
                                GroupBox {
                                    Text(record.source).textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            VStack(alignment: .leading, spacing: 12) {
                                Text(record.operationKind == .translate ? "译文" : "润色结果").font(.headline)
                                GroupBox {
                                    Text(record.result).textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            GroupBox {
                                LearningView(
                                    learning: learning, request: learningRequest(record),
                                    collection: collection, openNotebook: nil
                                )
                                .id(record.persistentModelID)
                            }
                            .id("learning")
                        }
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .onChange(of: learningReveal) { _, _ in
                        proxy.scrollTo("learning", anchor: .top)
                    }
                }
                .frame(minWidth: 260, maxWidth: .infinity, maxHeight: .infinity)
            } else if selection.count > 1 {
                ContentUnavailableView(
                    "已选择 \(selection.count) 条历史记录", systemImage: "checkmark.circle",
                    description: Text("可使用工具栏删除所选内容。")
                )
                .frame(minWidth: 260, maxWidth: .infinity, maxHeight: .infinity)
            } else if !filtered.isEmpty {
                ContentUnavailableView(
                    "选择一个记录", systemImage: "sidebar.left",
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
        .searchable(text: $search, placement: .toolbar, prompt: "搜索原文或结果")
        .toolbar { toolbar }
        .safeAreaInset(edge: .top) {
            if let message = store.lastError {
                HStack {
                    Label("历史保存失败：\(message)", systemImage: "exclamationmark.triangle")
                    Spacer()
                    Button("关闭", systemImage: "xmark") { store.dismissError() }
                        .labelStyle(.iconOnly).help("关闭提示")
                }.padding()
            }
        }
        .onChange(of: filtered.map(\.persistentModelID), initial: true) { _, ids in
            selection.formIntersection(ids)
            if selection.isEmpty, let first = ids.first { selection = [first] }
        }
        .onChange(of: selection) { _, _ in learning.reset() }
        .onDisappear { learning.reset() }
        .confirmationDialog("删除所选 \(selection.count) 条历史记录？", isPresented: $confirmingDelete, titleVisibility: .visible)
        {
            Button("删除", role: .destructive) { deleteSelected() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("生词本中的表达不受影响。")
        }
        .alert(
            "操作失败",
            isPresented: Binding(
                get: { actionError != nil }, set: { if !$0 { actionError = nil } })
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Menu {
                Picker("筛选类型", selection: $operationFilter) {
                    Text("全部类型").tag(Operation?.none)
                    ForEach(Operation.allCases, id: \.self) { operation in
                        Text(operation.title).tag(Operation?.some(operation))
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label("筛选类型", systemImage: "line.3.horizontal.decrease")
            }
            .labelStyle(.iconOnly).help("筛选类型")
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
                guard let record = selectedRecord else { return }
                learning.isExpanded = true
                learning.generate(for: learningRequest(record))
                learningReveal += 1
            } label: {
                Label("学习", systemImage: "lightbulb.fill")
            }
            .labelStyle(.iconOnly).disabled(selectedRecord == nil).help("学习词汇与表达")
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

    private func learningRequest(_ record: HistoryRecord) -> LearningRequest {
        LearningRequest(
            text: record.source, operation: record.operationKind, targetLanguage: record.language,
            result: record.result, claimAutoRequest: { false })
    }

    private var previous: PersistentIdentifier? {
        adjacentSelection(in: filtered.map(\.persistentModelID), to: selectedRecord?.persistentModelID, offset: -1)
    }

    private var next: PersistentIdentifier? {
        adjacentSelection(in: filtered.map(\.persistentModelID), to: selectedRecord?.persistentModelID, offset: 1)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(records.isEmpty ? "暂无历史记录" : "无匹配结果", systemImage: "clock")
        } description: {
            Text(records.isEmpty ? "成功的翻译与润色会自动记录在这里。" : "试试其他搜索词或筛选条件。")
        } actions: {
            if records.isEmpty {
                Button("前往翻译", action: openProcessing).buttonStyle(.glass)
            } else {
                Button("清除筛选") {
                    search = ""; operationFilter = nil
                }.buttonStyle(.glass)
            }
        }
    }

    private func deleteSelected() {
        guard !selectedRecords.isEmpty else { return }
        do {
            try store.delete(selectedRecords)
            selection = []
            actionError = nil
        } catch { actionError = error.localizedDescription }
    }
}

/// Short, human dates for the detail header, matching the 今天 HH:mm style of the design.
enum HistoryTime {
    static func display(_ date: Date) -> String {
        let calendar = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDateInToday(date) { return "今天 \(time)" }
        if calendar.isDateInYesterday(date) { return "昨天 \(time)" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
