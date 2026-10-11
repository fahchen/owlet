import Foundation
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

    /// The tooltip: what the button does, then its key. The name is a catalog key, resolved here
    /// because a `String` is what the hover view shows.
    var tooltip: String { L10n.shared.string(title) + " " + keys }

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
    static let panelReplace = KeyHint(title: "Replace", key: .return, modifiers: .command)
    static let panelCopy = KeyHint(title: "Copy Result", key: "c", modifiers: .command)
    static let panelRetry = KeyHint(title: "Try Again", key: "r", modifiers: .command)
    static let panelLearn = KeyHint(title: "Study / Back", key: "l", modifiers: .command)
    static let panelCancel = KeyHint(title: "Stop / Close", key: .escape, modifiers: [])
    /// Read-only reading text claims Return on a selection; `LookupTextView.keyDown` handles it,
    /// and the 快捷键 page lists it.
    static let lookUp = KeyHint(title: "Look Up Selection", key: .return, modifiers: [])

    // The main window.
    static let process = KeyHint(title: "Process", key: .return, modifiers: .command)
    static let translateMode = KeyHint(title: "Translate", key: "1", modifiers: .command)
    static let polishMode = KeyHint(title: "Polish", key: "2", modifiers: .command)
    static let cancel = KeyHint(title: "Cancel", key: ".", modifiers: .command)
    static let learn = KeyHint(title: "Study / Back", key: "l", modifiers: .command)
    static let copy = KeyHint(title: "Copy", key: "c", modifiers: .command)
    static let previous = KeyHint(title: "Previous", key: .upArrow, modifiers: .command)
    static let next = KeyHint(title: "Next", key: .downArrow, modifiers: .command)
    static let delete = KeyHint(title: "Delete", key: .delete, modifiers: .command)

    /// The 快捷键 page's groups, by where the keys work.
    static let groups: [(title: String, keys: [KeyHint])] = [
        ("Panel", [panelReplace, panelCopy, panelRetry, panelLearn, panelCancel, lookUp]),
        ("Translate & Polish", [process, translateMode, polishMode, cancel, learn, copy]),
        ("Notebook and History", [previous, next, delete, copy, learn]),
    ]
}
