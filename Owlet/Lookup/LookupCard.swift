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

    /// The language the notebook would key this word under; nil keeps the entry unusable, so the
    /// card offers no collect action rather than saving a language-less entry.
    private var notebookLanguage: String? { query.lookupLanguage(from: shown?.result) }

    private var isCollected: Bool {
        guard let collection = presenter.collection, let language = notebookLanguage else { return false }
        // Reading the revision is what re-renders this card when a click lands: the notebook's store is
        // SwiftData, which a popover outside its container never observes, so membership alone would
        // only appear the next time the card was built.
        _ = collection.revision
        return collection.isCollected(language: language, expression: query.text)
    }

    /// Whether the card can offer 加入生词本 at all: a notebook action is wired in and the text's
    /// language is known. Read-only usage without one keeps the card exactly as it was.
    private var canCollect: Bool { presenter.collection != nil && notebookLanguage != nil }

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
            HStack(spacing: 6) {
                if let shown, canCollect { collectButton(shown.result) }
                CardButton(title: "发音", symbol: "speaker.wave.2") {
                    if let voiceLanguage { presenter.speak(query.text, language: voiceLanguage) }
                }
                .disabled(!canSpeak)
                .accessibilityHint(canSpeak ? "" : "暂无系统语音")
                .hoverTip(canSpeak ? "发音" : "暂无系统语音")
            }
        }
    }

    /// 加入生词本／已收藏 as the same round glass action as 发音, beside it, so the two read as one pair.
    /// Filled and accented once the entry is stored, matching the learning rows. The card stays open,
    /// and the entry keeps the meaning the lookup already paid for.
    private func collectButton(_ result: LookupResult) -> some View {
        CardGlassButton(
            title: isCollected ? "已收藏" : "加入生词本",
            symbol: isCollected ? "bookmark.fill" : "bookmark",
            tint: isCollected ? Color.accentColor : Color.primary
        ) {
            guard let language = notebookLanguage else { return }
            presenter.collection?.setCollected(
                !isCollected,
                query: query.language == nil ? stampedLanguageQuery(language) : query,
                result: result)
        }
        .accessibilityValue(isCollected ? "已收藏" : "未收藏")
        .accessibilityHint(isCollected ? "取消收藏" : "加入生词本")
    }

    /// The lookup can identify the language the reading area did not know; the notebook keys on it, so
    /// the query carries it from here on.
    private func stampedLanguageQuery(_ language: String) -> LookupQuery {
        var query = query
        query.language = language
        return query
    }

    /// Lemma when it differs from the queried form, then pronunciation and part of speech. The
    /// model returns null for what does not apply, a whole sentence's pronunciation included.
    private var details: String? {
        guard let result = shown?.result else { return nil }
        var parts: [String] = []
        if let lemma = result.lemma,
            TranslationResult.normalized(lemma) != TranslationResult.normalized(query.text)
        {
            parts.append(lemma)
        }
        parts += [result.pronunciation, result.partOfSpeech].compactMap { $0 }
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
