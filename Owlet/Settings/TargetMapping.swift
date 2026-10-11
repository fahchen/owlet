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

    /// What to call a language in the interface, in the interface's own language: the catalog carries
    /// the languages this app deals with, and anything else falls back to the system's name for itself
    /// — there are hundreds and they cannot all be translated here.
    static func name(for tag: String) -> String {
        let known = localizedName(for: tag)
        if let known { return known }
        let locale = Locale(identifier: tag)
        guard let native = locale.localizedString(forIdentifier: tag) else { return tag }
        return native.prefix(1).uppercased(with: locale) + native.dropFirst()
    }

    /// The translated name, or nil when the catalog does not carry this language. Chinese is named by
    /// script, as the contract splits it.
    private static func localizedName(for tag: String) -> String? {
        switch LanguageTag.key(tag) {
        case "zh-Hans": return String(localized: "简体中文")
        case "zh-Hant": return String(localized: "繁體中文")
        case "en": return String(localized: "英语")
        case "ja": return String(localized: "日语")
        case "ko": return String(localized: "韩语")
        case "fr": return String(localized: "法语")
        case "de": return String(localized: "德语")
        case "es": return String(localized: "西班牙语")
        case "ru": return String(localized: "俄语")
        default: return nil
        }
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
            .map { LanguageOption(tag: $0, name: name(for: $0)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
