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

    @Test func aPinnedLanguageOverridesTheMapping() {
        SettingsStore.setTargetMapping(
            TargetMapping(targets: ["en": "ja"], fallback: "zh-Hans"), in: defaults)
        SettingsStore.setPinnedTarget("zh-Hant", in: defaults)
        #expect(
            SettingsStore.resolvedTarget(for: "Could you send me the report?", in: defaults)
                == "zh-Hant")
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
}
