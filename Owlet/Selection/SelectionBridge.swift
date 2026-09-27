import AppKit
import ApplicationServices

enum SelectionError: Error, Equatable {
    case permission
    case unreadable
    /// Secure text fields are never read.
    case secure
}

/// Selected text plus the element and app it came from, captured before the panel opens.
struct Selection {
    let text: String
    let element: AXUIElement
    let app: NSRunningApplication?
    let source: Source
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

    static func read() -> Result<Selection, SelectionError> {
        guard AXIsProcessTrusted() else { return .failure(.permission) }
        guard let app = NSWorkspace.shared.frontmostApplication,
            app.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else { return .failure(.unreadable) }
        let pid = app.processIdentifier
        return capture(AXUIElementCreateApplication(pid), pid: pid, copy: copy).map {
            Selection(text: $0.text, element: $0.element, app: app, source: $0.source)
        }
    }

    /// Reads the focused element of `appElement`, checking the secure subrole before any
    /// text is touched, and reuses the single text read for `Source.text`.
    static func capture(_ appElement: AXUIElement, pid: pid_t, copy: Reader)
        -> Result<(text: String, element: AXUIElement, source: Source), SelectionError>
    {
        guard let element = focusedElement(appElement, copy: copy) else {
            return .failure(.unreadable)
        }
        let subrole = copy(element, kAXSubroleAttribute)
        if let subrole, !(subrole is String) { return .failure(.unreadable) }
        if subrole as? String == kAXSecureTextFieldSubrole { return .failure(.secure) }
        return classify(
            trusted: true, subrole: nil, text: copy(element, kAXSelectedTextAttribute) as? String
        ).map { text in
            (text, element, source(element, pid: pid, text: text, copy: copy))
        }
    }

    /// Writes `text` over the original selection only if its element, document, text and range
    /// are unchanged. Returns false without writing otherwise.
    static func replace(_ selection: Selection, with text: String) -> Bool {
        guard AXIsProcessTrusted(),
            let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
            let element = focusedElement(AXUIElementCreateApplication(pid), copy: copy)
        else { return false }
        let current = source(
            element, pid: pid, text: copy(element, kAXSelectedTextAttribute) as? String,
            copy: copy)
        guard
            canReplace(
                original: selection.source, current: current,
                sameElement: CFEqual(element, selection.element))
        else { return false }
        return AXUIElementSetAttributeValue(
            element, kAXSelectedTextAttribute as CFString, text as CFString) == .success
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
