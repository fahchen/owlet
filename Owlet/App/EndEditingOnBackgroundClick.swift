import AppKit
import SwiftUI

/// Ends native editing without consuming the click that should reach another control.
struct EndEditingOnBackgroundClick: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) {
            [weak view] event in
            MainActor.assumeIsolated {
                guard let window = view?.window, event.window === window,
                    let root = window.contentView?.superview
                else { return }
                let hit = root.hitTest(root.convert(event.locationInWindow, from: nil))
                if Self.shouldEndEditing(in: window, clicking: hit) {
                    window.makeFirstResponder(nil)
                }
            }
            return event
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        if let monitor = coordinator.monitor { NSEvent.removeMonitor(monitor) }
        coordinator.monitor = nil
    }

    final class Coordinator {
        var monitor: Any?
    }

    static func shouldEndEditing(in window: NSWindow, clicking hit: NSView?) -> Bool {
        guard let editor = window.firstResponder as? NSTextView, editor.isEditable,
            let hit, hit.window === window
        else { return false }
        if hit === editor || hit.isDescendant(of: editor) { return false }
        if let scroll = editor.enclosingScrollView,
            hit === scroll || hit.isDescendant(of: scroll)
        {
            return false
        }
        if editor.isFieldEditor, let field = editor.delegate as? NSView,
            hit === field || hit.isDescendant(of: field)
        {
            return false
        }
        return true
    }
}
