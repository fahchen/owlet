import Foundation

/// The source → target language mapping (BDR-0003). It decides the target only when the user has not
/// pinned one; the source comes from `LanguageDetector`, and an unmatched one falls back.
struct TargetMapping: Equatable, Sendable {
    /// Canonical source tags (`LanguageTag.key`) to target tags; one target per source.
    var targets: [String: String]
    /// Used when the source is unknown or has no row.
    var fallback: String

    /// The target for a detected source; nil means the language could not be detected.
    func target(forSource source: String?) -> String {
        guard let source, let mapped = targets[source] else { return fallback }
        return mapped
    }
}

/// One language the pickers can name.
struct LanguageOption: Hashable, Identifiable, Sendable {
    let tag: String
    let name: String
    var id: String { tag }
}

/// The language choices, taken from the system rather than a list this app maintains, so a language
/// the app has never heard of is still selectable. Chinese is the one addition: the system list has
/// only `zh`, while the contract treats 简体 and 繁體 as different targets.
enum LanguageCatalog {
    static let targets: [LanguageOption] = options()

    /// The localized name for a tag, including tags this list does not offer.
    static func name(for tag: String) -> String {
        if let known = targets.first(where: { $0.tag == tag }) { return known.name }
        return Locale.current.localizedString(forIdentifier: tag) ?? tag
    }

    /// The offered choices: only the languages selected in settings, in the order they were selected.
    static func options(for tags: [String]) -> [LanguageOption] {
        tags.map { LanguageOption(tag: $0, name: name(for: $0)) }
    }

    private static func options() -> [LanguageOption] {
        var tags = Locale.LanguageCode.isoLanguageCodes.map { LanguageTag.key($0.identifier) }
        tags.append("zh-Hant")
        // The ISO `zh` canonicalizes to `zh-Hans`, so only the traditional tag has to be added.
        return Set(tags)
            .map { LanguageOption(tag: $0, name: Locale.current.localizedString(forIdentifier: $0) ?? $0) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
