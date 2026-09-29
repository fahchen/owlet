import SwiftUI

/// Retry entry shown while an entry has no Chinese meaning yet.
struct MissingMeaningView: View {
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

struct VocabularyContextView: View {
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
