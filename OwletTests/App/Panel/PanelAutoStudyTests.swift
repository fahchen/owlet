import AppKit
import SwiftData
import SwiftUI
import Synchronization
import Testing

@testable import Owlet

/// The panel honours the auto-request Study switch: it opens the study column and requests on its own,
/// whether the result arrives while the panel is up or the panel opens on a finished result.
@MainActor @Suite(.serialized)
struct PanelAutoStudyTests {
    final class Calls: Sendable { let count = Mutex(0) }

    func learning(_ calls: Calls) -> LearningModel {
        let payload = learningJSON(
            #"{"items":[{"text":"hello","language":"en","kind":"word","meaning":"你好。","context":"Hello"}]}"#)
        let learning = LearningModel(
            client: ModelClient(transport: { request in
                calls.count.withLock { $0 += 1 }
                return try await stub(body: learningBody(payload))(request)
            }),
            config: { testConfig })
        learning.autoRequest = { _ in true }
        return learning
    }

    /// The real panel content in a window, so its lifecycle runs as on screen.
    func show(_ model: TextProcessingModel, learning: LearningModel) throws -> NSWindow {
        let schema = Schema([HistoryRecord.self, VocabularyEntry.self, VocabularyContext.self])
        let container = try ModelContainer(
            for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let collection = CollectionAction(
            store: VocabularyStore(container: container), client: ModelClient(transport: stub(body: "{}")),
            config: { testConfig })
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 821, height: 500), styleMask: [.borderless],
            backing: .buffered, defer: false)
        window.contentView = NSHostingView(
            rootView: ExpandedPanel(
                model: model, replace: nil, copy: { _ in }, collection: collection, openNotebook: nil,
                notice: nil, recover: { _ in }, retry: {}, cancel: {}, openSettings: {}, close: {},
                lookupOrigin: nil, learning: learning))
        window.orderFrontRegardless()
        return window
    }

    func translation() -> TextProcessingModel {
        let model = TextProcessingModel(
            client: ModelClient(transport: stub(body: chatBody(TestReplies.reply(for: "Hello")))),
            config: { testConfig })
        model.input = "Hello"
        return model
    }

    func waitForItems(_ learning: LearningModel) async {
        for _ in 0..<40 {
            if case .success = learning.state { return }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    @Test func aResultArrivingInTheOpenPanelOpensStudy() async throws {
        let calls = Calls()
        let learning = learning(calls)
        let model = translation()
        let window = try show(model, learning: learning)
        defer { window.close() }
        await model.process(to: "zh-Hans")?.value
        await waitForItems(learning)
        #expect(learning.isExpanded)
        #expect(calls.count.withLock { $0 } == 1)
    }

    @Test func thePanelOpeningOnAFinishedResultOpensStudy() async throws {
        let calls = Calls()
        let learning = learning(calls)
        let model = translation()
        await model.process(to: "zh-Hans")?.value
        let window = try show(model, learning: learning)
        defer { window.close() }
        await waitForItems(learning)
        #expect(learning.isExpanded)
        #expect(calls.count.withLock { $0 } == 1)
    }
}
