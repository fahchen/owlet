import AppKit
import ApplicationServices
import Foundation
import Testing

@testable import Owlet

/// Serialized: each test shows a real panel, and a panel closes when another one takes key.
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

    /// A panel that never goes on screen. The test host is not the active application, so a real
    /// panel loses key the moment it takes it; a test of controller state must not race that.
    final class OffScreenPanel: FloatingPanel {
        override func show(anchor: PanelPlacement.Anchor) {}
    }

    func makePanel(
        gate: Gate? = nil, outcome: ReplaceOutcome = .written,
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

    @Test(.disabled("Hangs in app-hosted test run once the panel expands; needs investigation"))
    func successWritesOnce() async {
        let (panel, writes) = makePanel()
        panel.trigger(replace: true)
        await settle()
        #expect(writes.texts == ["T:Hello"])
        #expect(panel.selection == nil)
        panel.replace(with: "again")
        #expect(writes.texts == ["T:Hello"])
    }

    @Test(.disabled("Hangs in app-hosted test run once the panel expands; needs investigation"))
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

    @Test(.disabled("Hangs in app-hosted test run once the panel expands; needs investigation"))
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

    /// A refused write-back keeps the result copyable instead of claiming the selection moved.
    @Test(.disabled("Hangs in app-hosted test run once the panel expands; needs investigation"))
    func refusedWriteKeepsResult() async {
        let (panel, writes) = makePanel(outcome: .refused)
        panel.trigger(replace: true)
        await settle()
        #expect(writes.texts == ["T:Hello"])
        #expect(!panel.expanded)
        #expect(panel.notice == .unwritten)
        #expect(panel.writebackRefused)
        #expect(panel.model.state == .success("T:Hello"))
        panel.close()
    }

    @Test func stopShowsCancelledAndDoesNotWrite() async {
        let gate = Gate()
        let (panel, writes) = makePanel(gate: gate)
        panel.trigger(replace: true)
        await settle()
        panel.stop()
        #expect(panel.notice == .cancelled)
        #expect(panel.inlineNotice == .cancelled)
        gate.release()
        await settle()
        #expect(writes.texts.isEmpty)
        #expect(panel.notice == .cancelled)
        panel.close()
    }

    @Test func failureNoticeCopy() {
        typealias Notice = PanelController.Notice
        #expect(Notice.failure(ModelError.format.message).actionTitle == "提示词设置")
        #expect(Notice.failure(ModelError.unauthorized.message).message == "连接失败，请检查模型服务")
        #expect(Notice.failure(ModelError.http(500).message).message == "连接失败，请检查模型服务")
        #expect(Notice.failure(ModelError.network("x").message).actionTitle == "服务设置")
        #expect(Notice.failure(ModelError.refused.message).message == ModelError.refused.message)
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

    /// A paste is a write too: the source is still consumed, no refusal is left and the
    /// panel does not stay up. Driven through the footer's entry point, which is what a click or
    /// ⌘↩ reaches, so the assertion does not depend on the window's key state.
    @Test func pastedWriteConsumesTheSelection() async {
        let (panel, writes) = makePanel(outcome: .pasted)
        panel.trigger()
        await settle()
        #expect(panel.selection != nil)
        panel.replace(with: "T:Hello")
        for _ in 0..<40 where writes.texts.isEmpty { try? await Task.sleep(for: .milliseconds(50)) }
        #expect(writes.texts == ["T:Hello"])
        #expect(panel.selection == nil)
        #expect(!panel.writebackRefused)
        #expect(panel.panel?.isVisible != true)
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

    /// Losing key (click elsewhere) closes like Esc: the request is invalidated, so the pending
    /// auto-replace never writes and the late response is dropped.
    @Test func resignKeyClosesAndCancelsAutoReplace() async throws {
        let gate = Gate()
        let (panel, writes) = makePanel(gate: gate, realWindow: true)
        panel.trigger(replace: true)
        await settle()
        #expect(panel.notice == .translating)
        #expect(panel.replacing)
        let window = try #require(panel.panel)
        #expect(window.isVisible)
        window.resignKey()
        #expect(!window.isVisible)
        #expect(panel.notice == nil)
        #expect(panel.model.state == .idle)
        gate.release()
        await settle()
        #expect(writes.texts.isEmpty)
        #expect(panel.model.state == .idle)
        #expect(panel.notice == nil)
    }

    /// Dismissed while the write-back is in flight: the write still happens exactly once and
    /// `onClose` runs once. Driven through the controller, so no real window is involved and the
    /// assertion cannot race the window server.
    @Test func dismissDuringWriteBackWritesOnce() async throws {
        let (panel, writes) = makePanel()
        panel.trigger(replace: true)
        let window = try #require(panel.panel)
        var closes = 0
        let onClose = window.onClose
        window.onClose = {
            closes += 1
            onClose()
        }
        panel.write = { [weak panel] _, text in
            writes.texts.append(text)
            panel?.close()
            return .written
        }
        for _ in 0..<40 where writes.texts.isEmpty { try? await Task.sleep(for: .milliseconds(50)) }
        #expect(writes.texts == ["T:Hello"])
        #expect(panel.selection == nil)
        #expect(!window.isVisible)
        #expect(closes == 1)
    }

    /// `close()` re-entered from `onClose`, or via `resignKey` while closing, runs `onClose` once.
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

    /// The panel is the glass and nothing else: no hand-set corner radius, and no window shadow
    /// whose square frame-shape would draw a rectangular edge around the rounded glass.
    @Test func usesTheSystemGlassShapeOnly() async throws {
        let (panel, _) = makePanel(realWindow: true)
        panel.read = { $0(.failure(.unreadable)) }
        panel.trigger()
        let window = try #require(panel.panel)
        let glass = try #require(window.contentView as? NSGlassEffectView)
        #expect(glass.cornerRadius == NSGlassEffectView().cornerRadius)
        #expect(glass.style == NSGlassEffectView().style)
        #expect(!window.hasShadow)
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
        #expect(window.contentView is NSGlassEffectView)
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
