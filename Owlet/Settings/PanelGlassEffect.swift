import Foundation
import SwiftUI

enum PanelGlassEffect: String, CaseIterable {
    case transparent
    case contrast

    var title: LocalizedStringResource {
        switch self {
        case .transparent: "More Transparent"
        case .contrast: "Higher Contrast"
        }
    }

    var glass: Glass {
        self == .transparent ? .clear : .regular
    }

    /// Glass for the compact strip's small surfaces. The system frosts small glass less than large
    /// glass, so the strip reads more see-through than the expanded panel over the same text; a
    /// window-colored tint brings it level.
    var compactGlass: Glass { glass.tint(Self.compactTint) }

    /// The tint that levels the compact strip with the expanded panel. The shared surface lays it
    /// under the source bar instead of tinting the glass, so expanding never swaps the glass mid-frame.
    static let compactTint = Color(nsColor: .windowBackgroundColor).opacity(0.5)
}

extension SettingsStore {
    static let panelGlassEffectKey = "panel.glassEffect"

    /// System Settings › Appearance, where Liquid Glass and its intensity are chosen system-wide. The
    /// app can only pick between the two glass variants, so it points here instead of offering an
    /// intensity of its own.
    static let appearanceSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.Appearance-Settings.extension")
}
