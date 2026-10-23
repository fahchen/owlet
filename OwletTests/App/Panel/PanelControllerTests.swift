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

    /// An off-screen panel that records being presented and being asked to release the keyboard.
    /// The test host cannot hold key on a real panel, so "the panel is up" and "the write-back let
    /// the keyboard go" are asserted against these counters instead of window state.
    final class RecordingPanel: FloatingPanel {
        private(set) var releases = 0
        private(set) var shows = 0
        private(set) var closes = 0
        override func show(anchor: PanelPlacement.Anchor) { shows += 1 }
        override func releaseKeyboard() { releases += 1 }
        override func close() {
            closes += 1
            super.close()
        }
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
        let model = TextProcessingModel(
            client: ModelClient(transport: transport), config: { testConfig })
        let panel = PanelController(model: model, defaults: defaults)
        if !realWindow { panel.makeWindow = { (view: PanelRootView) in OffScreenPanel(rootView: view) } }
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

    /// A controller wired to one recording stub, so "the panel is up" and "it was dismissed" are
    /// counters rather than window state the test host cannot guarantee.
    func recordingPanel(gate: Gate? = nil, outcome: ReplaceOutcome = .pasted)
        -> (PanelController, Box, RecordingPanel)
    {
        let (panel, writes) = makePanel(gate: gate, outcome: outcome)
        let stub = RecordingPanel(rootView: PanelRootView(controller: panel))
        panel.makeWindow = { _ in stub }
        return (panel, writes, stub)
    }

    func settle() async {
        for _ in 0..<50 { await Task.yield() }
        try? await Task.sleep(for: .milliseconds(50))
    }

    @Test
    func successWritesOnce() async {
        let (panel, writes) = makePanel()
        panel.processSelection(replace: true)
        await settle()
        #expect(writes.texts == ["T:Hello"])
        #expect(panel.selection == nil)
        panel.replace(with: "again")
        #expect(writes.texts == ["T:Hello"])
    }

    @Test
    func plainTranslateDoesNotWrite() async {
        let (panel, writes) = makePanel()
        panel.processSelection()
        await settle()
        #expect(writes.texts.isEmpty)
        #expect(panel.expanded)
        panel.close()
    }

    /// The panel resolves the target exactly as the window does: the mapping decides from the
    /// detected source, unless the user pinned a language.
    @Test func thePanelUsesTheMappedTarget() async {
        let defaults = UserDefaults(suiteName: "PanelControllerTests.target.\(UUID().uuidString)")!
        SettingsStore.setTargetMapping(
            TargetMapping(targets: ["en": "ja"], fallback: "zh-Hans"), in: defaults)
        let captured = Captured()
        let model = TextProcessingModel(
            client: ModelClient(transport: { request in
                captured.request = request
                let reply =
                    #"{"source_language":"en","target_language":"ja","segments":[{"source":"Could you send me the report?","target":"報告書を送っていただけますか。"}]}"#
                return try await stub(body: chatBody(reply))(request)
            }),
            config: { testConfig })
        let panel = PanelController(model: model, defaults: defaults)
        panel.makeWindow = { OffScreenPanel(rootView: $0) }
        let text = "Could you send me the report?"
        let read = Selection(
            text: text, element: AXUIElementCreateApplication(1), app: nil,
            range: SelectedRange(location: 0, length: text.count))
        panel.read = { $0(.success(read)) }
        panel.processSelection()
        await settle()
        let body = String(decoding: captured.request?.httpBody ?? Data(), as: UTF8.self)
        #expect(body.contains("Target language: ja"))
        #expect(panel.model.state == .success("報告書を送っていただけますか。"))
        panel.close()
    }

    /// A pinned language wins over the mapping in the panel too.
    @Test func thePanelUsesThePinnedTarget() async {
        let defaults = UserDefaults(suiteName: "PanelControllerTests.pinned.\(UUID().uuidString)")!
        SettingsStore.setTargetMapping(
            TargetMapping(targets: ["en": "ja"], fallback: "zh-Hans"), in: defaults)
        SettingsStore.setPinnedTarget("zh-Hant", in: defaults)
        let captured = Captured()
        let model = TextProcessingModel(
            client: ModelClient(transport: { request in
                captured.request = request
                let reply =
                    #"{"source_language":"en","target_language":"zh-Hant","segments":[{"source":"Could you send me the report?","target":"請把報告寄給我。"}]}"#
                return try await stub(body: chatBody(reply))(request)
            }),
            config: { testConfig })
        let panel = PanelController(model: model, defaults: defaults)
        panel.makeWindow = { OffScreenPanel(rootView: $0) }
        let text = "Could you send me the report?"
        let read = Selection(
            text: text, element: AXUIElementCreateApplication(1), app: nil,
            range: SelectedRange(location: 0, length: text.count))
        panel.read = { $0(.success(read)) }
        panel.processSelection()
        await settle()
        let body = String(decoding: captured.request?.httpBody ?? Data(), as: UTF8.self)
        #expect(body.contains("Target language: zh-Hant"))
        panel.close()
    }

    @Test func lateResponseAfterCancelDoesNotWrite() async {
        let gate = Gate()
        let (panel, writes) = makePanel(gate: gate)
        panel.processSelection(replace: true)
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
        panel.processSelection(replace: true)
        await settle()
        panel.processSelection(replace: true)
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
        panel.processSelection(replace: true)
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
        panel.processSelection()
        #expect(panel.notice == nil)
        try? await Task.sleep(for: .milliseconds(1_100))
        #expect(panel.notice == .unreadable)
        reads.completions[0](.success(selection))
        await settle()
        #expect(panel.model.input == "Hello")
        panel.close()
    }

    /// Nothing readable turns the compact source bar into an empty, focused field; no request is
    /// sent and no notice is shown beside it (BDR-0018).
    @Test func unreadableOpensTheEmptySourceBar() async {
        let (panel, writes) = makePanel()
        panel.model.input = "Earlier text"
        panel.read = { $0(.failure(.unreadable)) }
        panel.processSelection(replace: true)
        await settle()
        #expect(!panel.expanded)
        #expect(panel.notice == .unreadable)
        #expect(panel.focusRequest > 0)
        #expect(panel.model.input.isEmpty)
        #expect(panel.model.state == .idle)
        #expect(!panel.cancelEndsEditing)
        #expect(writes.texts.isEmpty)
        panel.close()
    }

    /// Typed text is submitted with ⌘↩, and with no selection the result is never written back,
    /// even when a replace shortcut opened the editor.
    @Test func returnSubmitsManualInputWithoutWritingBack() async {
        let (panel, writes) = makePanel()
        panel.read = { $0(.failure(.unreadable)) }
        panel.processSelection(replace: true)
        panel.model.input = "Hello"
        panel.run(.replace)
        await settle()
        #expect(panel.model.state == .success("T:Hello"))
        #expect(panel.inlineNotice == nil)
        #expect(writes.texts.isEmpty)
        panel.close()
    }

    /// After the timeout opened the editor, a late read must not replace what the user typed.
    @Test func lateReadDoesNotOverwriteTypedText() async {
        let (panel, _) = makePanel()
        let reads = deferredReads(panel)
        panel.processSelection()
        try? await Task.sleep(for: .milliseconds(1_100))
        #expect(panel.notice == .unreadable)
        panel.model.input = "Typed"
        reads.completions[0](.success(selection))
        await settle()
        #expect(panel.model.input == "Typed")
        #expect(panel.selection == nil)
        panel.close()
    }

    /// The bar is the source: an edit before anything arrived, then ⌘↩, restarts with the edited
    /// text; Esc ends the edit first while there is text.
    @Test func editingTheBarRestartsWithTheEditedText() async {
        let gate = Gate()
        let (panel, _) = makePanel(gate: gate)
        panel.processSelection()
        await settle()
        #expect(panel.model.state == .loading)
        #expect(panel.cancelEndsEditing)
        panel.model.input = "Hello again"
        panel.run(.replace)
        await settle()
        #expect(panel.model.state == .loading)
        gate.release()
        gate.release()
        await settle()
        #expect(panel.model.input == "Hello again")
        panel.close()
    }

    /// No Screen Recording permission: the compact notice, and the capture never starts.
    @Test func regionWithoutPermissionShowsTheNotice() async {
        let (panel, _) = makePanel()
        var captures = 0
        panel.screenAccess = { false }
        panel.captureRegion = {
            captures += 1
            return nil
        }
        panel.processRegion()
        await settle()
        #expect(panel.notice == .screenPermission)
        #expect(!panel.expanded)
        #expect(captures == 0)
        panel.close()
    }

    /// Esc in the capture leaves nothing on screen.
    @Test func cancelledRegionShowsNothing() async {
        let (panel, _, stub) = recordingPanel()
        panel.screenAccess = { true }
        panel.captureRegion = { nil }
        panel.processRegion()
        await settle()
        #expect(stub.shows == 0)
        #expect(panel.model.state == .idle)
    }

    /// Recognised text is translated with the screenshot beside it, and never written back.
    @Test func regionTextIsTranslatedWithItsScreenshot() async {
        let (panel, writes) = makePanel()
        panel.screenAccess = { true }
        panel.captureRegion = { Data([1, 2, 3]) }
        panel.recognize = { _ in "Hello" }
        panel.processRegion()
        await settle()
        #expect(panel.model.input == "Hello")
        #expect(panel.model.sourceImage == Data([1, 2, 3]))
        #expect(panel.model.state == .success("T:Hello"))
        #expect(panel.selection == nil)
        #expect(writes.texts.isEmpty)
        panel.close()
    }

    /// A screenshot with no text is a failure, not an editor: there is nothing to translate, and a
    /// new region is the way out (BDR-0019).
    @Test func regionWithoutTextIsAFailure() async {
        let (panel, _) = makePanel()
        panel.screenAccess = { true }
        panel.captureRegion = { Data([1, 2, 3]) }
        panel.recognize = { _ in "" }
        panel.processRegion()
        await settle()
        #expect(panel.notice == .noTextInScreenshot)
        #expect(!panel.expanded)
        #expect(panel.model.input.isEmpty)
        #expect(panel.model.sourceImage == nil)
        #expect(panel.model.state == .idle)
        panel.close()
    }

    /// A capture that fails says so, rather than opening the selection's empty editor.
    @Test func failedCaptureIsAFailure() async {
        struct Failed: Error {}
        let (panel, _) = makePanel()
        var recognised = 0
        panel.screenAccess = { true }
        panel.captureRegion = { throw Failed() }
        panel.recognize = { _ in
            recognised += 1
            return ""
        }
        panel.processRegion()
        await settle()
        #expect(panel.notice == .captureFailed)
        #expect(!panel.expanded)
        #expect(recognised == 0)
        panel.close()
    }

    /// A click on the thumbnail zooms the screenshot; from the compact bar it opens the panel
    /// zoomed, and closing forgets the zoom.
    @Test func thumbnailZoomsAndOpensThePanel() async {
        let gate = Gate()
        let (panel, _) = makePanel(gate: gate)
        panel.screenAccess = { true }
        panel.captureRegion = { Data([1, 2, 3]) }
        panel.recognize = { _ in "Hello" }
        panel.processRegion()
        await settle()
        #expect(!panel.expanded)
        panel.toggleScreenshotZoom()
        #expect(panel.expanded)
        #expect(panel.screenshotZoomed)
        panel.toggleScreenshotZoom()
        #expect(!panel.screenshotZoomed)
        panel.toggleScreenshotZoom()
        panel.close()
        #expect(!panel.screenshotZoomed)
        gate.release()
    }

    /// Thumbnail is the default; with Enlarged in the settings the result opens on the full-width
    /// screenshot.
    @Test func screenshotDisplayDecidesHowTheResultOpens() async {
        let defaults = UserDefaults(suiteName: "PanelControllerTests.\(UUID().uuidString)")!
        let (panel, _) = makePanel(defaults: defaults)
        panel.screenAccess = { true }
        panel.captureRegion = { Data([1, 2, 3]) }
        panel.recognize = { _ in "Hello" }
        panel.processRegion()
        await settle()
        #expect(!panel.screenshotZoomed)
        defaults.set(ScreenshotDisplay.enlarged.rawValue, forKey: SettingsStore.screenshotDisplayKey)
        panel.processRegion()
        await settle()
        #expect(panel.screenshotZoomed)
        panel.close()
    }

    /// The next selection does not carry an earlier screenshot.
    @Test func aSelectionDropsTheScreenshot() async {
        let (panel, _) = makePanel()
        panel.model.sourceImage = Data([1])
        panel.processSelection()
        await settle()
        #expect(panel.model.sourceImage == nil)
        panel.close()
    }

    /// The panel translates the trimmed text, and the write-back restores the selection's indent and
    /// trailing newline around the result.
    @Test func writeBackKeepsTheSelectionsEdgeWhitespace() async {
        let (panel, writes) = makePanel()
        let padded = Selection(text: "  Hello\n", element: AXUIElementCreateApplication(1), app: nil, range: range)
        panel.read = { $0(.success(padded)) }
        panel.processSelection(replace: true)
        for _ in 0..<40 where writes.texts.isEmpty { try? await Task.sleep(for: .milliseconds(50)) }
        #expect(writes.texts == ["  T:Hello\n"])
    }

    /// A failed read clears the previous text, so the notice never sits beside a stale selection.
    @Test func failedReadClearsThePreviousText() async {
        let (panel, _) = makePanel()
        panel.model.input = "Earlier text"
        panel.read = { $0(.failure(.unreadable)) }
        panel.processSelection()
        #expect(panel.notice == .unreadable)
        #expect(panel.model.input.isEmpty)
        panel.close()
    }

    @Test func lateReadAfterCloseIsIgnored() async {
        let (panel, writes) = makePanel()
        let reads = deferredReads(panel)
        panel.processSelection(.polish, replace: true)
        try? await Task.sleep(for: .milliseconds(250))
        panel.close()
        reads.completions[0](.success(selection))
        await settle()
        #expect(panel.selection == nil)
        #expect(panel.model.input.isEmpty)
        #expect(panel.notice == nil)
        #expect(writes.texts.isEmpty)
    }

    /// A paste is a write too: the source is still consumed, no refusal is left, and a success
    /// closes the panel. Driven through the footer's entry point, which is what a click or ⌘↩
    /// reaches, so the assertion does not depend on the window's key state.
    @Test func pastedWriteConsumesTheSelection() async {
        let (panel, writes, stub) = recordingPanel(outcome: .pasted)
        panel.processSelection()
        await settle()
        #expect(panel.selection != nil)
        panel.replace(with: "T:Hello")
        for _ in 0..<40 where stub.closes == 0 { try? await Task.sleep(for: .milliseconds(50)) }
        #expect(writes.texts == ["T:Hello"])
        #expect(panel.selection == nil)
        #expect(panel.writebackRefusal == nil)
        #expect(stub.closes == 1)
    }

    @Test func rapidTriggersAcceptOnlyLatestRead() async {
        let (panel, writes) = makePanel()
        let reads = deferredReads(panel)
        panel.processSelection(replace: true)
        panel.processSelection()
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
        let (panel, writes, stub) = recordingPanel(gate: gate)
        panel.processSelection(replace: true)
        await settle()
        #expect(panel.notice == .translating)
        #expect(panel.replacing)
        stub.resignKey()
        #expect(stub.closes == 0)
        #expect(panel.notice == .translating)
        gate.release()
        await settle()
        #expect(writes.texts == ["T:Hello"])
        #expect(stub.closes == 1)
    }

    /// The write-back takes the keyboard away from the panel first — a synthetic ⌘V follows the
    /// keyboard — and a successful write then closes the panel.
    @Test func writeBackReleasesTheKeyboardThenCloses() async throws {
        final class Holder { var panel: RecordingPanel? }
        let holder = Holder()
        let (panel, writes) = makePanel()
        panel.makeWindow = { view in
            let stub = RecordingPanel(rootView: view)
            holder.panel = stub
            return stub
        }
        panel.processSelection(replace: true)
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
        for _ in 0..<40 where closes == 0 { try? await Task.sleep(for: .milliseconds(50)) }
        #expect(writes.texts == ["T:Hello"])
        // Released exactly once, and already released by the time the write ran.
        #expect(releasesAtWrite.withLock { $0 } == 1)
        #expect(!stub.isVisible)
        #expect(panel.selection == nil)
        #expect(closes == 1)
    }

    /// A write-back that never landed comes back with the result still in hand, so the failure is
    /// visible instead of the panel closing as if it had worked.
    @Test func refusedWriteBackKeepsTheResult() async {
        let (panel, _) = makePanel(outcome: .refused)
        panel.processSelection(replace: true)
        for _ in 0..<40 where panel.writebackRefusal == nil {
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(panel.writebackRefusal == .unwritten)
        #expect(panel.selection != nil)
    }

    /// A read-only selection is reported as such rather than as a generic failure.
    @Test func readOnlySelectionIsReportedAsUnwritable() async {
        let (panel, _) = makePanel(outcome: .unwritable)
        panel.processSelection(replace: true)
        for _ in 0..<40 where panel.writebackRefusal == nil {
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(panel.writebackRefusal == .unwritable)
        #expect(panel.selection != nil)
    }

    /// A successful write-back closes the panel instead of leaving a confirmation on screen.
    @Test func successfulWriteBackClosesThePanel() async throws {
        let (panel, _, stub) = recordingPanel()
        panel.processSelection()
        await settle()
        #expect(panel.model.state == .success("T:Hello"))
        #expect(stub.shows >= 1)
        panel.replace(with: "T:Hello")
        for _ in 0..<40 where stub.closes == 0 { try? await Task.sleep(for: .milliseconds(50)) }
        #expect(stub.closes == 1)
        #expect(panel.selection == nil)
    }

    /// Copying is a finished interaction too, so the panel closes once the result is copied.
    @Test func copyClosesThePanel() async throws {
        let (panel, _, stub) = recordingPanel()
        panel.processSelection()
        await settle()
        #expect(panel.model.state == .success("T:Hello"))
        var copied: String?
        panel.copy = { copied = $0 }
        panel.run(.copy)
        #expect(copied == "T:Hello")
        #expect(stub.closes == 1)
    }

    /// A click that misses the glass dismisses the panel; a click on the panel is not a dismissal.
    @Test func clicksOutsideTheGlassDismissAndClicksInsideDoNot() {
        let frame = NSRect(x: 100, y: 100, width: 560, height: 200)
        #expect(!FloatingPanel.dismisses(NSPoint(x: frame.midX, y: frame.midY), from: frame))
        #expect(!FloatingPanel.dismisses(NSPoint(x: frame.minX, y: frame.minY), from: frame))
        #expect(FloatingPanel.dismisses(NSPoint(x: frame.maxX + 1, y: frame.midY), from: frame))
        #expect(FloatingPanel.dismisses(NSPoint(x: frame.midX, y: frame.maxY + 1), from: frame))
    }

    /// The outside-click monitor lives exactly while the panel is visible, so a hidden panel cannot
    /// swallow the next click.
    @Test func mouseMonitorFollowsVisibility() async throws {
        let (panel, _) = makePanel(realWindow: true)
        panel.read = { $0(.failure(.unreadable)) }
        panel.processSelection()
        let window = try #require(panel.panel)
        #expect(window.watchesMouse)
        panel.close()
        #expect(!window.watchesMouse)
    }

    /// A write-back takes the panel off screen without dismissing it, and a miss brings it back with
    /// the result still copyable.
    @Test func writeBackBringsThePanelBackOnAMiss() async throws {
        let (panel, _, stub) = recordingPanel(outcome: .refused)
        panel.processSelection()
        await settle()
        #expect(panel.selection != nil)
        panel.replace(with: "T:Hello")
        for _ in 0..<40 where panel.writebackRefusal == nil { try? await Task.sleep(for: .milliseconds(50)) }
        await settle()
        #expect(panel.writebackRefusal == .unwritten)
        #expect(panel.selection != nil)
        // Presented again, because a missed write is exactly when the result needs copying.
        #expect(stub.shows >= 2)
        #expect(stub.closes == 0)
        panel.close()
    }

    /// `close()` re-entered from `onClose` runs `onClose` once, and a later key change is inert.
    @Test func closeIsNotReentrant() async throws {
        let (panel, _) = makePanel(realWindow: true)
        panel.read = { $0(.failure(.unreadable)) }
        panel.processSelection()
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

    /// Separate native surfaces are hosted on a transparent window, so their gaps stay clear.
    @Test func hostsContentWithoutAnOuterGlassSurface() async throws {
        let (panel, _) = makePanel(realWindow: true)
        panel.read = { $0(.failure(.unreadable)) }
        panel.processSelection()
        let window = try #require(panel.panel)
        #expect(!window.isOpaque)
        #expect(window.backgroundColor == .clear)
        #expect(!window.hasShadow)
        #expect(window.contentView != nil)
        #expect(!(window.contentView is NSGlassEffectView))
        panel.close()
    }

    /// Opening clears automatic focus; explicit key-view traversal can still reach the controls
    /// without depending on event dispatch while the screen is locked.
    @Test func opensWithNothingFocusedButTraversalStillReachesTheControls() async throws {
        let (panel, _) = makePanel(realWindow: true)
        // Not unreadable: that focuses the source bar's field on purpose.
        panel.read = { $0(.failure(.permission)) }
        panel.processSelection()
        let window = try #require(panel.panel)
        #expect(window.firstResponder === window)
        // The hosting view lays out and builds its key view loop asynchronously, and a full suite
        // keeps the main queue busy, so traversal is retried until it reaches a control rather than
        // after one fixed delay: how fast layout gets there is not what this test is about.
        for _ in 0..<40 where window.firstResponder === window {
            window.recalculateKeyViewLoop()
            window.selectNextKeyView(nil)
            await settle()
        }
        #expect(window.firstResponder !== window)
        panel.close()
    }

    /// Fixed mode: a user move of the glass-backed panel saves its top-center; self-placement does not.
    @Test func dragSavesFixedAnchor() async throws {
        let defaults = UserDefaults(suiteName: "PanelControllerTests.\(UUID().uuidString)")!
        let (panel, _) = makePanel(defaults: defaults, realWindow: true)
        panel.read = { $0(.failure(.unreadable)) }
        panel.processSelection()
        let window = try #require(panel.panel)
        #expect(SettingsStore.panelFixedAnchor(in: defaults) == nil)
        window.setFrameOrigin(NSPoint(x: window.frame.minX + 40, y: window.frame.minY - 30))
        await settle()
        #expect(
            SettingsStore.panelFixedAnchor(in: defaults)
                == NSPoint(x: window.glassFrame.midX, y: window.glassFrame.maxY))
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
        panel.processSelection()
        await settle()
        let window = try #require(panel.panel)
        let rect = PanelPlacement.appKitRect(fromAX: axRect, primaryScreenHeight: screen.frame.height)
        // The panel is placed by the same function the app uses, at whatever size it is now: this
        // stays true when the panel's width changes and the screen clamp moves it.
        // The panel sits below the selection and inside the screen. The exact frame depends on the
        // live mouse location, and its arithmetic belongs to PanelPlacementTests; the resize is
        // spring animated, so allow it to settle before reading the frame.
        try? await Task.sleep(for: .milliseconds(600))
        #expect(window.glassFrame.maxY <= rect.minY)
        #expect(window.glassFrame.minX >= visible.minX)
        #expect(window.glassFrame.maxX <= visible.maxX)
        window.setFrameOrigin(NSPoint(x: window.frame.minX + 40, y: window.frame.minY - 30))
        await settle()
        #expect(SettingsStore.panelFixedAnchor(in: defaults) == nil)
        panel.close()
        gate.release()
    }

    /// Escape invalidates the active request and closes instead of leaving a cancelled notice.
    @Test func escapeClosesAndCancelsProcessing() async {
        let gate = Gate()
        let (panel, writes, stub) = recordingPanel(gate: gate)
        panel.processSelection()
        await settle()
        #expect(panel.model.state == .loading)
        panel.run(.cancel)
        #expect(stub.closes == 1)
        #expect(panel.notice == nil)
        #expect(panel.model.state == .idle)
        #expect(!panel.expanded)
        gate.release()
        await settle()
        #expect(writes.texts.isEmpty)
        #expect(!panel.expanded)
    }

    // MARK: Streaming (BDR-0017)

    /// A panel whose stream shows its one piece, then holds until the test releases it.
    func receivingPanel() -> (PanelController, StreamStub) {
        var client = ModelClient()
        client.capture = .off
        client.transport = { _ in
            Issue.record("with a stream fixture, the whole-shot transport must never run")
            throw TestTransportError()
        }
        let stub = StreamStub(
            [chatStreamFrame(TestReplies.reply(for: "Hello")), "data: [DONE]\n\n"],
            holding: true)
        client.streamTransport = stub.streamTransport
        let model = TextProcessingModel(client: client, config: { testConfig })
        let panel = PanelController(
            model: model, defaults: UserDefaults(suiteName: "PanelControllerTests.receiving.\(UUID().uuidString)")!)
        panel.makeWindow = { OffScreenPanel(rootView: $0) }
        panel.read = { $0(.success(selection)) }
        panel.copy = { _ in }
        return (panel, stub)
    }

    /// While a result is still arriving, a press on copy answers with the reason it must wait, and
    /// only the finished result acts.
    @Test func aPressWhileReceivingGivesAReasonAndTheResultActs() async {
        let (panel, stub) = receivingPanel()
        panel.processSelection()
        for _ in 0..<200 where panel.model.receiving == nil {
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(panel.model.isReceiving)
        panel.run(.copy)
        #expect(panel.notice == .receiving)
        #expect(panel.expanded)
        stub.release()
        for _ in 0..<200 where panel.model.isReceiving {
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(panel.model.state == .success("T:Hello"))
        // The note belongs to the wait: the finished result acts normally again.
        panel.run(.copy)
        #expect(panel.notice == nil)
    }
}
