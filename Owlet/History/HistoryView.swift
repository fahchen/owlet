import SwiftData
import SwiftUI

/// Sidebar 历史记录 page: search, type filter and deletion over the finished results.
struct HistoryView: View {
    let store: HistoryStore
    let collection: CollectionAction
    let openProcessing: () -> Void
    @Query(sort: \HistoryRecord.createdAt, order: .reverse) private var records: [HistoryRecord]
    @State private var search = ""
    /// Nil means 全部类型; the picker's tags are optional so the filter can be cleared.
    @State private var operationFilter: Operation?
    @State private var actionError: String?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("历史记录")
                .searchable(text: $search, prompt: "搜索原文或结果")
                .navigationDestination(for: HistoryRecord.self) { record in
                    HistoryDetailView(record: record, collection: collection)
                }
                .toolbar { toolbar }
                .safeAreaInset(edge: .top, spacing: 0) { errorBanner }
                .confirmationDialog(
                    "清空全部历史？",
                    isPresented: Binding(
                        get: { store.isConfirmingClear },
                        set: { if !$0 { store.cancelClear() } }),
                    titleVisibility: .visible
                ) {
                    Button("清空全部", role: .destructive) { clear() }
                    Button("取消", role: .cancel) { store.cancelClear() }
                } message: {
                    Text("删除后无法恢复；生词本与收藏不受影响。")
                }
                .alert(
                    "操作失败",
                    isPresented: Binding(
                        get: { actionError != nil },
                        set: { if !$0 { actionError = nil } })
                ) {
                    Button("好", role: .cancel) {}
                } message: {
                    Text(actionError ?? "")
                }
        }
    }

    private var filtered: [HistoryRecord] {
        HistoryFilter.apply(records, search: search, operation: operationFilter)
    }

    @ViewBuilder private var content: some View {
        if records.isEmpty {
            ContentUnavailableView {
                Label("暂无历史", systemImage: "clock")
            } description: {
                Text("成功的翻译与润色会自动记录在这里。")
            } actions: {
                Button("开始翻译", action: openProcessing).buttonStyle(.glass)
            }
        } else if filtered.isEmpty {
            ContentUnavailableView {
                Label("无匹配结果", systemImage: "clock")
            } description: {
                Text("没有记录符合当前的搜索和筛选条件。")
            } actions: {
                Button("清除筛选") {
                    search = ""
                    operationFilter = nil
                }
                .buttonStyle(.glass)
            }
        } else {
            List(filtered) { record in
                HistoryRowLink(record: record) { delete(record) }
            }
            .listStyle(.inset)
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Picker("筛选类型", selection: $operationFilter) {
                Text("全部类型").tag(Operation?.none)
                ForEach(Operation.allCases, id: \.self) { operation in
                    Text(operation.title).tag(Operation?.some(operation))
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                store.requestClear()
            } label: {
                Label("清空历史", systemImage: "trash")
            }
            .disabled(records.isEmpty)
        }
    }

    /// A storage failure is reported here because the result itself stays on the processing screen.
    @ViewBuilder private var errorBanner: some View {
        if let message = store.lastError {
            HStack(spacing: 12) {
                Label("历史保存失败：\(message)", systemImage: "exclamationmark.triangle")
                    .frame(maxWidth: .infinity, alignment: .leading)
                GlassEffectContainer {
                    Button("关闭") { store.dismissError() }.buttonStyle(.glass)
                }
            }
            .font(.system(size: 12))
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }

    private func delete(_ record: HistoryRecord) {
        do {
            try store.delete(record)
            actionError = nil
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func clear() {
        do {
            try store.confirmClear()
            actionError = nil
        } catch {
            actionError = error.localizedDescription
        }
    }
}

/// One list row whose delete control is revealed on hover, so the list stays quiet at rest.
private struct HistoryRowLink: View {
    let record: HistoryRecord
    let onDelete: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            NavigationLink(value: record) {
                HistoryRow(record: record)
            }
            Button(action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .opacity(isHovering ? 1 : 0)
            .help("删除")
            .accessibilityLabel("删除 \(record.source)")
        }
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("删除", role: .destructive, action: onDelete)
        }
    }
}

private struct HistoryRow: View {
    let record: HistoryRecord

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(LanguageDisplay.code(record.language))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 24)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 3) {
                Text(record.source)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(2)
                Text(record.result)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 12)
            Text(record.operationKind.title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct HistoryDetailView: View {
    let record: HistoryRecord
    let collection: CollectionAction
    /// True once this page collected, so a status another screen left behind never shows up here.
    @State private var didCollect = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("\(LanguageDisplay.name(record.language)) · \(record.operationKind.title)")
                    Spacer()
                    Text(HistoryTime.display(record.createdAt))
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.bottom, 12)
                Text(record.source)
                    .font(.system(size: 15))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                    .padding(.bottom, 22)
                Text(record.result)
                    .font(.system(size: 20))
                    .lineSpacing(8)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if didCollect {
                    CollectionFeedback(collection: collection, openNotebook: nil)
                        .font(.system(size: 11))
                        .padding(.top, 24)
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
        }
        .navigationTitle("历史记录 / 详情")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Clipboard.copy(record.result)
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                }
                .buttonStyle(.glass)
            }
            ToolbarItem(placement: .primaryAction) {
                Button("收藏", action: collect).buttonStyle(.glassProminent)
            }
        }
    }

    /// Collects through the shared collect action, which saves first and only then asks for a missing
    /// Chinese meaning, so a failed request leaves this record's own context in the notebook.
    private func collect() {
        didCollect = true
        collection.collect(VocabularyDraft.from(record: record))
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
