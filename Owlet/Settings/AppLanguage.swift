import Foundation
import SwiftUI

/// Which language the interface speaks. The app is written in Simplified Chinese, so that is the
/// source language of `Localizable.xcstrings`, and the three others are translated there.
///
/// The choice is applied by writing `AppleLanguages` before any view is built, which is how Foundation
/// resolves the catalog, so it takes effect on the next launch rather than needing a second
/// localization path inside the app.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case simplifiedChinese
    case traditionalChinese
    case english
    case japanese

    var id: String { rawValue }

    /// The languages a user can pick, in the order the picker shows them: the system, then the four
    /// the catalog is translated into.
    static let selectable: [AppLanguage] = [
        .system, .simplifiedChinese, .traditionalChinese, .english, .japanese,
    ]

    /// The interface languages the catalog is translated into, in `AppleLanguages` notation.
    static let supported = ["zh-Hans", "zh-Hant", "en", "ja"]

    /// The locale this choice means, or nil for "follow the system".
    var locale: String? {
        switch self {
        case .system: nil
        case .simplifiedChinese: "zh-Hans"
        case .traditionalChinese: "zh-Hant"
        case .english: "en"
        case .japanese: "ja"
        }
    }

    /// What the picker shows for this choice.
    ///
    /// A language names itself — 简体中文, 繁體中文, English, 日本語 — because the picker's whole job is
    /// to be readable *before* the interface is switched to it; naming them in the current interface
    /// language would be the one place that cannot be read until too late. "Follow the system" is the
    /// exception: it is not a language, so it does come from the catalog.
    var title: String {
        switch self {
        case .system: L10n.shared.string("Follow System")
        default:
            // The system already knows a language's own name for itself, so no name is written here —
            // which also keeps the sources free of the scripts the catalog is supposed to hold.
            Locale(identifier: locale ?? "en").localizedString(forIdentifier: locale ?? "en")
                ?? locale ?? "en"
        }
    }

    /// The choice to open with: what was saved, else the best match for the user's own languages,
    /// else the source language. `preferred` is Foundation's order, most wanted first.
    static func resolve(saved: String?, preferred: [String]) -> AppLanguage {
        if let saved, let language = AppLanguage(rawValue: saved) { return language }
        return pick(from: preferred) ?? .simplifiedChinese
    }

    /// Applies the stored choice and returns it. The system's own order has to be read *before* the
    /// override is written, or the app would resolve "follow the system" against its own last choice.
    @discardableResult
    static func applyStoredChoice(in defaults: UserDefaults = .standard) -> AppLanguage {
        let saved = defaults.string(forKey: SettingsStore.appLanguageKey)
        let choice = resolve(
            saved: saved,
            preferred: saved == nil ? Locale.preferredLanguages : [])
        apply(choice, to: defaults)
        return choice
    }

    /// The interface language that best matches the user's own, or nil when none of the four is
    /// among them. `preferred` is Foundation's order, most wanted first.
    static func pick(from preferred: [String]) -> AppLanguage? {
        for tag in preferred {
            guard let match = AppLanguage.supported.first(where: { LanguageTag.same($0, tag) }) else {
                continue
            }
            switch match {
            case "zh-Hans": return .simplifiedChinese
            case "zh-Hant": return .traditionalChinese
            case "ja": return .japanese
            default: return .english
            }
        }
        return nil
    }

    /// Writes the choice where Foundation reads it, so the catalog resolves to it from the next launch.
    /// The override is removed first and only then written back, because removing it is what makes the
    /// app follow the system again: a global `AppleLanguages` is always in the search list, so an
    /// override left behind would keep winning over the system's own order.
    static func apply(_ language: AppLanguage, to defaults: UserDefaults = .standard) {
        defaults.set(language.rawValue, forKey: SettingsStore.appLanguageKey)
        defaults.removeObject(forKey: "AppleLanguages")
        guard let locale = language.locale else { return }
        defaults.set([locale], forKey: "AppleLanguages")
    }
}
