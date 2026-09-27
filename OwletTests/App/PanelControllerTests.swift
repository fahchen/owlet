import AppKit
import ApplicationServices
import Foundation
import Synchronization
import Testing

@testable import Owlet

/// Serialized: each test may show a real panel, and real panels compete for key.
@MainActor @Suite(.serialized)
struct PanelControllerTests {
    let range = SelectedRange(location: 0, length: 5)
    var selection: Selection {
        Selection(text: "Hello", element: AXUIElementCreateApplication(1), app: nil, range: range)
    }

    /// Transport that waits until released, so tests control when a response arrives.
    final class Gate: @unchecked Sendable {
        var continuations: [CheckedContinuation<Void, Never>] = []
        func release() { continuations.removeFirst().resume() }
    }

    /// A panel that never goes on screen, so a test of controller state does not depend on the
    /// window server and the test host's key changes.
    final class OffScreenPanel: FloatingPanel {
        override func show(anchor: PanelPlacement.Anchor) {}
    }

    /// An off-screen panel that remembers being asked to release the keyboard, so the write-back's
    /// first step can be asserted without a real window the test host cannot keep key on.
    final class RecordingPanel: FloatingPanel {
        private(set) var releases = 0
        override func show(anchor: PanelPlacement.Anchor) {}
        override func releaseKeyboard() { releases += 1 }
    }

    func makePanel(
        gate: Gate? = nil, outcome: ReplaceOutcome = .pasted,
        defaults: UserDefaults = UserDefaults(suiteName: "PanelControllerTests.\(UUID().uuidString)")!,
        realWindow: Bool = false
    ) -> (PanelController, Box) {
        let transport: Transport = { request in
            if let gate { await withCheckedContinuation { gate.continuations.append($0) } }
            return try await stub(body: chatBody(TestReplies.reply(for: "Hello")))(request)
        }
        let model = TranslationModel(
            client: ModelClient(transport: transport), config: { testConfig })
        let panel = PanelController(model: model, defaults: defaults)
        if !realWindow { panel.makeWindow = { (view: PanelView) in OffScreenPanel(rootView: view) } }
        let writes = Box()
        let selection = selection
        panel.read = { $0(.success(selection)) }
        panel.write = { _, text in
            writes.texts.append(text)
            return outcome
        }
        return (panel, writes)
    }

    final class Box { var texts: [String] = [] }

    func settle() async {
        for _ in 0..<50 { await Task.yield() }
        try? await Task.sleep(for: .milliseconds(50))
    }

    @Test
    func successWritesOnce() async {
        let (panel, writes) = makePanel()
        panel.trigger(replace: true)
        await settle()
        #expect(writes.texts == ["T:Hello"])
        #expect(panel.selection == nil)
        panel.replace(with: "again")
        #expect(writes.texts == ["T:Hello"])
    }

    @Test
    func plainTranslateDoesNotWrite() async {
        let (panel, writes) = makePanel()
        panel.trigger()
        await settle()
        #expect(writes.texts.isEmpty)
        #expect(panel.expanded)
        panel.close()
    }

    @Test func lateResponseAfterCancelDoesNotWrite() async {
        let gate = Gate()
        let (panel, writes) = makePanel(gate: gate)
        panel.trigger(replace: true)
        await settle()
        panel.close()
        gate.release()
        await settle()
        #expect(writes.texts.isEmpty)
    }

    @Test
    func newRequestSupersedesOld() async {
        let gate = Gate()
        let (panel, writes) = makePanel(gate: gate)
        panel.trigger(replace: true)
        await settle()
        panel.trigger(replace: true)
        await settle()
        gate.release()
        gate.release()
        await settle()
        #expect(writes.texts == ["T:Hello"])
        panel.close()
    }

    @Test func noSelectionDoesNotWrite() async {
        let (panel, writes) = makePanel()
        panel.read = { $0(.failure(.unreadable)) }
        panel.trigger(replace: true)
        await settle()
        #expect(writes.texts.isEmpty)
        #expect(panel.notice == .unreadable)
        panel.close()
    }

    typealias Completion = @MainActor (Result<Selection, SelectionError>) -> Void
    final class Reads { var completions: [Completion] = [] }

    func deferredReads(_ panel: PanelController) -> Reads {
        let reads = Reads()
        panel.read = { reads.completions.append($0) }
        return reads
    }

    /// The budget only puts the notice up: a browser builds its accessibility tree on request, so
    /// the slow answer is usually the right one and has to be allowed to replace the notice.
    @Test func readPastBudgetShowsUnreadableThenAcceptsTheLateAnswer() async {
        let (panel, _) = makePanel()
        let reads = deferredReads(panel)
        panel.trigger()
        #expect(panel.notice == nil)
        try? await Task.sleep(for: .milliseconds(1_100))
        #expect(panel.notice == .unreadable)
        reads.completions[0](.success(selection))
        await settle()
        #expect(panel.model.input == "Hello")
        panel.close()
    }

    @Test func lateReadAfterCloseIsIgnored() async {
        let (panel, writes) = makePanel()
        let reads = deferredReads(panel)
        panel.trigger(.polish, replace: true)
        try? await Task.sleep(for: .milliseconds(250))
        panel.close()
        reads.completions[0](.success(selection))
        await settle()
        #expect(panel.selection == nil)
        #expect(panel.model.input.isEmpty)
        #expect(panel.notice == nil)
        #expect(writes.texts.isEmpty)
    }

    /// A paste is a write too: the source is still consumed, no refusal is left and the panel
    /// confirms the write-back instead of closing. Driven through the footer's entry point, which
    /// is what a click or ⌘↩ reaches, so the assertion does not depend on the window's key state.
    @Test func pastedWriteConsumesTheSelection() async {
        let (panel, writes) = makePanel(outcome: .pasted)
        panel.trigger()
        await settle()
        #expect(panel.selection != nil)
        panel.replace(with: "T:Hello")
        for _ in 0..<40 where writes.texts.isEmpty { try? await Task.sleep(for: .milliseconds(50)) }
        #expect(writes.texts == ["T:Hello"])
        #expect(panel.selection == nil)
        #expect(panel.writebackRefusal == nil)
        #expect(panel.writebackConfirmed)
    }

    @Test func rapidTriggersAcceptOnlyLatestRead() async {
        let (panel, writes) = makePanel()
        let reads = deferredReads(panel)
        panel.trigger(replace: true)
        panel.trigger()
        reads.completions[1](.failure(.unreadable))
        reads.completions[0](.success(selection))
        await settle()
        #expect(panel.notice == .unreadable)
        #expect(panel.selection == nil)
        #expect(panel.model.input.isEmpty)
        #expect(writes.texts.isEmpty)
        panel.close()
    }

    /// Losing key (deactivation, a system dialog, or an inactive app taking key and dropping it) no
    /// longer dismisses: the panel stays up and the pending auto-replace still writes.
    @Test func losingKeyNeitherClosesNorCancelsTheWrite() async throws {
        let gate = Gate()
        let (panel, writes) = makePanel(gate: gate, realWindow: true)
        panel.trigger(replace: true)
        await settle()
        #expect(panel.notice == .translating)
        #expect(panel.replacing)
        let window = try #require(panel.panel)
        #expect(window.isVisible)
        window.resignKey()
        #expect(window.isVisible)
        #expect(panel.notice == .translating)
        gate.release()
        await settle()
        #expect(writes.texts == ["T:Hello"])
        #expect(panel.writebackConfirmed)
        panel.close()
    }

    /// The write-back takes the keyboard away from the panel first — a synthetic ⌘V follows the
    /// keyboard — without dismissing it, and the write itself still happens exactly once.
    @Test func writeBackReleasesTheKeyboardWithoutDismissing() async throws {
        final class Holder { var panel: RecordingPanel? }
        let holder = Holder()
        let (panel, writes) = makePanel()
        panel.makeWindow = { view in
            let stub = RecordingPanel(rootView: view)
            holder.panel = stub
            return stub
        }
        panel.trigger(replace: true)
        let stub = try #require(holder.panel)
        var closes = 0
        let onClose = stub.onClose
        stub.onClose = {
            closes += 1
            onClose()
        }
        let releasesAtWrite = Mutex(-1)
        panel.write = { _, text in
            writes.texts.append(text)
            releasesAtWrite.withLock { $0 = holder.panel?.releases ?? -1 }
            return .pasted
        }
        for _ in 0..<40 where writes.texts.isEmpty { try? await Task.sleep(for: .milliseconds(50)) }
        #expect(writes.texts == ["T:Hello"])
        // Released exactly once, and already released by the time the write ran.
        #expect(releasesAtWrite.withLock { $0 } == 1)
        #expect(!stub.isVisible)
        #expect(panel.selection == nil)
        // The panel is not dismissed: it comes back to confirm the write-back.
        #expect(closes == 0)
        #expect(panel.writebackConfirmed)
    }

    /// A write-back that never landed comes back with the result still in hand, so the failure is
    /// visible instead of the panel closing as if it had worked.
    @Test func refusedWriteBackKeepsTheResult() async {
        let (panel, _) = makePanel(outcome: .refused)
        panel.trigger(replace: true)
        for _ in 0..<40 where panel.writebackRefusal == nil {
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(panel.writebackRefusal == .unwritten)
        #expect(panel.selection != nil)
        #expect(!panel.writebackConfirmed)
    }

    /// A read-only selection is reported as such rather than as a generic failure.
    @Test func readOnlySelectionIsReportedAsUnwritable() async {
        let (panel, _) = makePanel(outcome: .unwritable)
        panel.trigger(replace: true)
        for _ in 0..<40 where panel.writebackRefusal == nil {
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(panel.writebackRefusal == .unwritable)
        #expect(panel.selection != nil)
        #expect(!panel.writebackConfirmed)
    }

    /// A successful write-back confirms instead of vanishing: the panel stays on screen with the
    /// result still copyable, and Esc closes it.
    @Test func successfulWriteBackConfirmsAndEscCloses() async throws {
        let (panel, _) = makePanel(outcome: .pasted, realWindow: true)
        panel.trigger()
        await settle()
        #expect(panel.model.state == .success("T:Hello"))
        panel.replace(with: "T:Hello")
        for _ in 0..<40 where !panel.writebackConfirmed { try? await Task.sleep(for: .milliseconds(50)) }
        #expect(panel.writebackConfirmed)
        #expect(panel.selection == nil)
        #expect(panel.model.state == .success("T:Hello"))
        #expect(panel.inlineNotice == nil)
        let window = try #require(panel.panel)
        #expect(window.isVisible)
        panel.run(.cancel)
        #expect(!window.isVisible)
        #expect(!panel.writebackConfirmed)
    }

    /// 完成 closes the confirmation through the same controller close the footer button calls.
    @Test func finishClosesTheConfirmation() async throws {
        let (panel, _) = makePanel(outcome: .pasted, realWindow: true)
        panel.trigger()
        await settle()
        panel.replace(with: "T:Hello")
        for _ in 0..<40 where !panel.writebackConfirmed { try? await Task.sleep(for: .milliseconds(50)) }
        let window = try #require(panel.panel)
        #expect(window.isVisible)
        panel.close()
        #expect(!window.isVisible)
        #expect(!panel.writebackConfirmed)
    }

    /// A click that misses the glass dismisses the panel; a click on the panel is not a dismissal.
    @Test func mouseDownOutsideDismissesButInsideDoesNot() async throws {
        let (panel, _) = makePanel(realWindow: true)
        panel.read = { $0(.failure(.unreadable)) }
        panel.trigger()
        let window = try #require(panel.panel)
        #expect(window.isVisible)
        window.dismissIfOutside(NSPoint(x: window.frame.midX, y: window.frame.midY))
        #expect(window.isVisible)
        window.dismissIfOutside(NSPoint(x: window.frame.maxX + 500, y: window.frame.maxY + 500))
        #expect(!window.isVisible)
    }

    /// The outside-click monitor lives exactly while the panel is visible, so a hidden panel cannot
    /// swallow the next click.
    @Test func mouseMonitorFollowsVisibility() async throws {
        let (panel, _) = makePanel(realWindow: true)
        panel.read = { $0(.failure(.unreadable)) }
        panel.trigger()
        let window = try #require(panel.panel)
        #expect(window.watchesMouse)
        panel.close()
        #expect(!window.watchesMouse)
    }

    /// A write-back takes the panel off screen without dismissing it, and a miss brings it back with
    /// the result still copyable.
    @Test func writeBackBringsThePanelBackOnAMiss() async throws {
        let (panel, _) = makePanel(outcome: .refused, realWindow: true)
        panel.trigger()
        await settle()
        let window = try #require(panel.panel)
        #expect(window.isVisible)
        #expect(panel.selection != nil)
        panel.replace(with: "T:Hello")
        for _ in 0..<40 where panel.writebackRefusal == nil { try? await Task.sleep(for: .milliseconds(50)) }
        await settle()
        #expect(panel.writebackRefusal == .unwritten)
        #expect(panel.selection != nil)
        #expect(window.isVisible)
        #expect(window.watchesMouse)
        #expect(!panel.writebackConfirmed)
        panel.close()
    }

    /// `close()` re-entered from `onClose` runs `onClose` once, and a later key change is inert.
    @Test func closeIsNotReentrant() async throws {
        let (panel, _) = makePanel(realWindow: true)
        panel.read = { $0(.failure(.unreadable)) }
        panel.trigger()
        let window = try #require(panel.panel)
        var closes = 0
        let onClose = window.onClose
        window.onClose = {
            closes += 1
            onClose()
            window.close()
            window.resignKey()
        }
        window.close()
        #expect(closes == 1)
        #expect(!window.isVisible)
        window.resignKey()
        #expect(closes == 1)
        #expect(panel.notice == nil)
        #expect(panel.model.state == .idle)
    }

    /// The panel keeps the system glass defaults and casts a shadow that follows the glass: the
    /// window's shape comes from a container masked to the glass's own corner radius, which is what
    /// stops the window server from shadowing a rectangle around rounded glass.
    @Test func shapesItsShadowLikeTheGlass() async throws {
        let (panel, _) = makePanel(realWindow: true)
        panel.read = { $0(.failure(.unreadable)) }
        panel.trigger()
        let window = try #require(panel.panel)
        let shape = try #require(window.contentView)
        let glass = try #require(shape.subviews.first as? NSGlassEffectView)
        #expect(glass.cornerRadius == NSGlassEffectView().cornerRadius)
        #expect(glass.style == NSGlassEffectView().style)
        #expect(window.hasShadow)
        #expect(shape.layer?.cornerRadius == glass.cornerRadius)
        #expect(shape.layer?.masksToBounds == true)
        #expect(glass.frame == shape.bounds)
        panel.close()
    }

    /// Becoming key hands the responder to SwiftUI's key view proxy, which focuses the first
    /// control; the panel takes it back, so it opens with nothing focused, and Tab still reaches
    /// the controls afterwards.
    @Test func opensWithNothingFocusedButTabStillReachesTheControls() async throws {
        let (panel, _) = makePanel(realWindow: true)
        panel.read = { $0(.failure(.unreadable)) }
        panel.trigger()
        let window = try #require(panel.panel)
        #expect(window.firstResponder === window)
        let tab = try #require(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: "\t",
                charactersIgnoringModifiers: "\t", isARepeat: false, keyCode: 48))
        window.keyDown(with: tab)
        #expect(window.firstResponder !== window)
        panel.close()
    }

    /// Fixed mode: a user move of the glass-backed panel saves its top-center; self-placement does not.
    @Test func dragSavesFixedAnchor() async throws {
        let defaults = UserDefaults(suiteName: "PanelControllerTests.\(UUID().uuidString)")!
        let (panel, _) = makePanel(defaults: defaults, realWindow: true)
        panel.read = { $0(.failure(.unreadable)) }
        panel.trigger()
        let window = try #require(panel.panel)
        #expect(window.contentView?.subviews.first is NSGlassEffectView)
        #expect(SettingsStore.panelFixedAnchor(in: defaults) == nil)
        window.setFrameOrigin(NSPoint(x: window.frame.minX + 40, y: window.frame.minY - 30))
        await settle()
        #expect(SettingsStore.panelFixedAnchor(in: defaults) == NSPoint(x: window.frame.midX, y: window.frame.maxY))
        panel.close()
    }

    /// Follow-selection mode: the panel sits just below the selection and a drag is not saved.
    @Test func followSelectionPlacesBelowAndIgnoresDrag() async throws {
        let defaults = UserDefaults(suiteName: "PanelControllerTests.\(UUID().uuidString)")!
        defaults.set(PanelPosition.followSelection.rawValue, forKey: SettingsStore.panelPositionKey)
        let gate = Gate()
        let (panel, _) = makePanel(gate: gate, defaults: defaults, realWindow: true)
        let screen = try #require(NSScreen.screens.first)
        let visible = screen.visibleFrame
        // AX rect near the top-left of the primary screen's visible area (y down from the top).
        let axRect = CGRect(
            x: visible.minX + 100, y: screen.frame.maxY - visible.maxY + 100, width: 80, height: 20)
        var selection = selection
        selection.bounds = axRect
        panel.read = { [selection] in $0(.success(selection)) }
        panel.trigger()
        await settle()
        let window = try #require(panel.panel)
        let rect = PanelPlacement.appKitRect(fromAX: axRect, primaryScreenHeight: screen.frame.height)
        #expect(window.frame.minX == rect.minX)
        #expect(window.frame.maxY == rect.minY - PanelPlacement.gap)
        window.setFrameOrigin(NSPoint(x: window.frame.minX + 40, y: window.frame.minY - 30))
        await settle()
        #expect(SettingsStore.panelFixedAnchor(in: defaults) == nil)
        panel.close()
        gate.release()
    }
}
