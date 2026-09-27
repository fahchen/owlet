import SwiftData
import SwiftUI

/// Sidebar 生词本 page: the collected expressions, their detail, and the empty state.
struct VocabularyView: View {
    let collection: CollectionAction
    let openProcessing: () -> Void
    @Query(sort: \VocabularyEntry.createdAt, order: .reverse) private var entries: [VocabularyEntry]

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    ContentUnavailableView {
                        Label("暂无收藏", systemImage: "book")
                    } description: {
                        Text("收藏的词汇、短语和整句会出现在这里。")
                    } actions: {
                        Button("开始翻译", action: openProcessing).buttonStyle(.glass)
                    }
                } else {
                    List(entries) { entry in
                        NavigationLink(value: entry) {
                            VocabularyRow(entry: entry)
                        }
                    }
                    .listStyle(.inset)
                }
            }
            .navigationTitle("生词本")
            .navigationDestination(for: VocabularyEntry.self) { entry in
                VocabularyDetailView(entry: entry, collection: collection)
            }
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

private struct VocabularyDetailView: View {
    let entry: VocabularyEntry
    let collection: CollectionAction

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
                meaningSection.padding(.bottom, 24)
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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Clipboard.copy(entry.expression)
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                }
                .buttonStyle(.glass)
            }
        }
    }

    private var meaningSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("中文释义")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            if entry.meaning.isEmpty {
                HStack(spacing: 12) {
                    Text("尚无中文释义").foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    MeaningAction(entry: entry, collection: collection)
                }
            } else {
                Text(entry.meaning)
                    .font(.system(size: 15))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
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
