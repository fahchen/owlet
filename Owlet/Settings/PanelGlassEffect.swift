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
}

extension SettingsStore {
    static let panelGlassEffectKey = "panel.glassEffect"
}
