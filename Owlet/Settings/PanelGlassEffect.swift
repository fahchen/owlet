import SwiftUI

enum PanelGlassEffect: String, CaseIterable {
    case transparent
    case contrast

    var title: String {
        switch self {
        case .transparent: "更透明"
        case .contrast: "更高对比度"
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
}
