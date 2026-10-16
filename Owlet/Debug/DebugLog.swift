import Foundation

/// One model exchange kept for the debug page. It holds the user's text, so it lives in memory only
/// and is never written anywhere.
struct DebugExchange: Identifiable, Sendable {
    let id = UUID()
    var date = Date()
    /// "Translate · zh-Hant" / "Polish", naming what was asked for.
    var title: String
    /// The glyph that names the request on the page: the operation's own, or the entry that asked.
    var symbol = "terminal"
    /// The request body exactly as sent, pretty printed. The API key travels in a header, so it is
    /// not in here.
    var request: String
    /// The text that was submitted, kept for the source comparison.
    var submitted: String
    /// The model's raw message content, when a response arrived.
    var response: String?
    /// The failure as the UI shows it, and what kind it was. The kind is what the page reasons about:
    /// a translated message must never be the thing that decides which comparison to show.
    var failure: String?
    var failureKind: ModelError.Kind?

    /// Where a source mismatch first stops matching the submitted text. nil for every other failure,
    /// so the page only explains the check that actually failed.
    var sourceDivergence: String? {
        guard failureKind == .contract, failure == ModelError.sourceMismatch.message,
            let response,
            let object = try? JSONSerialization.jsonObject(with: Data(response.utf8))
                as? [String: Any],
            let segments = object["segments"] as? [[String: Any]]
        else { return nil }
        let returned = TranslationResult.normalized(
            segments.compactMap { $0["source"] as? String }.joined())
        let wanted = TranslationResult.normalized(submitted)
        guard returned != wanted else { return nil }
        let index =
            zip(returned, wanted).enumerated().first { $0.element.0 != $0.element.1 }?.offset
            ?? min(returned.count, wanted.count)
        return L10n.shared.string(
            "The first difference is at character %lld:\nreturned …%@…\nsubmitted …%@…",
            index, Self.snippet(of: returned, around: index), Self.snippet(of: wanted, around: index))
    }

    /// One line of the captured text, for a collapsed row: a list row must not grow with the text.
    var summary: String {
        submitted.split(whereSeparator: \.isNewline).joined(separator: " ")
    }

    /// The plain text a one-click copy puts on the pasteboard.
    var report: String {
        var lines = ["# \(title)", L10n.shared.string("Time: %@", date.formatted(date: .numeric, time: .standard))]
        if let failure { lines.append(L10n.shared.string("Failure: %@", failure)) }
        if let sourceDivergence { lines.append(L10n.shared.string("Source difference:\n%@", sourceDivergence)) }
        lines.append(L10n.shared.string("\n## Request body\n%@", request))
        if let response { lines.append(L10n.shared.string("\n## Model raw reply\n%@", response)) }
        lines.append(L10n.shared.string("\n## Submitted text\n%@", submitted))
        return lines.joined(separator: "\n")
    }

    private static func snippet(of text: String, around index: Int) -> String {
        let radius = 30
        let start = text.index(text.startIndex, offsetBy: max(0, index - radius))
        let end = text.index(
            text.startIndex, offsetBy: min(text.count, index + radius))
        return String(text[start..<end])
    }
}

/// The exchanges the debug page shows. In memory only: turning the page off clears it.
@MainActor @Observable
final class DebugLog {
    static let shared = DebugLog()
    /// Recent attempts are enough to diagnose, and the list must not grow without bound.
    static let limit = 20

    private(set) var exchanges: [DebugExchange] = []

    /// Drops everything captured so far. The switch that turns the page on is also the consent for
    /// keeping the user's text in memory, so turning it off must not leave records behind.
    func clear() { exchanges.removeAll() }

    func add(_ exchange: DebugExchange) {
        exchanges.insert(exchange, at: 0)
        if exchanges.count > Self.limit {
            exchanges.removeLast(exchanges.count - Self.limit)
        }
    }

}

/// Where a `ModelClient` hands a finished exchange. Disabled by default, so ordinary use never keeps
/// the user's text; injectable so a test can capture without touching the shared page.
struct DebugCapture: Sendable {
    var isEnabled: @Sendable () -> Bool = { SettingsStore.isDebugEnabled() }
    var record: @Sendable (DebugExchange) async -> Void = { await DebugLog.shared.add($0) }

    static let live = DebugCapture()
    static let off = DebugCapture(isEnabled: { false }, record: { _ in })
}
