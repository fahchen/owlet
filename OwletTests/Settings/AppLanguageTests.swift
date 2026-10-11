import Foundation
import Testing

@testable import Owlet

/// The interface language: which one a fresh launch speaks, and where the choice is written so
/// Foundation resolves the catalog to it.
@Suite struct AppLanguageTests {
    /// Its own suite, so a test never reads or writes the developer's real choice. The suite is named
    /// so a test can also inspect what the app itself persisted through `persistentDomain(forName:)`.
    func defaults(_ name: String = UUID().uuidString) -> UserDefaults {
        UserDefaults(suiteName: suiteName(name))!
    }

    func suiteName(_ name: String) -> String { "AppLanguageTests.\(name)" }

    @Test func aSavedChoiceWins() {
        let defaults = defaults()
        defaults.set(AppLanguage.japanese.rawValue, forKey: SettingsStore.appLanguageKey)
        #expect(SettingsStore.appLanguage(in: defaults) == .japanese)
    }

    @Test func withoutAChoiceTheSystemDecides() {
        #expect(
            AppLanguage.resolve(saved: nil, preferred: ["ja-JP", "en-US"]) == .japanese)
        #expect(
            AppLanguage.resolve(saved: nil, preferred: ["zh-Hant-TW"]) == .traditionalChinese)
        #expect(
            AppLanguage.resolve(saved: nil, preferred: ["zh-Hans-CN"]) == .simplifiedChinese)
        // A language the catalog does not carry falls through to the next one that it does.
        #expect(
            AppLanguage.resolve(saved: nil, preferred: ["ko-KR", "en"]) == .english)
        // None of them: the app is written in Simplified Chinese, so that is what it falls back to.
        #expect(AppLanguage.resolve(saved: nil, preferred: ["ko-KR"]) == .simplifiedChinese)
    }

    /// A saved value the app no longer understands is treated as no choice at all.
    @Test func anUnknownSavedValueFallsBackToTheSystem() {
        #expect(
            AppLanguage.resolve(saved: "kl", preferred: ["ja"]) == .japanese)
    }

    @Test func aChosenLanguageIsWrittenWhereFoundationReadsIt() {
        let defaults = defaults()
        AppLanguage.apply(.japanese, to: defaults)
        #expect(defaults.stringArray(forKey: "AppleLanguages") == ["ja"])
        // The stored choice is the case, not the locale: it is the app's own setting.
        #expect(defaults.string(forKey: SettingsStore.appLanguageKey) == AppLanguage.japanese.rawValue)

        AppLanguage.apply(.traditionalChinese, to: defaults)
        #expect(defaults.stringArray(forKey: "AppleLanguages") == ["zh-Hant"])
    }

    /// "Follow the system" must leave no override behind, or the app would keep speaking the last
    /// language it was set to.
    ///
    /// Only the app's own domain can answer this. A global `AppleLanguages` is always in the search
    /// list, so `object(forKey:)` and `stringArray(forKey:)` both keep answering after the override is
    /// removed — which is precisely the behaviour "follow the system" relies on.
    @Test func followingTheSystemClearsTheOverride() {
        let name = UUID().uuidString
        let defaults = defaults(name)
        AppLanguage.apply(.english, to: defaults)
        #expect(defaults.persistentDomain(forName: suiteName(name))?["AppleLanguages"] as? [String] == ["en"])

        AppLanguage.apply(.system, to: defaults)
        #expect(defaults.persistentDomain(forName: suiteName(name))?["AppleLanguages"] == nil)
        #expect(defaults.string(forKey: SettingsStore.appLanguageKey) == AppLanguage.system.rawValue)
    }

    /// Startup reads the system's languages before it writes the override; reading them after would
    /// resolve the system against the app's own last choice.
    @Test func startupAppliesTheStoredChoice() {
        let defaults = defaults()
        defaults.set(AppLanguage.english.rawValue, forKey: SettingsStore.appLanguageKey)
        let applied = AppLanguage.applyStoredChoice(in: defaults)
        #expect(applied == .english)
        #expect(defaults.stringArray(forKey: "AppleLanguages") == ["en"])
    }

    @Test func everyChoiceNamesItself() {
        #expect(AppLanguage.selectable.count == 5)
        #expect(AppLanguage.supported == ["zh-Hans", "zh-Hant", "en", "ja"])
        // A locale is only absent for the system choice, which is what makes it the fallback.
        #expect(AppLanguage.system.locale == nil)
        #expect(AppLanguage.allCases.compactMap(\.locale).count == 4)
    }
}
