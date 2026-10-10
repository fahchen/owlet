import AppKit
import Testing

@testable import Owlet

/// The panel's keys, checked without a window: only these combinations are claimed.
@MainActor
struct FloatingPanelCommandTests {
    func event(_ keyCode: UInt16, _ flags: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
            context: nil, characters: "", charactersIgnoringModifiers: "",
            isARepeat: false, keyCode: keyCode)!
    }

    @Test func commandEnterReplaces() {
        #expect(FloatingPanel.command(for: event(36, .command)) == .replace)
        #expect(FloatingPanel.command(for: event(76, .command)) == .replace)
    }

    @Test func commandCCopies() {
        #expect(FloatingPanel.command(for: event(8, .command)) == .copy)
    }

    @Test func commandRRunsAgain() {
        #expect(FloatingPanel.command(for: event(15, .command)) == .retry)
    }

    @Test func plainEscapeCancels() {
        #expect(FloatingPanel.command(for: event(53, [])) == .cancel)
    }

    /// Anything else belongs to the panel's text field or to nothing at all.
    @Test func everyOtherKeyIsLeftAlone() {
        #expect(FloatingPanel.command(for: event(36, [])) == nil)
        #expect(FloatingPanel.command(for: event(8, [.command, .shift])) == nil)
        #expect(FloatingPanel.command(for: event(53, .command)) == nil)
        #expect(FloatingPanel.command(for: event(0, .command)) == nil)
        #expect(FloatingPanel.command(for: event(53, [.command, .shift])) == nil)
    }
}
