import AppKit
import Testing

@testable import Owlet

@MainActor
@Test func backgroundClickEndsOnlyEditingOutsideTheEditor() {
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
        styleMask: [.titled], backing: .buffered, defer: false)
    let root = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
    window.contentView = root
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
    let editor = NSTextView(frame: scroll.bounds)
    scroll.documentView = editor
    root.addSubview(scroll)
    #expect(window.makeFirstResponder(editor))
    #expect(!EndEditingOnBackgroundClick.shouldEndEditing(in: window, clicking: editor))
    #expect(!EndEditingOnBackgroundClick.shouldEndEditing(in: window, clicking: scroll))
    #expect(EndEditingOnBackgroundClick.shouldEndEditing(in: window, clicking: root))
    let button = NSButton(title: "Action", target: nil, action: nil)
    root.addSubview(button)
    #expect(EndEditingOnBackgroundClick.shouldEndEditing(in: window, clicking: button))
    #expect(!EndEditingOnBackgroundClick.shouldEndEditing(in: window, clicking: NSView()))
    let field = NSTextField()
    root.addSubview(field)
    #expect(window.makeFirstResponder(field))
    #expect(!EndEditingOnBackgroundClick.shouldEndEditing(in: window, clicking: field))
    #expect(window.makeFirstResponder(nil))
    #expect(!EndEditingOnBackgroundClick.shouldEndEditing(in: window, clicking: root))
}
