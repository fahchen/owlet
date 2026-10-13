import Foundation
import SwiftUI
import Testing

@testable import Owlet

@MainActor
struct PanelGlassEffectTests {
    @Test func preferencePersistsAcrossReopening() throws {
        let suite = "PanelGlassEffectTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let setting = AppStorage(
            wrappedValue: PanelGlassEffect.contrast, SettingsStore.panelGlassEffectKey, store: defaults)
        #expect(setting.wrappedValue == .contrast)
        #expect(setting.wrappedValue.glass == .regular)
        setting.wrappedValue = .transparent
        let reopened = AppStorage(
            wrappedValue: PanelGlassEffect.contrast, SettingsStore.panelGlassEffectKey, store: defaults)
        #expect(reopened.wrappedValue == .transparent)
        #expect(reopened.wrappedValue.glass == .clear)
        #expect(defaults.string(forKey: SettingsStore.panelGlassEffectKey) == "transparent")
        reopened.wrappedValue = .contrast
        #expect(defaults.string(forKey: SettingsStore.panelGlassEffectKey) == "contrast")
    }

    /// The hint's link is the app's only path to the intensity it cannot set, so the URL has to be the
    /// Appearance pane rather than, say, Accessibility: a typo here opens the wrong pane silently.
    @Test func theGlassHintOpensTheAppearancePane() throws {
        let url = try #require(SettingsStore.appearanceSettingsURL)
        #expect(url.scheme == "x-apple.systempreferences")
        #expect(url.absoluteString.contains("Appearance-Settings"))
    }
}
