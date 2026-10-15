import AppKit
import Testing

@testable import Owlet

@Suite struct SettingsWindowTests {
    /// The raise itself needs a window server, so this holds the finding rule it depends on: the
    /// settings scene's window is the only one whose class or identifier says so.
    @Test func theSettingsWindowIsFoundByItsClassOrIdentifier() {
        #expect(SettingsWindow.isSettingsWindow(identifier: "", className: "SwiftUI.SettingsWindow"))
        #expect(SettingsWindow.isSettingsWindow(identifier: "com_apple_SwiftUI_Settings_window", className: "NSWindow"))
        #expect(!SettingsWindow.isSettingsWindow(identifier: "", className: "Owlet.PanelWindow"))
        #expect(!SettingsWindow.isSettingsWindow(identifier: "main", className: "NSWindow"))
    }

    /// No windows means nothing to raise, and the app must not invent one.
    @Test @MainActor func noSettingsWindowIsReportedWhenThereIsNone() {
        #expect(SettingsWindow.existing(in: []) == nil)
    }
}
