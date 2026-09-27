import Foundation
import Testing

@testable import Owlet

/// The two 学习表达 switches start off, persist, and are controlled per operation.
struct LearningSwitchTests {
    let suite = "LearningSwitchTests.\(UUID().uuidString)"
    var defaults: UserDefaults { UserDefaults(suiteName: suite)! }

    @Test func bothSwitchesDefaultToOff() {
        #expect(!SettingsStore.autoRequestsLearning(for: .translate, in: defaults))
        #expect(!SettingsStore.autoRequestsLearning(for: .polish, in: defaults))
    }

    @Test func eachSwitchPersistsWithoutTouchingTheOther() {
        defaults.set(true, forKey: SettingsStore.learningKey(for: .translate))
        #expect(SettingsStore.autoRequestsLearning(for: .translate, in: defaults))
        #expect(!SettingsStore.autoRequestsLearning(for: .polish, in: defaults))

        defaults.set(true, forKey: SettingsStore.learningKey(for: .polish))
        defaults.set(false, forKey: SettingsStore.learningKey(for: .translate))
        #expect(!SettingsStore.autoRequestsLearning(for: .translate, in: defaults))
        #expect(SettingsStore.autoRequestsLearning(for: .polish, in: defaults))
    }

    /// A later read of the same suite sees what was saved, which is what a relaunch does.
    @Test func aSavedSwitchReadsBack() {
        defaults.set(true, forKey: SettingsStore.learningKey(for: .polish))
        let reopened = UserDefaults(suiteName: suite)!
        #expect(SettingsStore.autoRequestsLearning(for: .polish, in: reopened))
    }
}
