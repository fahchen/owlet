import Foundation
import Testing

@testable import Owlet

/// 思考强度 defaults to 关闭: the app should not pay for reasoning nobody asked for. `.automatic`
/// keeps the provider's own default and is only used once the user picks it.
struct EffortTests {
    let suite = "EffortTests.\(UUID().uuidString)"
    var defaults: UserDefaults { UserDefaults(suiteName: suite)! }

    @Test func anUntouchedInstallAsksForNoThinking() {
        #expect(SettingsStore.effort(in: defaults) == .off)
    }

    @Test func aSavedEffortReadsBack() {
        defaults.set(EffortLevel.low.rawValue, forKey: SettingsStore.effortKey)
        #expect(SettingsStore.effort(in: defaults) == .low)
        defaults.set(EffortLevel.automatic.rawValue, forKey: SettingsStore.effortKey)
        #expect(SettingsStore.effort(in: defaults) == .automatic)
    }

    @Test func anUnknownEffortFallsBackToOff() {
        defaults.set("turbo", forKey: SettingsStore.effortKey)
        #expect(SettingsStore.effort(in: defaults) == .off)
    }
}
