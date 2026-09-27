import AppKit
import ApplicationServices
import Synchronization
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
            app,
            copy: reader(
                [
                    kAXSubroleAttribute: kAXSecureTextFieldSubrole as CFString,
                    kAXSelectedTextAttribute: "pw" as CFString,
                ], log: log))
        #expect(result.map(\.text) == .failure(.secure))
        #expect(log.calls == [kAXFocusedUIElementAttribute, kAXSubroleAttribute])
    }

    @Test func textIsReadOnceAndTheRangeIsDecoded() {
        let log = Log()
        var range = CFRange(location: 3, length: 9)
        let text = "  héllo\n世界 "
        let result = SelectionBridge.capture(
            app,
            copy: reader(
                [
                    kAXSelectedTextAttribute: text as CFString,
                    kAXSelectedTextRangeAttribute: AXValueCreate(.cfRange, &range)!,
                ], log: log))
        let captured = try? result.get()
        #expect(captured?.text == text)
        #expect(captured?.range == SelectedRange(location: 3, length: 9))
        #expect(log.calls.filter { $0 == kAXSelectedTextAttribute }.count == 1)
    }

    @Test func wrongTypesFailSafely() {
        let wrongText = SelectionBridge.capture(
            app, copy: reader([kAXSelectedTextAttribute: 42 as CFNumber], log: Log()))
        #expect(wrongText.map(\.text) == .failure(.unreadable))
        let wrongSubrole = SelectionBridge.capture(
            app,
            copy: reader(
                [kAXSubroleAttribute: 1 as CFNumber, kAXSelectedTextAttribute: "hi" as CFString],
                log: Log()))
        #expect(wrongSubrole.map(\.text) == .failure(.unreadable))
        let wrongRange = try? SelectionBridge.capture(
            app,
            copy: reader(
                [
                    kAXSelectedTextAttribute: "hi" as CFString,
                    kAXSelectedTextRangeAttribute: "0,2" as CFString,
                ], log: Log())
        ).get()
        #expect(wrongRange?.range == nil)
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

    /// Page and PDF selections answer no accessibility attribute, so a ⌘C read is the only way to
    /// reach them; its text must reach the caller like an accessibility read would.
    @Test func copyFallbackReadsWhenTheSearchFindsNothing() {
        let result = SelectionBridge.capture(
            app, copy: reader([:], log: Log()), copySelection: { "copied from page" })
        let captured = try? result.get()
        #expect(captured?.text == "copied from page")
        #expect(captured?.range == nil)
        #expect(captured.map { CFEqual($0.element, field) } == true)
    }

    /// A field known to be secure never reaches the fallback, so ⌘C is never pressed there.
    @Test func copyFallbackIsSkippedForASecureField() {
        let called = Mutex(false)
        let result = SelectionBridge.capture(
            app,
            copy: reader([kAXSubroleAttribute: kAXSecureTextFieldSubrole as CFString], log: Log()),
            copySelection: {
                called.withLock { $0 = true }
                return "pw"
            })
        #expect(result.map(\.text) == .failure(.secure))
        #expect(called.withLock { $0 } == false)
    }

    /// An accessibility read is authoritative, so the fallback must not press ⌘C over it.
    @Test func copyFallbackIsSkippedWhenTheSearchSucceeds() {
        let called = Mutex(false)
        let result = SelectionBridge.capture(
            app,
            copy: reader([kAXSelectedTextAttribute: "accessibility text" as CFString], log: Log()),
            copySelection: {
                called.withLock { $0 = true }
                return "pasteboard text"
            })
        #expect(result.map(\.text) == .success("accessibility text"))
        #expect(called.withLock { $0 } == false)
    }

    /// The ⌘C read hands the user's own pasteboard back and keeps nothing.
    @Test func copyFallbackRestoresThePreviousPasteboard() {
        let fake = FakePasteboard("user text")
        let seam = fake.seam()
        let copy = SelectionBridge.copySelection(
            pasteboard: seam,
            press: { seam.write("copied text") },
            sleep: {})
        #expect(copy() == "copied text")
        #expect(fake.text == "user text")
    }

    /// A copy that changes nothing yields no text and leaves the pasteboard alone.
    @Test func copyFallbackWithoutANewCopyIsNil() {
        let fake = FakePasteboard("user text")
        let copy = SelectionBridge.copySelection(
            pasteboard: fake.seam(), press: {}, sleep: {})
        #expect(copy() == nil)
        #expect(fake.text == "user text")
    }

    @Test @MainActor func directWriteIsUsedWhenTheElementAcceptsIt() async {
        let pasted = Mutex(false)
        let outcome = await SelectionBridge.replace(
            Selection(text: "Hello", element: field, app: .current, range: SelectedRange(location: 0, length: 5)),
            with: "你好",
            seams: seams(write: { _, _ in true }, press: { pasted.withLock { $0 = true } }))
        #expect(outcome == .written)
        #expect(pasted.withLock { $0 } == false)
    }

    /// A page or PDF selection refuses a direct write, so the result goes through the pasteboard.
    @Test @MainActor func pasteIsUsedWhenTheDirectWriteFails() async {
        let pasted = Mutex(false)
        let fake = FakePasteboard("user text")
        let outcome = await SelectionBridge.replace(
            Selection(text: "Hello", element: field, app: .current, range: SelectedRange(location: 0, length: 5)),
            with: "你好",
            seams: seams(
                write: { _, _ in false },
                press: { pasted.withLock { $0 = true } },
                pasteboard: fake.seam()))
        #expect(outcome == .pasted)
        #expect(pasted.withLock { $0 })
        #expect(fake.text == "user text")
    }

    /// The paste never runs when the app will not come forward, and the pasteboard still returns.
    @Test @MainActor func pasteRefusesWithoutFrontingTheApp() async {
        let pasted = Mutex(false)
        let fake = FakePasteboard("user text")
        let outcome = await SelectionBridge.replace(
            Selection(text: "Hello", element: field, app: .current, range: SelectedRange(location: 0, length: 5)),
            with: "你好",
            seams: seams(
                write: { _, _ in false },
                activate: { _ in false },
                press: { pasted.withLock { $0 = true } },
                pasteboard: fake.seam()))
        #expect(outcome == .refused)
        #expect(pasted.withLock { $0 } == false)
        #expect(fake.text == "user text")
    }

    @Test @MainActor func replaceRefusesWithoutAccessibilityPermission() async {
        let outcome = await SelectionBridge.replace(
            Selection(text: "Hello", element: field, app: .current, range: SelectedRange(location: 0, length: 5)),
            with: "你好",
            seams: SelectionBridge.WritebackSeams(trusted: { false }))
        #expect(outcome == .refused)
    }

    /// Builds write-back seams that never touch accessibility, the pasteboard or real key events.
    @MainActor func seams(
        write: @escaping @MainActor (AXUIElement, String) -> Bool,
        activate: @escaping @MainActor (NSRunningApplication) async -> Bool = { _ in true },
        press: @escaping SelectionBridge.PasteSelection,
        pasteboard: SelectionBridge.Pasteboard = .system
    ) -> SelectionBridge.WritebackSeams {
        SelectionBridge.WritebackSeams(
            trusted: { true }, write: write, activate: activate, press: press, pasteboard: pasteboard,
            settle: .zero)
    }

    /// In-memory pasteboard so the fallback tests never touch the real pasteboard.
    final class FakePasteboard: Sendable {
        private let content: Mutex<(text: String?, changeCount: Int)>

        init(_ text: String? = nil) { content = Mutex((text, 0)) }

        var text: String? { content.withLock { $0.text } }

        func seam() -> SelectionBridge.Pasteboard {
            SelectionBridge.Pasteboard(
                changeCount: { self.content.withLock { $0.changeCount } },
                string: { self.content.withLock { $0.text } },
                write: { text in
                    self.content.withLock {
                        $0.text = text
                        $0.changeCount += 1
                    }
                },
                snapshot: {
                    self.content.withLock {
                        let item: [NSPasteboard.PasteboardType: Data] = [
                            .string: Data(($0.text ?? "").utf8)
                        ]
                        return [item]
                    }
                },
                restore: { items in
                    self.content.withLock {
                        $0.text = items.first?[.string].flatMap { String(data: $0, encoding: .utf8) }
                        $0.changeCount += 1
                    }
                })
        }
    }

    @Test func missingFocusedElementIsUnreadable() {
        let result = SelectionBridge.capture(app, copy: { _, _ in nil })
        #expect(result.map(\.text) == .failure(.unreadable))
    }
}
