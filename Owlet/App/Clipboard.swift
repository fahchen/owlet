import AppKit

/// Copying a result is one gesture in three places — the window footer, the panel footer and the
/// panel's ⌘⇧C — so it lives in one place.
@MainActor
enum Clipboard {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
