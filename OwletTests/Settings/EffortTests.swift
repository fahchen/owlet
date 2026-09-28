import Foundation
import Testing

@testable import Owlet

/// 思考强度 defaults to the provider's own setting and is only sent once the user picks one, so a
/// provider that does not accept the field is never sent it.
struct EffortTests {
    let suite = "EffortTests.\(UUID().uuidString)"
    var defaults: UserDefaults { UserDefaults(suiteName: suite)! }

    @Test func anUntouchedInstallKeepsTheProviderDefault() {
        #expect(SettingsStore.effort(in: defaults) == .automatic)
    }

    @Test func aSavedEffortReadsBack() {
        defaults.set(EffortLevel.low.rawValue, forKey: SettingsStore.effortKey)
        #expect(SettingsStore.effort(in: defaults) == .low)
    }

    @Test func anUnknownEffortFallsBackToAutomatic() {
        defaults.set("turbo", forKey: SettingsStore.effortKey)
        #expect(SettingsStore.effort(in: defaults) == .automatic)
    }
}
