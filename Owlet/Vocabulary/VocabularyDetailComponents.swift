import SwiftUI

/// Retry entry shown while an entry has no Chinese meaning yet.
struct MissingMeaningView: View {
    let entry: VocabularyEntry
    let collection: CollectionAction

    var body: some View {
        switch collection.status {
        case .filling(let filling) where filling == entry:
            Text("正在补充中文释义…").foregroundStyle(.secondary)
        // As in the learning column: a red message and a plain retry.
        case .meaningFailed(let failed, let message) where failed == entry:
            VStack(alignment: .leading, spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                Button("重试", systemImage: "arrow.clockwise") { collection.fillMeaning(for: entry) }
                    .buttonStyle(.plain)
            }
        default:
            Button("补充中文释义", systemImage: "text.badge.plus") { collection.fillMeaning(for: entry) }
                .buttonStyle(.plain)
        }
    }
}

struct VocabularyContextView: View {
    let context: VocabularyContext

    /// A quote: a thin accent bar beside the sentence, and for a polish the before in gray above the
    /// after in full color, so the change reads at a glance.
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 1.5).fill(.tint).frame(width: 3)
            content
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(context.source)
                .font(.system(size: PanelMetrics.sourceTextSize, weight: PanelMetrics.sourceWeight))
                .lineSpacing(2)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let before = context.polishBefore, let after = context.polishAfter {
                comparison(title: "润色前", text: before).foregroundStyle(.secondary)
                comparison(title: "润色后", text: after)
            }
        }
    }

    private func comparison(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(text).font(.system(size: 14)).lineSpacing(2).textSelection(.enabled)
        }
    }
}
