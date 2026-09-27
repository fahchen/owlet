import SwiftData
import SwiftUI

/// Sidebar 历史记录 page: the finished results, their detail, and the empty state.
struct HistoryView: View {
    let store: HistoryStore
    let openProcessing: () -> Void
    @Query(sort: \HistoryRecord.createdAt, order: .reverse) private var records: [HistoryRecord]

    var body: some View {
        NavigationStack {
            Group {
                if records.isEmpty {
                    ContentUnavailableView {
                        Label("暂无历史", systemImage: "clock")
                    } description: {
                        Text("成功的翻译与润色会自动记录在这里。")
                    } actions: {
                        Button("开始翻译", action: openProcessing).buttonStyle(.glass)
                    }
                } else {
                    List(records) { record in
                        NavigationLink(value: record) {
                            HistoryRow(record: record)
                        }
                    }
                    .listStyle(.inset)
                }
            }
            .navigationTitle("历史记录")
            .navigationDestination(for: HistoryRecord.self) { record in
                HistoryDetailView(record: record)
            }
            .safeAreaInset(edge: .top, spacing: 0) { errorBanner }
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
        }
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
