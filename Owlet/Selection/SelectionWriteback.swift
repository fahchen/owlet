import AppKit
import ApplicationServices

extension SelectionBridge {
    /// Writes `text` over the selection once using the real accessibility API and pasteboard.
    @MainActor static func replace(_ selection: Selection, with text: String) async -> ReplaceOutcome {
        await replace(selection, with: text, seams: WritebackSeams())
    }

    /// Writes `text` over the selection once, by pasting: the accessibility write is deliberately
    /// not used, because an app can accept that write, change nothing, and report success — which is
    /// how a replacement used to disappear without a word. A selection that provably cannot hold
    /// text is never typed into at all, because the keystroke would land somewhere else.
    @MainActor static func replace(
        _ selection: Selection, with text: String,
        seams: WritebackSeams
    ) async -> ReplaceOutcome {
        guard seams.trusted() else { return .refused }
        // The app that owned the selection, not the frontmost app: the panel is key while the
        // user clicks, so the frontmost app can be Owlet itself.
        guard let app = selection.app ?? NSWorkspace.shared.frontmostApplication,
            !app.isTerminated
        else { return .refused }
        // Only a provable read-only selection is refused: an app that reports no role at all is not
        // evidence that the field is read-only.
        guard seams.editable(selection.element) != false else { return .unwritable }
        // Replacing text with itself cannot be observed and needs no change at all.
        if text == selection.text { return .pasted }
        return await paste(text, to: app, selection: selection, seams: seams)
    }

    /// The element's accessibility role; nil when the app does not report one.
    static func role(of element: AXUIElement) -> String? {
        attribute(kAXRoleAttribute, of: element) as? String
    }

    /// The element's text; nil when the app does not report it.
    static func value(of element: AXUIElement) -> String? {
        attribute(kAXValueAttribute, of: element) as? String
    }

    /// Roles that hold editable text. Page text, a PDF or an image cannot take a paste, and typing at
    /// one would send the keystroke somewhere the user did not choose.
    private static let editableRoles: Set<String> = [
        kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole,
    ]

    /// nil when the app reports no role, which is not evidence of a read-only field.
    static func isEditable(role: String?) -> Bool? {
        guard let role else { return nil }
        return editableRoles.contains(role)
    }

    /// One attribute of one element, read straight through with no searching.
    private static func attribute(_ name: String, of element: AXUIElement) -> AnyObject? {
        timed(element)
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    /// Puts `text` on the pasteboard, brings `app` forward and presses ⌘V, then hands the previous
    /// pasteboard back. The paste is only reported once the element's text is seen to change, so a
    /// keystroke the app ignored is not mistaken for a replacement.
    @MainActor private static func paste(
        _ text: String, to app: NSRunningApplication, selection: Selection, seams: WritebackSeams
    ) async -> ReplaceOutcome {
        let saved = seams.pasteboard.snapshot()
        let before = seams.value(selection.element)
        seams.pasteboard.write(text)
        guard await seams.activate(app) else {
            seams.pasteboard.restore(saved)
            return .refused
        }
        // The keystroke follows the keyboard, and the panel only just let it go, so the app is given
        // a moment to own it before the press.
        try? await Task.sleep(for: seams.handover)
        seams.press()
        // The app reads the pasteboard after the keystroke, so nothing may overwrite it until it has.
        try? await Task.sleep(for: seams.settle / 2)
        // An element that does not report its text cannot be checked, and the paste went to wherever
        // the app really has focus rather than to this captured element, so unreadable is not failure.
        var applied = before == nil || seams.value(selection.element) != before
        for _ in 0..<pastePolls where !applied {
            try? await Task.sleep(for: seams.settle / 2 / pastePolls)
            applied = seams.value(selection.element) != before
        }
        seams.pasteboard.restore(saved)
        return applied ? .pasted : .refused
    }

    /// Twelve polls inside the settle window: long enough for a busy app, short enough to keep the
    /// clipboard held only briefly.
    private static let pastePolls = 12

    /// Brings `app` forward and waits for it to be the frontmost application. Being frontmost is not
    /// proof that an app owns the keyboard — a non-activating panel holds it while it is up — so the
    /// app is always asked to come forward rather than skipped when it already looks frontmost.
    @MainActor static func bringForward(
        _ app: NSRunningApplication,
        frontmost: @MainActor () -> pid_t? = {
            NSWorkspace.shared.frontmostApplication?.processIdentifier
        },
        activate: @MainActor (NSRunningApplication) -> Bool = { $0.activate() }
    ) async -> Bool {
        _ = activate(app)
        for _ in 0..<25 {
            if frontmost() == app.processIdentifier { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    /// Real ⌘V press; the caller owns placing the result on the pasteboard.
    static func pasteSelection() -> PasteSelection { pressCommandV }

    /// Real ⌘C read: keeps the previous pasteboard, presses ⌘C, waits briefly for the pasteboard to
    /// change and hands the previous contents back; nil and no copy when nothing changed.
    static func copySelection(
        pasteboard: Pasteboard = .system,
        press: @escaping () -> Void = pressCommandC,
        sleep: @escaping () -> Void = { Thread.sleep(forTimeInterval: 0.02) }
    ) -> CopySelection {
        {
            let before = pasteboard.changeCount()
            let saved = pasteboard.snapshot()
            press()
            var copied: String?
            for _ in 0..<copyAttempts {
                if pasteboard.changeCount() != before, let text = pasteboard.string(), isNotBlank(text) {
                    copied = text
                    break
                }
                sleep()
            }
            pasteboard.restore(saved)
            return copied
        }
    }

    /// Twenty 20 ms polls: a slow app yields nothing and the worker never waits longer than 400 ms.
    private static let copyAttempts = 20

    /// Synthetic ⌘C; keycode 8 is the C key in every layout.
    static func pressCommandC() { postCommand(keyCode: cKey) }

    /// Synthetic ⌘V; keycode 9 is the V key in every layout.
    static func pressCommandV() { postCommand(keyCode: vKey) }

    /// The four events a Command-modified press is made of: an app that watches the modifier state
    /// rather than the event flags only sees a real press when Command itself goes down and up.
    /// Separated out so the sequence can be checked without a real keystroke.
    static func commandSequence(for keyCode: CGKeyCode)
        -> [(code: CGKeyCode, isDown: Bool, flags: CGEventFlags)]
    {
        [
            (leftCommandKey, true, .maskCommand),
            (keyCode, true, .maskCommand),
            (keyCode, false, .maskCommand),
            (leftCommandKey, false, []),
        ]
    }

    /// Posts one Command-modified press as that sequence, at the HID tap so it arrives exactly as a
    /// typed one would.
    private static func postCommand(keyCode: CGKeyCode) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for step in commandSequence(for: keyCode) {
            guard
                let event = CGEvent(
                    keyboardEventSource: source, virtualKey: step.code, keyDown: step.isDown)
            else { continue }
            event.flags = step.flags
            event.post(tap: .cghidEventTap)
        }
    }

    /// Left Command, which every layout puts in the same place.
    static let leftCommandKey: CGKeyCode = 55

    /// Keycode 8 is the C key and 9 the V key, in every layout.
    static let cKey: CGKeyCode = 8
    static let vKey: CGKeyCode = 9

    static func snapshot(_ pasteboard: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        (pasteboard.pasteboardItems ?? []).map { item in
            var copies: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { copies[type] = data }
            }
            return copies
        }
    }

    static func restore(
        _ saved: [[NSPasteboard.PasteboardType: Data]], to pasteboard: NSPasteboard
    ) {
        pasteboard.clearContents()
        guard !saved.isEmpty else { return }
        pasteboard.writeObjects(
            saved.map { copies in
                let item = NSPasteboardItem()
                for (type, data) in copies { item.setData(data, forType: type) }
                return item
            })
    }

}
