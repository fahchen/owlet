import SwiftData
import SwiftUI

/// Sidebar 生词本 page: search, language filter and export over one list, plus the detail editor.
struct VocabularyView: View {
    let collection: CollectionAction
    let openProcessing: () -> Void
    @Query(sort: \VocabularyEntry.createdAt, order: .reverse) private var entries: [VocabularyEntry]
    @State private var search = ""
    /// Empty means 全部语言; the picker's tags are plain strings so no optional tag is needed.
    @State private var language = ""
    @State private var exporter = NotebookExporter()
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("生词本")
                .searchable(text: $search, prompt: "搜索表达或释义")
                .navigationDestination(for: VocabularyEntry.self) { entry in
                    VocabularyDetailView(entry: entry, collection: collection)
                }
                .toolbar { toolbar }
                .alert(
                    "操作失败",
                    isPresented: Binding(
                        get: { errorMessage != nil },
                        set: { if !$0 { errorMessage = nil } })
                ) {
                    Button("好", role: .cancel) {}
                } message: {
                    Text(errorMessage ?? "")
                }
                .alert(
                    "导出失败",
                    isPresented: Binding(
                        get: { if case .failed = exporter.status { true } else { false } },
                        set: { if !$0 { exporter.reset() } })
                ) {
                    Button("好", role: .cancel) {}
                } message: {
                    if case .failed(let message) = exporter.status { Text(message) }
                }
        }
    }

    private var filtered: [VocabularyEntry] {
        VocabularyFilter.apply(entries, search: search, language: language.isEmpty ? nil : language)
    }

    @ViewBuilder private var content: some View {
        if entries.isEmpty {
            ContentUnavailableView {
                Label("暂无收藏", systemImage: "bookmark")
            } description: {
                Text("收藏的词汇、短语和整句会出现在这里。")
            } actions: {
                Button("开始翻译", action: openProcessing).buttonStyle(.glass)
            }
        } else if filtered.isEmpty {
            ContentUnavailableView {
                Label("无匹配结果", systemImage: "bookmark")
            } description: {
                Text("没有表达符合当前的搜索和筛选条件。")
            } actions: {
                Button("清除筛选") {
                    search = ""
                    language = ""
                }
                .buttonStyle(.glass)
            }
        } else {
            List {
                Section("所有表达 · \(filtered.count)") {
                    ForEach(filtered) { entry in
                        row(entry)
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    private func row(_ entry: VocabularyEntry) -> some View {
        HStack(spacing: 8) {
            NavigationLink(value: entry) {
                VocabularyRow(entry: entry)
            }
            Button {
                delete(entry)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("删除")
            .accessibilityLabel("删除 \(entry.expression)")
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Picker("筛选语言", selection: $language) {
                Text("全部语言").tag("")
                ForEach(VocabularyFilter.languages(in: entries), id: \.self) { tag in
                    Text(LanguageDisplay.name(tag)).tag(tag)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                exporter.export(entries)
            } label: {
                Label("导出…", systemImage: "square.and.arrow.up")
            }
            .disabled(entries.isEmpty)
        }
    }

    private func delete(_ entry: VocabularyEntry) {
        do {
            try collection.store.delete(entry)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct VocabularyRow: View {
    let entry: VocabularyEntry

    var body: some View {
        HStack(spacing: 12) {
            Text(LanguageDisplay.code(entry.language))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 24)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.expression)
                    .font(.system(size: 14, weight: .medium))
                Text(entry.meaning.isEmpty ? "尚无中文释义" : entry.meaning)
                    .font(.system(size: 12))
                    .foregroundStyle(entry.meaning.isEmpty ? .tertiary : .secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            Text("\(entry.contexts.count) 个语境")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

/// Detail page from `design/screenshots/book-detail.png`: the expression and its Chinese meaning
/// are editable and saved together, while the collected sentences stay read-only history.
private struct VocabularyDetailView: View {
    let entry: VocabularyEntry
    let collection: CollectionAction
    @State private var expression: String
    @State private var meaning: String
    @State private var errorMessage: String?

    init(entry: VocabularyEntry, collection: CollectionAction) {
        self.entry = entry
        self.collection = collection
        _expression = State(initialValue: entry.expression)
        _meaning = State(initialValue: entry.meaning)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("\(LanguageDisplay.name(entry.language)) · 收藏表达")
                    Spacer()
                    Text("个人生词本")
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.bottom, 12)
                Text(entry.expression)
                    .font(.system(size: 26, weight: .semibold))
                    .textSelection(.enabled)
                    .padding(.bottom, 22)
                editor.padding(.bottom, 24)
                if entry.meaning.isEmpty {
                    MeaningAction(entry: entry, collection: collection)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.bottom, 24)
                }
                Text("原句语境")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.bottom, 10)
                ForEach(entry.contexts) { context in
                    ContextView(context: context).padding(.bottom, 12)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
        }
        .navigationTitle("生词本 / 详情")
        .onChange(of: entry.meaning) { _, new in
            // The 补充中文释义 request writes straight to the model, so the field follows it.
            meaning = new
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Clipboard.copy(entry.expression)
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                }
                .buttonStyle(.glass)
            }
            ToolbarItem(placement: .primaryAction) {
                Button("保存", action: save)
                    .buttonStyle(.glassProminent)
                    .disabled(!isDirty)
            }
        }
        .alert(
            "保存失败",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } })
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var isDirty: Bool {
        expression.trimmingCharacters(in: .whitespacesAndNewlines) != entry.expression
            || meaning.trimmingCharacters(in: .whitespacesAndNewlines) != entry.meaning
    }

    private var editor: some View {
        VStack(spacing: 0) {
            field("表达") {
                TextField("表达", text: $expression)
            }
            Divider()
            field("中文释义") {
                TextField("中文释义", text: $meaning, axis: .vertical)
                    .lineLimit(2...4)
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private func field(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)
            content()
                .textFieldStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
    }

    private func save() {
        do {
            try collection.store.update(entry, expression: expression, meaning: meaning)
            expression = entry.expression
            meaning = entry.meaning
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
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
                .padding(14)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
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
