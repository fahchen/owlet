import AppKit
import ApplicationServices
import Foundation
import Testing

@testable import Owlet

/// Serialized: each test shows a real panel, and a panel closes when another one takes key.
@MainActor @Suite(.serialized)
struct PanelControllerTests {
    let source = Source(pid: 1, document: nil, text: "Hello", location: 0, length: 5)
    var selection: Selection {
        Selection(text: "Hello", element: AXUIElementCreateApplication(1), app: nil, source: source)
    }

    /// Transport that waits until released, so tests control when a response arrives.
    final class Gate: @unchecked Sendable {
        var continuations: [CheckedContinuation<Void, Never>] = []
        func release() { continuations.removeFirst().resume() }
    }

    func makePanel(gate: Gate? = nil, writable: Bool = true) -> (PanelController, Box) {
        let transport: Transport = { request in
            if let gate { await withCheckedContinuation { gate.continuations.append($0) } }
            return try await stub(body: chatBody(TestReplies.reply(for: "Hello")))(request)
        }
        let model = TranslationModel(
            client: ModelClient(transport: transport), config: { testConfig })
        let panel = PanelController(model: model)
        let writes = Box()
        let selection = selection
        panel.read = { $0(.success(selection)) }
        panel.write = { _, text in
            writes.texts.append(text)
            return writable
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

    /// Changed or read-only selection: write is refused, compact stale notice keeps the result copyable.
    @Test(.disabled("Hangs in app-hosted test run once the panel expands; needs investigation"))
    func refusedWriteKeepsResult() async {
        let (panel, writes) = makePanel(writable: false)
        panel.trigger(replace: true)
        await settle()
        #expect(writes.texts == ["T:Hello"])
        #expect(!panel.expanded)
        #expect(panel.notice == .stale)
        #expect(panel.replaceMessage != nil)
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

    @Test func readPastBudgetIsUnreadable() async {
        let (panel, _) = makePanel()
        _ = deferredReads(panel)
        panel.trigger()
        #expect(panel.notice == nil)
        try? await Task.sleep(for: .milliseconds(250))
        #expect(panel.notice == .unreadable)
        panel.close()
    }

    @Test func lateReadAfterTimeoutOrCloseIsIgnored() async {
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

    @Test func panelFrameStaysInsideVisibleFrame() {
        let visible = NSRect(x: 0, y: 0, width: 1000, height: 800)
        let size = NSSize(width: 560, height: 300)
        #expect(
            FloatingPanel.frame(size: size, topLeft: NSPoint(x: 100, y: 700), within: visible)
                == NSRect(x: 100, y: 400, width: 560, height: 300))
        #expect(
            FloatingPanel.frame(size: size, topLeft: NSPoint(x: 900, y: 100), within: visible)
                == NSRect(x: 440, y: 0, width: 560, height: 300))
        #expect(
            FloatingPanel.frame(
                size: NSSize(width: 560, height: 1200), topLeft: NSPoint(x: -50, y: 900), within: visible)
                == NSRect(x: 0, y: 0, width: 560, height: 800))
    }
}
