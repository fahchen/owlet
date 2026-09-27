import AppKit
import ApplicationServices
import Synchronization

enum SelectionError: Error, Equatable {
    case permission
    case unreadable
    /// Secure text fields are never read.
    case secure
}

/// How a write-back reached the target app.
enum ReplaceOutcome: Equatable {
    /// The result was pasted over the selection and the selection is seen to have changed.
    case pasted
    /// The selection cannot hold text at all, so nothing was typed: only the result can be copied.
    case unwritable
    /// Nothing changed: no running owning app, no accessibility permission, the app would not come
    /// forward, or the paste landed nowhere.
    case refused
}

/// Selected text plus the element and app it came from, captured before the panel opens.
struct Selection {
    let text: String
    let element: AXUIElement
    let app: NSRunningApplication?
    /// Range of the selection inside `element`, kept only so the panel can be placed under it; nil
    /// when the app reports none, which costs placement but not the translation.
    let range: SelectedRange?
    /// Selection rect in AX coordinates (top-left origin, y down); nil when not requested or unavailable.
    var bounds: CGRect? = nil
}

/// A selection's offset and length, as the owning app reported them.
struct SelectedRange: Equatable {
    let location: Int
    let length: Int
}

/// Reads the selection of the focused element through the Accessibility API.
enum SelectionBridge {
    static let permissionSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")

    /// Copies one AX attribute; injectable so tests can observe which attributes are read.
    typealias Reader = (AXUIElement, String) -> AnyObject?

    /// String behind a WebKit text marker range; injectable so tests never send real AX messages.
    typealias MarkerString = @Sendable (AXUIElement, AnyObject) -> String?

    /// Presses ⌘C and returns what the app copied, or nil when nothing new arrived; injectable so
    /// tests never post real key events.
    typealias CopySelection = () -> String?

    /// Presses ⌘V; injectable so tests never post real key events.
    typealias PasteSelection = () -> Void

    /// Pasteboard seam for the copy and paste fallbacks, so tests never touch the real pasteboard.
    struct Pasteboard: Sendable {
        var changeCount: @Sendable () -> Int
        var string: @Sendable () -> String?
        var write: @Sendable (String) -> Void
        var snapshot: @Sendable () -> [[NSPasteboard.PasteboardType: Data]]
        var restore: @Sendable ([[NSPasteboard.PasteboardType: Data]]) -> Void

        /// The system pasteboard; every call reads `NSPasteboard.general` fresh so no handle is shared.
        static let system = Pasteboard(
            changeCount: { NSPasteboard.general.changeCount },
            string: { NSPasteboard.general.string(forType: .string) },
            write: { text in
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
            },
            snapshot: { SelectionBridge.snapshot(NSPasteboard.general) },
            restore: { SelectionBridge.restore($0, to: NSPasteboard.general) })
    }

    /// Effect seams for one write-back, so tests can drive the decision without accessibility
    /// messages, a real pasteboard or real key events.
    struct WritebackSeams {
        var trusted: () -> Bool = { AXIsProcessTrusted() }
        /// Whether the selection sits in something that can hold editable text; nil when the app does
        /// not say, which is not evidence that it cannot.
        var editable: @MainActor (AXUIElement) -> Bool? = {
            SelectionBridge.isEditable(role: SelectionBridge.role(of: $0))
        }
        /// The element's text, read before and after the paste to tell a replacement that landed
        /// from one the app ignored.
        var value: @MainActor (AXUIElement) -> String? = { SelectionBridge.value(of: $0) }
        var activate: @MainActor (NSRunningApplication) async -> Bool = {
            await SelectionBridge.bringForward($0)
        }
        var press: PasteSelection = SelectionBridge.pasteSelection()
        var pasteboard: Pasteboard = .system
        /// How long the system is given to move the keyboard off the panel before the keystroke.
        var handover: Duration = .milliseconds(150)
        /// How long the target app is given to apply the paste before the result is called unwritten.
        var settle: Duration = .milliseconds(600)
    }

    /// AX messaging timeout per call and total budget from trigger; engineering values. The
    /// budget has to cover a browser or Electron app building its accessibility tree on request,
    /// which is the normal case when the selection lives in a web page.
    static let messagingTimeout: Float = 0.15
    static let budget: Duration = .milliseconds(900)
    /// How far up from the focused element and how many nodes a search may visit.
    static let ancestorLimit = 8
    static let nodeLimit = 400
    private static let worker = SerialLatest()

    /// Reads the selection off the main thread; `completion` runs on main, only if the
    /// frontmost app is still the one read. Past `budget` AX steps are skipped. `bounds` also
    /// reads the selection rect, costing one more AX call.
    @MainActor static func read(
        bounds wantsBounds: Bool = false,
        completion: @escaping @MainActor (Result<Selection, SelectionError>) -> Void
    ) {
        guard AXIsProcessTrusted() else { return completion(.failure(.permission)) }
        guard let app = NSWorkspace.shared.frontmostApplication,
            app.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else { return completion(.failure(.unreadable)) }
        let pid = app.processIdentifier
        let deadline = ContinuousClock.now + budget
        worker.submit {
            let appElement = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(appElement, messagingTimeout)
            // Electron builds its AX tree only on request; unsupported apps just return an
            // error, which is ignored. The tree may not be ready yet: no wait, user retriggers.
            AXUIElementSetAttributeValue(
                appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            let bounded: Reader = { element, attribute in
                ContinuousClock.now < deadline ? copy(element, attribute) : nil
            }
            // AX handles stay with this one operation; handed to main exactly once.
            nonisolated(unsafe) let result = capture(
                appElement, copy: bounded, copySelection: copySelection())
            let rect: CGRect? =
                if wantsBounds, ContinuousClock.now < deadline, case .success(let captured) = result,
                    let range = captured.range
                {
                    selectionBounds(captured.element, range: range)
                } else {
                    nil
                }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
                        return completion(.failure(.unreadable))
                    }
                    completion(
                        result.map {
                            Selection(
                                text: $0.text, element: $0.element, app: app, range: $0.range, bounds: rect)
                        })
                }
            }
        }
    }

    /// Reads the focused element of `appElement`, checking the secure subrole before any text is
    /// touched, then searches outwards for the selection and falls back to copying it with ⌘C when
    /// the search finds nothing. `copySelection` therefore only runs once the field is known not to
    /// be secure.
    static func capture(
        _ appElement: AXUIElement, copy: Reader,
        marker: MarkerString = SelectionBridge.markerString,
        copySelection: CopySelection? = nil
    ) -> Result<(text: String, element: AXUIElement, range: SelectedRange?), SelectionError> {
        guard let element = focusedElement(appElement, copy: copy) else {
            return .failure(.unreadable)
        }
        let subrole = copy(element, kAXSubroleAttribute)
        if let subrole, !(subrole is String) { return .failure(.unreadable) }
        if subrole as? String == kAXSecureTextFieldSubrole { return .failure(.secure) }
        if let found = search(element, copy: copy, marker: marker) {
            return classify(trusted: true, subrole: nil, text: found.text).map { text in
                (text, found.element, selectedRange(found.element, copy: copy))
            }
        }
        guard let copied = copySelection?() else { return .failure(.unreadable) }
        return classify(trusted: true, subrole: nil, text: copied).map { text in
            (text, element, selectedRange(element, copy: copy))
        }
    }

    /// Where a selection can hide, in the order worth paying for: the focused element itself
    /// (text fields, text views, browsers that answer `AXSelectedText`), then its ancestors (a
    /// web area selected from inside its content), then the focused element's subtree and finally
    /// the whole window — which is where a PDF viewer or a web page puts its text layer.
    static func search(
        _ focused: AXUIElement, copy: Reader, marker: MarkerString,
        ancestorLimit: Int = SelectionBridge.ancestorLimit,
        nodeLimit: Int = SelectionBridge.nodeLimit
    ) -> (element: AXUIElement, text: String)? {
        if let text = selection(focused, copy: copy, marker: marker) { return (focused, text) }
        var element = focused
        for _ in 0..<ancestorLimit {
            guard let parent = copy(timed(element), kAXParentAttribute),
                CFGetTypeID(parent) == AXUIElementGetTypeID()
            else { break }
            element = unsafeDowncast(parent, to: AXUIElement.self)
            if let text = selection(element, copy: copy, marker: marker) { return (element, text) }
        }
        for root in [focused, window(of: focused, copy: copy)].compactMap({ $0 }) {
            let children = (copy(root, kAXChildrenAttribute) as? [AXUIElement]) ?? []
            if let found = descend(children, copy: copy, marker: marker, limit: nodeLimit) {
                return found
            }
        }
        return nil
    }

    /// Breadth-first walk of `roots`, bounded by `limit` nodes; the bounded reader ends it early
    /// once the read budget is gone, so a deep tree can never stall the trigger.
    private static func descend(
        _ roots: [AXUIElement], copy: Reader, marker: MarkerString, limit: Int
    ) -> (element: AXUIElement, text: String)? {
        var queue = roots
        var visited = 0
        while !queue.isEmpty, visited < limit {
            let element = queue.removeFirst()
            visited += 1
            if let text = selection(element, copy: copy, marker: marker) { return (element, text) }
            if let children = copy(element, kAXChildrenAttribute) as? [AXUIElement] {
                queue.append(contentsOf: children)
            }
        }
        return nil
    }

    /// Selected text of one element, or nil: secure fields are skipped before any text is read,
    /// and a blank selection does not count as a selection.
    private static func selection(_ element: AXUIElement, copy: Reader, marker: MarkerString)
        -> String?
    {
        timed(element)
        if copy(element, kAXSubroleAttribute) as? String == kAXSecureTextFieldSubrole {
            return nil
        }
        if let text = copy(element, kAXSelectedTextAttribute) as? String, isNotBlank(text) {
            return text
        }
        // WebKit answers a page selection only as a text marker range.
        if let range = copy(element, kAXSelectedTextMarkerRangeAttribute),
            let text = marker(element, range), isNotBlank(text)
        {
            return text
        }
        return nil
    }

    /// Every element gets the per-call timeout before it is messaged: a child reference arrives
    /// with the process default, which can be seconds.
    @discardableResult private static func timed(_ element: AXUIElement) -> AXUIElement {
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        return element
    }

    /// String behind a WebKit text marker range; the only way to read a selection in Safari.
    static let markerString: MarkerString = { element, range in
        var value: AnyObject?
        guard
            AXUIElementCopyParameterizedAttributeValue(
                element, kAXStringForTextMarkerRangeParameterizedAttribute as CFString,
                range as CFTypeRef, &value) == .success
        else { return nil }
        return value as? String
    }

    private static func isNotBlank(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The window an element belongs to; nil when the app does not answer.
    private static func window(of element: AXUIElement, copy: Reader) -> AXUIElement? {
        guard let value = copy(timed(element), kAXWindowAttribute),
            CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

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

    private static func snapshot(_ pasteboard: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        (pasteboard.pasteboardItems ?? []).map { item in
            var copies: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { copies[type] = data }
            }
            return copies
        }
    }

    private static func restore(
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

    /// Screen rect of the selected range via `kAXBoundsForRangeParameterizedAttribute`; nil
    /// without a range or when the app reports nothing usable.
    private static func selectionBounds(_ element: AXUIElement, range: SelectedRange) -> CGRect? {
        var range = CFRange(location: range.location, length: range.length)
        guard let rangeValue = AXValueCreate(.cfRange, &range) else { return nil }
        var value: AnyObject?
        guard
            AXUIElementCopyParameterizedAttributeValue(
                element, kAXBoundsForRangeParameterizedAttribute as CFString, rangeValue, &value) == .success,
            let value, CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        let axValue = unsafeDowncast(value, to: AXValue.self)
        var rect = CGRect.zero
        guard AXValueGetType(axValue) == .cgRect, AXValueGetValue(axValue, .cgRect, &rect),
            rect.width > 0 || rect.height > 0
        else { return nil }
        return rect
    }

    /// Selection range of an element; the range only places the panel, so an app that reports none
    /// is not a failure and nothing else is read to describe the selection.
    private static func selectedRange(_ element: AXUIElement, copy: Reader) -> SelectedRange? {
        guard let value = copy(timed(element), kAXSelectedTextRangeAttribute),
            CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        let axValue = unsafeDowncast(value, to: AXValue.self)
        var range = CFRange()
        guard AXValueGetType(axValue) == .cfRange, AXValueGetValue(axValue, .cfRange, &range) else {
            return nil
        }
        return SelectedRange(location: range.location, length: range.length)
    }

    static func classify(trusted: Bool, subrole: String?, text: String?)
        -> Result<String, SelectionError>
    {
        guard trusted else { return .failure(.permission) }
        guard subrole != kAXSecureTextFieldSubrole else { return .failure(.secure) }
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(.unreadable)
        }
        return .success(text)
    }

    private static func focusedElement(_ appElement: AXUIElement, copy: Reader) -> AXUIElement? {
        guard let value = copy(appElement, kAXFocusedUIElementAttribute),
            CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private static func copy(_ element: AXUIElement, _ attribute: String) -> AnyObject? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
        else { return nil }
        return value
    }
}

/// Serial queue that keeps at most one running job and one latest pending; a newer
/// submit replaces the pending one so rapid triggers never queue up.
final class SerialLatest: Sendable {
    private let queue = DispatchQueue(label: "owlet.selection")
    private let state = Mutex<(running: Bool, pending: (@Sendable () -> Void)?)>((false, nil))

    func submit(_ job: @escaping @Sendable () -> Void) {
        let start = state.withLock { state in
            if state.running {
                state.pending = job
                return false
            }
            state.running = true
            return true
        }
        if start { run(job) }
    }

    private func run(_ job: @escaping @Sendable () -> Void) {
        queue.async {
            job()
            let next = self.state.withLock { state in
                let next = state.pending
                state.pending = nil
                state.running = next != nil
                return next
            }
            if let next { self.run(next) }
        }
    }
}
