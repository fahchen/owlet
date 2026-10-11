import Foundation
import Testing

@testable import Owlet

/// The mapping (BDR-0003) decides the target from the detected source, a pinned language wins over
/// it, and the old single target language becomes the fallback so an existing install is unchanged.
struct TargetMappingTests {
    let suite = "TargetMappingTests.\(UUID().uuidString)"
    var defaults: UserDefaults { UserDefaults(suiteName: suite)! }

    @Test func aFreshInstallMapsNothingAndFallsBackToSimplifiedChinese() {
        let mapping = SettingsStore.targetMapping(in: defaults)
        #expect(mapping.targets.isEmpty)
        #expect(mapping.fallback == "zh-Hans")
        #expect(SettingsStore.pinnedTarget(in: defaults) == nil)
    }

    /// Before the mapping, the one target language was the whole setting; it becomes the fallback.
    @Test func theOldTargetLanguageBecomesTheFallback() {
        defaults.set("ja", forKey: SettingsStore.targetLanguageKey)
        #expect(SettingsStore.targetMapping(in: defaults).fallback == "ja")
        #expect(SettingsStore.autoTarget(for: "Could you send me the report?", in: defaults) == "ja")
    }

    @Test func aMappedSourceWinsOverTheFallback() {
        SettingsStore.setTargetMapping(
            TargetMapping(targets: ["en": "ja"], fallback: "zh-Hans"), in: defaults)
        #expect(SettingsStore.autoTarget(for: "Could you send me the report?", in: defaults) == "ja")
    }

    @Test func anUnknownSourceUsesTheFallback() {
        SettingsStore.setTargetMapping(
            TargetMapping(targets: ["en": "ja"], fallback: "zh-Hans"), in: defaults)
        // Blank text is never detected, so it must not pick a mapping row.
        #expect(SettingsStore.autoTarget(for: "   ", in: defaults) == "zh-Hans")
    }

    @Test func aChosenSourceCarriesItsMappedTarget() {
        SettingsStore.setTargetMapping(
            TargetMapping(targets: ["en": "ja"], fallback: "zh-Hans"), in: defaults)
        #expect(SettingsStore.target(followingSource: "en", in: defaults) == "ja")
        #expect(SettingsStore.target(followingSource: "fr", in: defaults) == "zh-Hans")
        // An automatic source leaves the target automatic, so the mapping keeps deciding per text.
        #expect(SettingsStore.target(followingSource: "", in: defaults) == "")
    }

    @Test func aPinnedLanguageOverridesTheMapping() {
        SettingsStore.setTargetMapping(
            TargetMapping(targets: ["en": "ja"], fallback: "zh-Hans"), in: defaults)
        SettingsStore.setPinnedTarget("zh-Hant", in: defaults)
        #expect(
            SettingsStore.resolvedTarget(for: "Could you send me the report?", in: defaults)
                == "zh-Hant")
    }

    /// The source picker is an override for the *mapping lookup* only: the request still lets the
    /// model read the language, this just decides which row is consulted.
    @Test func aPinnedSourceDecidesTheMappingRow() {
        SettingsStore.setTargetMapping(
            TargetMapping(targets: ["en": "ja"], fallback: "zh-Hans"), in: defaults)
        #expect(SettingsStore.autoSource(for: "お世話になっております。", in: defaults) == "ja")
        SettingsStore.setPinnedSource("en", in: defaults)
        #expect(SettingsStore.autoSource(for: "お世話になっております。", in: defaults) == "en")
        #expect(
            SettingsStore.resolvedTarget(for: "お世話になっております。", in: defaults) == "ja")
        SettingsStore.setPinnedSource(nil, in: defaults)
        #expect(
            SettingsStore.resolvedTarget(for: "お世話になっております。", in: defaults) == "zh-Hans")
    }

    @Test func clearingThePinGoesBackToAutomatic() {
        SettingsStore.setPinnedTarget("ja", in: defaults)
        SettingsStore.setPinnedTarget(nil, in: defaults)
        #expect(SettingsStore.pinnedTarget(in: defaults) == nil)
        SettingsStore.setTargetMapping(
            TargetMapping(targets: ["en": "ja"], fallback: "zh-Hans"), in: defaults)
        #expect(
            SettingsStore.resolvedTarget(for: "Could you send me the report?", in: defaults) == "ja")
    }

    @Test func theMappingPersists() {
        SettingsStore.setTargetMapping(
            TargetMapping(targets: ["en": "ja", "zh-Hans": "en"], fallback: "ja"), in: defaults)
        let reloaded = SettingsStore.targetMapping(in: defaults)
        #expect(reloaded.targets == ["en": "ja", "zh-Hans": "en"])
        #expect(reloaded.fallback == "ja")
    }

    /// The catalog is the system list, so it must offer far more than the four languages the app
    /// used to hardcode, and Chinese must keep both scripts.
    @Test func theCatalogComesFromTheSystemAndKeepsBothChineseScripts() {
        #expect(LanguageCatalog.targets.count > 100)
        #expect(LanguageCatalog.targets.contains { $0.tag == "zh-Hans" })
        #expect(LanguageCatalog.targets.contains { $0.tag == "zh-Hant" })
        #expect(LanguageCatalog.targets.contains { $0.tag == "en" })
        #expect(Set(LanguageCatalog.targets.map(\.tag)).count == LanguageCatalog.targets.count)
    }

    /// A language name follows the interface language, like everything else. It used to be the
    /// language's own name regardless of the interface; with a translated interface "日本語" reads as
    /// a foreign word to someone using the English app.
    ///
    /// The interface-language picker in settings is the deliberate exception, and names each language
    /// in itself so it can be recognised before the interface is switched.
    @Test func languagesAreNamedInTheInterfaceLanguage() {
        #expect(LanguageCatalog.name(for: "zh-Hans") == String(localized: "简体中文"))
        #expect(LanguageCatalog.name(for: "zh-Hant") == String(localized: "繁體中文"))
        #expect(LanguageCatalog.name(for: "en") == String(localized: "英语"))
        #expect(LanguageCatalog.name(for: "ja") == String(localized: "日语"))
        // A language the catalog does not carry falls back to the system's own name for it.
        #expect(!LanguageCatalog.name(for: "is").isEmpty)
    }

    /// Recognising a language before switching to it needs it named in itself, and printed verbatim so
    /// the catalog cannot translate it.
    @Test func theInterfaceLanguagePickerNamesEachLanguageInItself() {
        #expect(AppLanguage.simplifiedChinese.title == "简体中文")
        #expect(AppLanguage.traditionalChinese.title == "繁體中文")
        #expect(AppLanguage.english.title == "English")
        #expect(AppLanguage.japanese.title == "日本語")
        // "Follow the system" is not a language, so it does follow the interface.
        #expect(AppLanguage.system.title == String(localized: "跟随系统"))
    }

    /// A fresh install offers the three languages the product targets, not the whole system list.
    @Test func aFreshInstallSelectsTheProductLanguages() {
        #expect(SettingsStore.languages(in: defaults) == ["zh-Hans", "en", "ja"])
    }

    @Test func theSelectionPersistsAndKeepsItsOrder() {
        SettingsStore.setLanguages(["ja", "en", "ko"], in: defaults)
        #expect(SettingsStore.languages(in: defaults) == ["ja", "en", "ko"])
        #expect(
            LanguageCatalog.options(for: SettingsStore.languages(in: defaults)).map(\.tag) == [
                "ja", "en", "ko",
            ])
    }

    /// Removing a language must take its mapping rows with it, and move a fallback or a pin that was
    /// pointing at it, otherwise a control would sit on a value it cannot show.
    @Test func aLanguageLeavingTheSelectionAlsoLeavesTheSettings() {
        SettingsStore.setTargetMapping(
            TargetMapping(targets: ["en": "ja", "ja": "zh-Hans"], fallback: "ja"), in: defaults)
        SettingsStore.setPinnedTarget("ja", in: defaults)
        SettingsStore.setLanguages(["zh-Hans", "en"], in: defaults)
        // Both rows touched the removed 日本語, so both go; the fallback moves to the first kept one.
        #expect(SettingsStore.targetMapping(in: defaults).targets.isEmpty)
        #expect(SettingsStore.targetMapping(in: defaults).fallback == "zh-Hans")
        #expect(SettingsStore.pinnedTarget(in: defaults) == nil)
    }

    /// The source pin is restricted to the selected languages too.
    @Test func aSourceLeavingTheSelectionAlsoLeavesThePin() {
        SettingsStore.setPinnedSource("ja", in: defaults)
        SettingsStore.setLanguages(["zh-Hans", "en"], in: defaults)
        #expect(SettingsStore.pinnedSource(in: defaults) == nil)
    }

    @Test func rowsInsideTheSelectionSurviveARemoval() {
        SettingsStore.setTargetMapping(
            TargetMapping(targets: ["en": "ja", "ja": "zh-Hans"], fallback: "zh-Hans"), in: defaults)
        SettingsStore.setLanguages(["zh-Hans", "ja"], in: defaults)
        #expect(SettingsStore.targetMapping(in: defaults).targets == ["ja": "zh-Hans"])
        #expect(SettingsStore.targetMapping(in: defaults).fallback == "zh-Hans")
    }
}
