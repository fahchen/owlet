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

    static func read() -> Result<Selection, SelectionError> {
        let trusted = AXIsProcessTrusted()
        let element = trusted ? focusedElement() : nil
        let subrole = element.flatMap { string($0, kAXSubroleAttribute) }
        let text = element.flatMap { string($0, kAXSelectedTextAttribute) }
        return classify(trusted: trusted, subrole: subrole, text: text).flatMap { text in
            guard let element else { return .failure(.unreadable) }
            let app = NSWorkspace.shared.frontmostApplication
            return .success(
                Selection(
                    text: text, element: element, app: app,
                    source: source(element, pid: app?.processIdentifier)))
        }
    }

    /// Writes `text` over the original selection only if its element, document, text and range
    /// are unchanged. Returns false without writing otherwise.
    static func replace(_ selection: Selection, with text: String) -> Bool {
        guard AXIsProcessTrusted(), let element = focusedElement() else { return false }
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard
            canReplace(
                original: selection.source, current: source(element, pid: pid),
                sameElement: CFEqual(element, selection.element))
        else { return false }
        return AXUIElementSetAttributeValue(
            element, kAXSelectedTextAttribute as CFString, text as CFString) == .success
    }

    static func canReplace(original: Source, current: Source, sameElement: Bool) -> Bool {
        sameElement && original.text != nil && original.location != nil && original == current
    }

    private static func source(_ element: AXUIElement, pid: pid_t?) -> Source {
        var range = CFRange()
        var value: AnyObject?
        let hasRange =
            AXUIElementCopyAttributeValue(
                element, kAXSelectedTextRangeAttribute as CFString, &value) == .success
            && value.map { AXValueGetValue(unsafeDowncast($0, to: AXValue.self), .cfRange, &range) }
                == true
        return Source(
            pid: pid, document: string(element, kAXDocumentAttribute),
            text: string(element, kAXSelectedTextAttribute),
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

    private static func focusedElement() -> AXUIElement? {
        var value: AnyObject?
        guard
            AXUIElementCopyAttributeValue(
                AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute as CFString, &value)
                == .success,
            let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
        else { return nil }
        return value as? String
    }
}
