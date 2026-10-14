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
    /// text is never typed into at all, because the keystroke would land somewhere else. When the
    /// source was the whole focused field there is no selection, so the field is selected with ⌘A
    /// before the paste; if that cannot be confirmed, nothing is typed.
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

    /// The element's selected range, read straight through the accessibility API: the whole-field
    /// write-back has to see that ⌘A landed before it presses paste. A field that publishes no range
    /// but does publish its selected text is read that way instead; the assumed start is the field's
    /// beginning, so only a selection as long as the whole text counts as select-all.
    static func selectedRange(of element: AXUIElement) -> SelectedRange? {
        timed(element)
        var value: AnyObject?
        if AXUIElementCopyAttributeValue(
            element, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
            let value, CFGetTypeID(value) == AXValueGetTypeID()
        {
            let axValue = unsafeDowncast(value, to: AXValue.self)
            var range = CFRange()
            if AXValueGetType(axValue) == .cfRange, AXValueGetValue(axValue, .cfRange, &range) {
                return SelectedRange(location: range.location, length: range.length)
            }
        }
        guard let selected = attribute(kAXSelectedTextAttribute, of: element) as? String,
            isNotBlank(selected)
        else { return nil }
        return SelectedRange(location: 0, length: selected.utf16.count)
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
    /// keystroke the app ignored is not mistaken for a replacement. When the source was the whole
    /// field there is nothing selected to paste over, so ⌘A runs first and must be seen to select the
    /// whole text: pasting at the insertion point would append the result, which is the wrong result
    /// this path exists to prevent.
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
        if selection.wholeField,
            !(await selectWholeField(selection.element, whole: before?.utf16.count, seams: seams))
        {
            seams.pasteboard.restore(saved)
            return .refused
        }
        seams.press(.paste)
        // The app reads the pasteboard after the keystroke, so nothing may overwrite it until it has.
        try? await Task.sleep(for: seams.settle / 2)
        // An element that does not report its text cannot be checked, and the paste went to wherever
        // the app really has focus rather than to this captured element, so unreadable is not failure.
        // The whole-field result has to be exactly the pasted text: anything else means the paste did
        // not cover the field, and calling that success would hide an append.
        let landed: @MainActor () -> Bool = {
            let after = seams.value(selection.element)
            return selection.wholeField ? after == text : (before == nil || after != before)
        }
        var applied = landed()
        for _ in 0..<pastePolls where !applied {
            try? await Task.sleep(for: seams.settle / 2 / pastePolls)
            applied = landed()
        }
        seams.pasteboard.restore(saved)
        return applied ? .pasted : .refused
    }

    /// Asks the focused element to select everything and waits for it to report a selection covering
    /// the whole field. ⌘A is only a request: a field that ignores it, or selects only part, must not
    /// reach the paste, because that paste would land at the insertion point and append.
    @MainActor private static func selectWholeField(
        _ element: AXUIElement, whole: Int?, seams: WritebackSeams
    ) async -> Bool {
        seams.press(.selectAll)
        for _ in 0..<selectAllPolls {
            if let range = seams.selectedRange(element), range.location == 0, range.length > 0,
                whole == nil || range.length == whole
            {
                return true
            }
            try? await Task.sleep(for: seams.settle / 2 / selectAllPolls)
        }
        return false
    }

    /// Twelve polls inside the settle window: long enough for a busy app to answer ⌘A, short enough
    /// that the paste is not held back long when the field ignores it.
    private static let selectAllPolls = 12

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

    /// Real shortcut press; the caller owns placing the result on the pasteboard.
    static func pressShortcut(_ shortcut: WritebackShortcut) {
        switch shortcut {
        case .selectAll: pressCommandA()
        case .paste: pressCommandV()
        }
    }

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

    /// Synthetic ⌘A; keycode 0 is the A key in every layout.
    static func pressCommandA() { postCommand(keyCode: aKey) }

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

    /// Keycode 0 is the A key, 8 the C key and 9 the V key, in every layout.
    static let aKey: CGKeyCode = 0
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
