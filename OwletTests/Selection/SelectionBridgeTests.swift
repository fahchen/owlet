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
}
