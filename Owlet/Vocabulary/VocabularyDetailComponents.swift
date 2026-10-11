import SwiftUI

/// Retry entry shown while an entry has no Chinese meaning yet.
struct MissingMeaningView: View {
    let entry: VocabularyEntry
    let collection: CollectionAction

    var body: some View {
        switch collection.status {
        case .filling(let filling) where filling == entry:
            Text(L10n.shared.string("Filling in the meaning…")).foregroundStyle(.secondary)
        // As in the learning column: a red message and a plain retry.
        case .meaningFailed(let failed, let message) where failed == entry:
            VStack(alignment: .leading, spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                Button("Retry", systemImage: "arrow.clockwise") { collection.fillMeaning(for: entry) }
                    .buttonStyle(.plain)
            }
        default:
            Button("Fill In Meaning", systemImage: "text.badge.plus") { collection.fillMeaning(for: entry) }
                .buttonStyle(.plain)
        }
    }
}

struct VocabularyContextView: View {
    let context: VocabularyContext
    /// The language the sentence is written in, which is not always the entry's; a context that
    /// never recorded one falls back to the entry's own.
    let language: String
    let definitionLanguage: String

    var origin: LookupOrigin {
        LookupOrigin(language: language, definitionLanguage: definitionLanguage)
    }

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
            LookupText(
                text: context.source, size: PanelMetrics.sourceTextSize, label: "Source Sentence", origin: origin
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            if let before = context.polishBefore, let after = context.polishAfter {
                comparison(title: "Before Polish", text: before, secondary: true)
                comparison(title: "After Polish", text: after)
            }
        }
    }

    private func comparison(title: String, text: String, secondary: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            LookupText(text: text, size: 14, secondary: secondary, label: title, origin: origin)
        }
    }
}
