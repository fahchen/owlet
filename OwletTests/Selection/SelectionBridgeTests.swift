import ApplicationServices
import Testing

@testable import Owlet

struct SelectionBridgeTests {
    @Test func untrustedReportsPermission() {
        #expect(SelectionBridge.classify(trusted: false, subrole: nil, text: "hi") == .failure(.permission))
    }

    @Test func secureFieldIsNotRead() {
        #expect(
            SelectionBridge.classify(trusted: true, subrole: kAXSecureTextFieldSubrole, text: "pw")
                == .failure(.secure))
    }

    @Test func blankOrMissingIsUnreadable() {
        #expect(SelectionBridge.classify(trusted: true, subrole: nil, text: nil) == .failure(.unreadable))
        #expect(SelectionBridge.classify(trusted: true, subrole: nil, text: " \n") == .failure(.unreadable))
    }

    @Test func textSucceeds() {
        #expect(SelectionBridge.classify(trusted: true, subrole: nil, text: "Hello") == .success("Hello"))
    }

    let source = Source(pid: 1, document: "file:///a", text: "Hello", location: 3, length: 5)

    @Test func unchangedSourceCanBeReplaced() {
        #expect(SelectionBridge.canReplace(original: source, current: source, sameElement: true))
    }

    @Test func mismatchedSourceIsRefused() {
        #expect(!SelectionBridge.canReplace(original: source, current: source, sameElement: false))
        let otherApp = Source(pid: 2, document: "file:///a", text: "Hello", location: 3, length: 5)
        #expect(!SelectionBridge.canReplace(original: source, current: otherApp, sameElement: true))
        let unknown = Source(pid: 1, document: nil, text: nil, location: nil, length: nil)
        #expect(!SelectionBridge.canReplace(original: unknown, current: unknown, sameElement: true))
    }

    @Test func changedDocumentOrTextIsRefused() {
        let doc = Source(pid: 1, document: "file:///b", text: "Hello", location: 3, length: 5)
        let edited = Source(pid: 1, document: "file:///a", text: "Hallo", location: 3, length: 5)
        #expect(!SelectionBridge.canReplace(original: source, current: doc, sameElement: true))
        #expect(!SelectionBridge.canReplace(original: source, current: edited, sameElement: true))
    }

    /// After a write-back the selection holds the result, so a second attempt is refused.
    @Test func repeatedReplaceIsRefused() {
        let after = Source(pid: 1, document: "file:///a", text: "你好", location: 3, length: 2)
        #expect(!SelectionBridge.canReplace(original: source, current: after, sameElement: true))
    }

    // Distinct opaque AX handles; the injected reader never sends them real AX messages.
    let app = AXUIElementCreateApplication(1)
    let field = AXUIElementCreateApplication(2)

    /// Serves `attrs` for the focused field and records every requested attribute.
    func reader(_ attrs: [String: AnyObject], log: Log) -> SelectionBridge.Reader {
        { element, attribute in
            log.calls.append(attribute)
            if CFEqual(element, app) {
                return attribute == kAXFocusedUIElementAttribute ? field : nil
            }
            return attrs[attribute]
        }
    }

    final class Log { var calls: [String] = [] }

    @Test func secureFieldNeverReadsTextOrRange() {
        let log = Log()
        let result = SelectionBridge.capture(
            app, pid: 9,
            copy: reader(
                [
                    kAXSubroleAttribute: kAXSecureTextFieldSubrole as CFString,
                    kAXSelectedTextAttribute: "pw" as CFString,
                ], log: log))
        #expect(result.map(\.text) == .failure(.secure))
        #expect(log.calls == [kAXFocusedUIElementAttribute, kAXSubroleAttribute])
    }

    @Test func textIsReadOnceAndReusedForSource() {
        let log = Log()
        var range = CFRange(location: 3, length: 9)
        let text = "  héllo\n世界 "
        let result = SelectionBridge.capture(
            app, pid: 9,
            copy: reader(
                [
                    kAXSelectedTextAttribute: text as CFString,
                    kAXSelectedTextRangeAttribute: AXValueCreate(.cfRange, &range)!,
                    kAXDocumentAttribute: "file:///a" as CFString,
                ], log: log))
        let captured = try? result.get()
        #expect(captured?.text == text)
        #expect(
            captured?.source
                == Source(pid: 9, document: "file:///a", text: text, location: 3, length: 9))
        #expect(log.calls.filter { $0 == kAXSelectedTextAttribute }.count == 1)
    }

    @Test func wrongTypesFailSafely() {
        let wrongText = SelectionBridge.capture(
            app, pid: 9, copy: reader([kAXSelectedTextAttribute: 42 as CFNumber], log: Log()))
        #expect(wrongText.map(\.text) == .failure(.unreadable))
        let wrongSubrole = SelectionBridge.capture(
            app, pid: 9,
            copy: reader(
                [kAXSubroleAttribute: 1 as CFNumber, kAXSelectedTextAttribute: "hi" as CFString],
                log: Log()))
        #expect(wrongSubrole.map(\.text) == .failure(.unreadable))
        let wrongRange = try? SelectionBridge.capture(
            app, pid: 9,
            copy: reader(
                [
                    kAXSelectedTextAttribute: "hi" as CFString,
                    kAXSelectedTextRangeAttribute: "0,2" as CFString,
                ], log: Log())
        ).get()
        #expect(wrongRange?.source.location == nil)
    }

    // MARK: Selection search

    /// A web page keeps the selection on the web area, one level above the focused element.
    @Test func searchFindsSelectionOnAnAncestor() {
        let focused = AXUIElementCreateApplication(2)
        let webArea = AXUIElementCreateApplication(3)
        let copy: SelectionBridge.Reader = { element, attribute in
            if CFEqual(element, focused), attribute == kAXParentAttribute { return webArea }
            if CFEqual(element, webArea), attribute == kAXSelectedTextAttribute {
                return "page text" as CFString
            }
            return nil
        }
        let found = SelectionBridge.search(focused, copy: copy, marker: { _, _ in nil })
        #expect(found.map { CFEqual($0.element, webArea) } == true)
        #expect(found?.text == "page text")
    }

    /// A PDF viewer holds no selection itself; its text layer is a child.
    @Test func searchFindsSelectionInADescendant() {
        let focused = AXUIElementCreateApplication(2)
        let page = AXUIElementCreateApplication(4)
        let copy: SelectionBridge.Reader = { element, attribute in
            if CFEqual(element, focused), attribute == kAXChildrenAttribute {
                return [page] as NSArray
            }
            if CFEqual(element, page), attribute == kAXSelectedTextAttribute {
                return "pdf text" as CFString
            }
            return nil
        }
        #expect(SelectionBridge.search(focused, copy: copy, marker: { _, _ in nil })?.text == "pdf text")
    }

    /// Safari publishes a page selection only as a text marker range.
    @Test func searchReadsSelectionThroughAWebKitMarkerRange() {
        let focused = AXUIElementCreateApplication(2)
        let range = "marker" as NSString
        let copy: SelectionBridge.Reader = { element, attribute in
            if CFEqual(element, focused), attribute == kAXSelectedTextMarkerRangeAttribute {
                return range
            }
            return nil
        }
        // The marker reader is @Sendable, so it captures nothing and matches on the value alone.
        let marker: SelectionBridge.MarkerString = { _, value in
            (value as? NSString) == ("marker" as NSString) ? "safari text" : nil
        }
        #expect(SelectionBridge.search(focused, copy: copy, marker: marker)?.text == "safari text")
    }

    /// A blank selection is not a selection, so the search keeps looking instead of stopping early.
    @Test func searchSkipsBlankSelections() {
        let focused = AXUIElementCreateApplication(2)
        let area = AXUIElementCreateApplication(3)
        let copy: SelectionBridge.Reader = { element, attribute in
            if CFEqual(element, focused) {
                if attribute == kAXSelectedTextAttribute { return "   " as CFString }
                if attribute == kAXParentAttribute { return area }
            }
            if CFEqual(element, area), attribute == kAXSelectedTextAttribute {
                return "real text" as CFString
            }
            return nil
        }
        #expect(SelectionBridge.search(focused, copy: copy, marker: { _, _ in nil })?.text == "real text")
    }

    /// Nothing anywhere: the search ends rather than walking forever.
    @Test func searchWithoutAnySelectionIsNil() {
        #expect(SelectionBridge.search(app, copy: { _, _ in nil }, marker: { _, _ in nil }) == nil)
    }

    // MARK: Write-back

    /// A non-editable selection has no range to compare, so the text itself is the whole check.
    @Test func nonEditableSelectionCanBePasted() {
        let original = Source(pid: 1, document: nil, text: "Hello", location: nil, length: nil)
        #expect(SelectionBridge.canPaste(original: original, current: original, sameElement: true))
    }

    @Test func pasteRefusedWhenTheSelectionMoved() {
        let original = Source(pid: 1, document: nil, text: "Hello", location: nil, length: nil)
        let moved = Source(pid: 1, document: nil, text: "World", location: nil, length: nil)
        let blank = Source(pid: 1, document: nil, text: "  ", location: nil, length: nil)
        #expect(!SelectionBridge.canPaste(original: original, current: moved, sameElement: true))
        #expect(!SelectionBridge.canPaste(original: original, current: original, sameElement: false))
        #expect(!SelectionBridge.canPaste(original: blank, current: blank, sameElement: true))
        #expect(
            !SelectionBridge.canPaste(
                original: Source(pid: 1, document: nil, text: nil, location: nil, length: nil),
                current: Source(pid: 1, document: nil, text: nil, location: nil, length: nil),
                sameElement: true))
    }

    @Test func missingFocusedElementIsUnreadable() {
        let result = SelectionBridge.capture(app, pid: 9, copy: { _, _ in nil })
        #expect(result.map(\.text) == .failure(.unreadable))
    }
}
