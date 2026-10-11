import Foundation
import Observation

/// Resolves interface text in the language the user chose, at the moment it is shown.
///
/// A bare literal and `Text(L10n.shared.string("…"))` resolve through `Bundle.main`, whose language is fixed when the
/// process starts, so a language change could only take effect on the next launch. This looks the text
/// up in the chosen language's bundle instead, and views observe `revision`, so a switch redraws them
/// right away.
@Observable
final class L10n: @unchecked Sendable {
    static let shared = L10n()

    /// Read by the root view, so every view below it is rebuilt when the language changes.
    ///
    /// Not isolated to the main actor: `LanguageCatalog.name` and the debug report are called from
    /// wherever they are needed, so the language and its bundle are guarded by a lock instead.
    private(set) var revision = 0

    /// The language the catalog's keys are written in, and the fallback for a missing entry.
    static let sourceLanguage = "en"

    private let lock = NSLock()
    private var language: String
    private var bundle: Bundle

    private init() {
        let chosen = AppLanguage.resolve(
            saved: UserDefaults.standard.string(forKey: SettingsStore.appLanguageKey),
            preferred: Locale.preferredLanguages)
        language = chosen.resolvedLocale
        bundle = Self.bundle(for: chosen.resolvedLocale) ?? .main
    }

    /// Switches the language; the revision bump is what redraws the interface.
    func use(_ choice: AppLanguage) {
        lock.withLock {
            language = choice.resolvedLocale
            bundle = Self.bundle(for: choice.resolvedLocale) ?? .main
        }
        revision &+= 1
    }

    /// The text for `key` in the current language, or the English source text when the catalog has no
    /// entry — so a gap shows up as English rather than as a raw key.
    func string(_ key: String) -> String {
        let fallback = Self.source[key] ?? key
        return lock.withLock {
            guard language != Self.sourceLanguage else { return fallback }
            return bundle.localizedString(forKey: key, value: fallback, table: nil)
        }
    }

    /// The text for `key` with its `%@` placeholders filled from `arguments`.
    func string(_ key: String, _ arguments: CVarArg...) -> String {
        guard !arguments.isEmpty else { return string(key) }
        return String(format: string(key), arguments: arguments)
    }

    /// The English text every key resolves to, used as the fallback when a translation is missing.
    private static let source: [String: String] = {
        let path = Bundle.main.bundlePath as NSString
        let url = URL(fileURLWithPath: path.appendingPathComponent("Contents/Resources/en.lproj/Localizable.strings"))
        guard let table = NSDictionary(contentsOf: url) as? [String: String] else { return [:] }
        return table
    }()

    private static func bundle(for locale: String?) -> Bundle? {
        guard let locale else { return nil }
        let path = Bundle.main.bundlePath as NSString
        let url = URL(fileURLWithPath: path.appendingPathComponent("Contents/Resources/\(locale).lproj"))
        return Bundle(url: url)
    }
}
