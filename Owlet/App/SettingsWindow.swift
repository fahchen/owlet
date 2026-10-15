import AppKit

/// Opening settings from a menu is a two-step job. The SwiftUI `Settings` scene creates its window on
/// the first call, but a later call does nothing when that window is already open behind something
/// else, so every programmatic entry point activates the app and raises the window itself. ⌘, goes
/// through the system's own item and does not need this.
enum SettingsWindow {
    /// Whether one window belongs to the settings scene. SwiftUI publishes no identifier we can rely
    /// on, so the class name and the identifier are both accepted; the rule is pure so the tests can
    /// hold it without a window server.
    static func isSettingsWindow(identifier: String, className: String) -> Bool {
        className.contains("Settings") || identifier.contains("Settings")
    }

    @MainActor static func existing(in windows: [NSWindow]) -> NSWindow? {
        windows.first {
            isSettingsWindow(
                identifier: $0.identifier?.rawValue ?? "", className: String(describing: type(of: $0)))
        }
    }

    /// Shows the settings window and brings it to the front, whether it is closed, behind another app
    /// or behind our own floating panel.
    @MainActor static func show(_ openSettings: () -> Void) {
        NSApp.activate()
        openSettings()
        // The scene may create the window on a later turn of the run loop, so the raise is deferred
        // once rather than assuming the window exists already.
        DispatchQueue.main.async {
            existing(in: NSApp.windows)?.makeKeyAndOrderFront(nil)
        }
    }
}
