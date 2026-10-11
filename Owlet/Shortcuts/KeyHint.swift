import SwiftUI

/// A fixed key the app claims: the one place its combination is written, so a button's binding, its
/// tooltip and its row on the 快捷键 page cannot drift apart.
struct KeyHint: Equatable, Sendable {
    let title: String
    let key: KeyEquivalent
    let modifiers: EventModifiers

    var shortcut: KeyboardShortcut { KeyboardShortcut(key, modifiers: modifiers) }

    /// The combination as a menu prints it: modifiers in the system order, then the key.
    var keys: String {
        let glyphs: [(EventModifiers, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        let prefix = glyphs.filter { modifiers.contains($0.0) }.map(\.1).joined()
        return prefix + Self.glyph(key)
    }

    /// The tooltip: what the button does, then its key.
    var tooltip: String { "\(title) \(keys)" }

    private static func glyph(_ key: KeyEquivalent) -> String {
        switch key {
        case .return: "↩"
        case .escape: "Esc"
        case .delete: "⌫"
        case .upArrow: "↑"
        case .downArrow: "↓"
        default: String(key.character).uppercased()
        }
    }

    static func == (lhs: KeyHint, rhs: KeyHint) -> Bool {
        lhs.title == rhs.title && lhs.keys == rhs.keys
    }
}

extension KeyHint {
    // The floating panel. `FloatingPanel.command(for:)` claims replace, copy, retry and Esc from its
    // own key monitor; 学习 is the learning button's shortcut.
    static let panelReplace = KeyHint(title: "替换", key: .return, modifiers: .command)
    static let panelCopy = KeyHint(title: "复制结果", key: "c", modifiers: .command)
    static let panelRetry = KeyHint(title: "重新处理", key: "r", modifiers: .command)
    static let panelLearn = KeyHint(title: "学习 / 返回", key: "l", modifiers: .command)
    static let panelCancel = KeyHint(title: "停止处理 / 关闭", key: .escape, modifiers: [])
    /// Read-only reading text claims Return on a selection; `LookupTextView.keyDown` handles it,
    /// and the 快捷键 page lists it.
    static let lookUp = KeyHint(title: "查询所选", key: .return, modifiers: [])

    // The main window.
    static let process = KeyHint(title: "处理", key: .return, modifiers: .command)
    static let translateMode = KeyHint(title: "翻译", key: "1", modifiers: .command)
    static let polishMode = KeyHint(title: "润色", key: "2", modifiers: .command)
    static let cancel = KeyHint(title: "取消处理", key: ".", modifiers: .command)
    static let learn = KeyHint(title: "学习 / 返回", key: "l", modifiers: .command)
    static let copy = KeyHint(title: "复制", key: "c", modifiers: .command)
    static let previous = KeyHint(title: "上一条", key: .upArrow, modifiers: .command)
    static let next = KeyHint(title: "下一条", key: .downArrow, modifiers: .command)
    static let delete = KeyHint(title: "删除", key: .delete, modifiers: .command)

    /// The 快捷键 page's groups, by where the keys work.
    static let groups: [(title: String, keys: [KeyHint])] = [
        ("浮窗", [panelReplace, panelCopy, panelRetry, panelLearn, panelCancel, lookUp]),
        ("翻译与润色", [process, translateMode, polishMode, cancel, learn, copy]),
        ("生词本与历史记录", [previous, next, delete, copy, learn]),
    ]
}
