import Carbon.HIToolbox
import Foundation
import Testing

@testable import Owlet

@MainActor
struct ShortcutControllerTests {
    // Isolated suite per test instance; never touches .standard.
    let suite = "ShortcutControllerTests.\(UUID().uuidString)"
    var defaults: UserDefaults { UserDefaults(suiteName: suite)! }

    @Test func unsetByDefault() {
        #expect(ShortcutController(defaults: defaults).translate == nil)
    }

    @Test func savePersistsAndClearRemoves() {
        let shortcut = Shortcut(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(cmdKey | optionKey))
        SettingsStore.setShortcut(shortcut, forKey: SettingsStore.translateShortcutKey, in: defaults)
        #expect(ShortcutController(defaults: defaults).translate == shortcut)

        SettingsStore.setShortcut(nil, forKey: SettingsStore.translateShortcutKey, in: defaults)
        #expect(ShortcutController(defaults: defaults).translate == nil)
        defaults.removePersistentDomain(forName: suite)
    }

    @Test func displayString() {
        var s = Shortcut(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(cmdKey | shiftKey))
        s.keyLabel = "T"
        #expect(s.displayString == "⇧⌘T")
    }

    @Test func conflictWithOtherAction() {
        let shortcut = Shortcut(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(cmdKey | optionKey))
        SettingsStore.setShortcut(shortcut, forKey: SettingsStore.translateShortcutKey, in: defaults)
        let controller = ShortcutController(defaults: defaults)
        #expect(controller.conflict(shortcut, for: .translateReplace) == .translate)
        #expect(controller.conflict(shortcut, for: .translate) == nil)
        controller.set(shortcut, for: .translateReplace)
        #expect(controller.shortcuts[.translateReplace] == nil)
        #expect(controller.registrationError != nil)
        defaults.removePersistentDomain(forName: suite)
    }
}
