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

    @Test func missingFocusedElementIsUnreadable() {
        let result = SelectionBridge.capture(app, pid: 9, copy: { _, _ in nil })
        #expect(result.map(\.text) == .failure(.unreadable))
    }
}
