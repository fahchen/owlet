import SwiftUI

/// The lookup card: the queried form as the title, the model's lemma and pronunciation beneath it,
/// then the meaning. An answer from another sentence is labelled with its source until rechecked.
struct LookupCard: View {
    let presenter: LookupPresenter
    let query: LookupQuery
    let other: LookupQuery?

    private var current: LookupStore.Entry? { presenter.store.entries[query] }

    /// The answer on screen: this query's own once it has one, else the other sentence's.
    private var shown: (result: LookupResult, source: LookupQuery)? {
        if case .success(let result) = current { return (result, query) }
        if let other, case .success(let result) = presenter.store.entries[other] {
            return (result, other)
        }
        return nil
    }

    /// The text's language for the system voice; a page language is never guessed.
    private var voiceLanguage: String? { query.language ?? shown?.result.language }

    private var canSpeak: Bool { voiceLanguage.map(presenter.speech.canSpeak) ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let shown {
                Text(shown.result.meaning)
                    .font(.system(size: PanelMetrics.sourceTextSize))
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if shown.source != query, let context = shown.source.context {
                    Label("这条释义来自另一句", systemImage: "text.quote")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Text(context)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .textSelection(.enabled)
                } else if query.context == nil {
                    Label("无原句语境", systemImage: "info.circle")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            status
        }
        .padding(16)
        .frame(width: 320, alignment: .leading)
        .onAppear { announce(current) }
        .onChange(of: current) { _, entry in announce(entry) }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(query.text)
                    .font(.system(size: PanelMetrics.textSize, weight: .semibold))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if let details {
                    Text(details).font(.system(size: 13)).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 4) {
                CardButton(title: "发音", symbol: "speaker.wave.2") {
                    if let voiceLanguage { presenter.speak(query.text, language: voiceLanguage) }
                }
                .disabled(!canSpeak)
                .accessibilityHint(canSpeak ? "" : "暂无系统语音")
                if !canSpeak {
                    Text("暂无系统语音").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Lemma when it differs from the queried form, then pronunciation and part of speech; a
    /// sentence has neither of the last two and missing fields are simply left out.
    private var details: String? {
        guard let result = shown?.result else { return nil }
        var parts: [String] = []
        if let lemma = result.lemma,
            TranslationResult.normalized(lemma) != TranslationResult.normalized(query.text)
        {
            parts.append(lemma)
        }
        if !query.isSentence {
            parts += [result.pronunciation, result.partOfSpeech].compactMap { $0 }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Loading and failure sit centered, as the panel's and the learning column's own states do.
    @ViewBuilder private var status: some View {
        switch current {
        case .loading?:
            Text(shown == nil ? "查询中…" : "正在按当前语境重查…")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        case .failure(let message)?:
            VStack(spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button("重试", systemImage: "arrow.clockwise") { presenter.requestCurrent() }
                    .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
        case nil where shown != nil:
            Button("按当前语境重查", systemImage: "arrow.clockwise") { presenter.requestCurrent() }
                .buttonStyle(.plain)
        default:
            EmptyView()
        }
    }

    /// VoiceOver hears progress and failure as they happen, without having to find the card.
    private func announce(_ entry: LookupStore.Entry?) {
        let message: String? =
            switch entry {
            case .loading?: "正在查询"
            case .failure(let message)?: "查询失败：\(message)"
            case .success(let result)?: result.meaning
            case nil: nil
            }
        if let message { AccessibilityNotification.Announcement(message).post() }
    }
}
