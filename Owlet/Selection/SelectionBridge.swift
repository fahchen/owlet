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
    /// The element took the text directly through the accessibility API.
    case written
    /// The element refuses direct writes (non-editable text in a web page or PDF), so the text
    /// was pasted over the selection with a synthesized ⌘V.
    case pasted
    /// Nothing changed: the selection moved, or its element could not be reached.
    case refused
}

/// Selected text plus the element and app it came from, captured before the panel opens.
struct Selection {
    let text: String
    let element: AXUIElement
    let app: NSRunningApplication?
    let source: Source
    /// Selection rect in AX coordinates (top-left origin, y down); nil when not requested or unavailable.
    var bounds: CGRect? = nil
}

/// Comparable facts about where a selection lives, re-checked before writing back.
struct Source: Equatable {
    let pid: pid_t?
    let document: String?
    let text: String?
    let location: Int?
    let length: Int?
}

/// Reads the selection of the focused element through the Accessibility API.
enum SelectionBridge {
    static let permissionSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")

    /// Copies one AX attribute; injectable so tests can observe which attributes are read.
    typealias Reader = (AXUIElement, String) -> AnyObject?

    /// String behind a WebKit text marker range; injectable so tests never send real AX messages.
    typealias MarkerString = @Sendable (AXUIElement, AnyObject) -> String?

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
            nonisolated(unsafe) let result = capture(appElement, pid: pid, copy: bounded)
            let rect: CGRect? =
                if wantsBounds, ContinuousClock.now < deadline, case .success(let captured) = result {
                    selectionBounds(captured.element, source: captured.source)
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
                                text: $0.text, element: $0.element, app: app, source: $0.source, bounds: rect)
                        })
                }
            }
        }
    }

    /// Reads the focused element of `appElement`, checking the secure subrole before any text is
    /// touched, then searches outwards for the selection and reuses the single text read for
    /// `Source.text`.
    static func capture(
        _ appElement: AXUIElement, pid: pid_t, copy: Reader,
        marker: MarkerString = SelectionBridge.markerString
    ) -> Result<(text: String, element: AXUIElement, source: Source), SelectionError> {
        guard let element = focusedElement(appElement, copy: copy) else {
            return .failure(.unreadable)
        }
        let subrole = copy(element, kAXSubroleAttribute)
        if let subrole, !(subrole is String) { return .failure(.unreadable) }
        if subrole as? String == kAXSecureTextFieldSubrole { return .failure(.secure) }
        guard let found = search(element, copy: copy, marker: marker) else {
            return .failure(.unreadable)
        }
        return classify(trusted: true, subrole: nil, text: found.text).map { text in
            (text, found.element, source(found.element, pid: pid, text: text, copy: copy))
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

    /// Writes `text` over the original selection once, preferring a direct accessibility write and
    /// falling back to a paste when the element refuses one. Refuses without writing if the
    /// selection moved in the meantime.
    @MainActor static func replace(_ selection: Selection, with text: String) async -> ReplaceOutcome {
        guard AXIsProcessTrusted() else { return .refused }
        // The app that owned the selection, not the frontmost app: the panel is key while the
        // user clicks, so the frontmost app can be Owlet itself.
        guard let app = selection.app ?? NSWorkspace.shared.frontmostApplication else {
            return .refused
        }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, messagingTimeout)
        guard let element = focusedElement(appElement, copy: copy) else {
            return .refused
        }
        let direct = copy(element, kAXSubroleAttribute) as? String
        if direct == kAXSecureTextFieldSubrole { return .refused }
        let current = source(
            element, pid: app.processIdentifier,
            text: copy(element, kAXSelectedTextAttribute) as? String, copy: copy)
        let sameElement = CFEqual(element, selection.element)
        if canReplace(original: selection.source, current: current, sameElement: sameElement),
            AXUIElementSetAttributeValue(
                element, kAXSelectedTextAttribute as CFString, text as CFString) == .success
        {
            return .written
        }
        guard canPaste(original: selection.source, current: current, sameElement: sameElement) else {
            return .refused
        }
        return await paste(text, to: app) ? .pasted : .refused
    }

    /// Pasting may only go ahead when the same element still holds the same text. A non-editable
    /// selection has no range to compare, so the text itself is the whole check.
    static func canPaste(original: Source, current: Source, sameElement: Bool) -> Bool {
        sameElement && original.text.map(isNotBlank) == true && original.text == current.text
    }

    /// Puts `text` on the clipboard, brings `app` forward and presses ⌘V, then hands the previous
    /// clipboard back once the paste has landed.
    @MainActor private static func paste(_ text: String, to app: NSRunningApplication) async -> Bool {
        let pasteboard = NSPasteboard.general
        let saved = snapshot(pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        guard await activate(app) else {
            restore(saved, to: pasteboard)
            return false
        }
        postCommandV()
        // The target app reads the clipboard asynchronously; give it a moment before restoring.
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            restore(saved, to: pasteboard)
        }
        return true
    }

    /// Waits for `app` to become frontmost; ⌘V must not be posted anywhere else.
    @MainActor private static func activate(_ app: NSRunningApplication) async -> Bool {
        if NSWorkspace.shared.frontmostApplication?.processIdentifier != app.processIdentifier {
            _ = app.activate()
        }
        for _ in 0..<25 {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    /// Keycode 9 is the V key in every layout; modifiers are the same Command-V every app knows.
    private static func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: isDown)
            else { continue }
            event.flags = .maskCommand
            event.post(tap: .cgAnnotatedSessionEventTap)
        }
    }

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
    private static func selectionBounds(_ element: AXUIElement, source: Source) -> CGRect? {
        guard let location = source.location, let length = source.length else { return nil }
        var range = CFRange(location: location, length: length)
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

    static func canReplace(original: Source, current: Source, sameElement: Bool) -> Bool {
        sameElement && original.text != nil && original.location != nil && original == current
    }

    private static func source(_ element: AXUIElement, pid: pid_t?, text: String?, copy: Reader)
        -> Source
    {
        var range = CFRange()
        let value = copy(element, kAXSelectedTextRangeAttribute)
        let hasRange =
            value.map {
                CFGetTypeID($0) == AXValueGetTypeID()
                    && AXValueGetType(unsafeDowncast($0, to: AXValue.self)) == .cfRange
                    && AXValueGetValue(unsafeDowncast($0, to: AXValue.self), .cfRange, &range)
            } == true
        return Source(
            pid: pid, document: copy(element, kAXDocumentAttribute) as? String, text: text,
            location: hasRange ? range.location : nil, length: hasRange ? range.length : nil)
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
