import AppKit
import SwiftUI
import SwiftData

@MainActor enum PreviewFixtures {
    nonisolated static let source =
        "「推敲」不仅是一个古老的文学典故，更是精准翻译的最高境界。我们像古人斟酌字句一样，在每一种语言的转换中反复衡量语境、语义与情感。不盲从表面的词义，而是用心去雕琢最自然、最贴切的表达，让每一次跨语言的沟通都兼具精准之真与文字之美。"
    static let live = ProcessInfo.processInfo.arguments.contains("--live")
    static let config = ServiceConfig(
        baseURL: URL(string: live ? "https://api.deepseek.com" : "https://preview.invalid")!,
        model: "deepseek-chat", apiKey: ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"] ?? "fixture",
        provider: .deepSeek)
    static let client = live ? ModelClient(capture: .off) : fixtureClient
    static let defaults = UserDefaults(suiteName: "dev.fahchen.owlet.panel-preview")!
    static let fixtureClient = ModelClient(
        transport: { request in
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            let messages = body["messages"] as! [[String: String]]
            let isLearning = messages[0]["content"]!.contains("key items")
            let content: [String: Any] =
                isLearning
                ? [
                    "items": [
                        [
                            "text": "deliberate", "language": "en", "kind": "word", "meaning": "仔细斟酌、深思熟虑。",
                            "context":
                                "we meticulously deliberate context, nuance, and emotion in every language pairing.",
                        ],
                        [
                            "text": "refine", "language": "en", "kind": "word", "meaning": "反复推敲，使表达更精准。",
                            "context": "we refine each expression for maximum naturalness.",
                        ],
                    ]
                ]
                : [
                    "source_language": "zh-Hans", "target_language": "en",
                    "segments": [
                        [
                            "source": source,
                            "target":
                                "\"Tui Qiao\" (deliberation) is not just an ancient literary allusion, but the ultimate pursuit of precise translation. Much like ancient poets weighing every character, we meticulously deliberate context, nuance, and emotion in every language pairing. Instead of stilted literal conversion, we refine each expression for maximum naturalness, making every cross-language exchange both perfectly accurate and beautifully articulate.",
                        ]
                    ],
                ]
            let serialized = String(decoding: try JSONSerialization.data(withJSONObject: content), as: UTF8.self)
            let data = try JSONSerialization.data(withJSONObject: [
                "choices": [["message": ["content": serialized], "finish_reason": "stop"]]
            ])
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }, promptForOperation: { _ in "Preview" }, capture: .off)
    static let model = TextProcessingModel(client: client, config: { config })
    static let learning: LearningModel = {
        let learning = LearningModel(client: client, config: { config })
        learning.autoRequest = { _ in false }
        return learning
    }()
    static let store = VocabularyStore(
        container: try! ModelContainer(
            for: VocabularyEntry.self, VocabularyContext.self, HistoryRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    static let collection = CollectionAction(store: store, client: client, config: { config })
}

@Observable @MainActor final class PreviewState: NSObject {
    static let shared = PreviewState()
    var mode = 3
    @objc func choose(_ item: NSMenuItem) { mode = item.tag }
}

struct PreviewView: View {
    @State private var state = PreviewState.shared
    var body: some View {
        ZStack {
            if let path = ProcessInfo.processInfo.environment["OWLET_PREVIEW_BACKGROUND"],
                let image = NSImage(contentsOfFile: path)
            {
                Image(nsImage: image).resizable().scaledToFill().frame(width: 1030, height: 550).clipped()
            }
            Group {
                switch state.mode {
                case 0: CompactProcessingView(summary: PreviewFixtures.source, status: "翻译中…", stop: {})
                case 1:
                    CompactNoticeView(
                        message: "模型未配置", summary: PreviewFixtures.source, retry: {}, close: {},
                        symbol: "lock.trianglebadge.exclamationmark", actionTitle: "设置",
                        recover: {})
                case 2:
                    CompactNoticeView(
                        message: "连接失败", summary: PreviewFixtures.source, retry: {}, close: {}, symbol: "network.slash",
                        actionTitle: "重试",
                        actionSymbol: "arrow.clockwise", recover: {})
                default:
                    ExpandedPanel(
                        model: PreviewFixtures.model, replace: nil, copy: { _ in },
                        collection: PreviewFixtures.collection, openNotebook: {}, notice: nil, recover: { _ in },
                        retry: {}, cancel: {}, openSettings: {}, close: {}, learning: PreviewFixtures.learning)
                }
            }
        }
        .frame(width: 1030, height: 550)
        .defaultAppStorage(PreviewFixtures.defaults)
        .environment(
            \.controlActiveState,
            ProcessInfo.processInfo.environment["OWLET_PREVIEW_ACTIVE"] == "1" ? .key : .inactive
        )
        .task {
            PreviewFixtures.model.input = PreviewFixtures.source
            await PreviewFixtures.model.process(to: "en")?.value
            PreviewFixtures.learning.autoRequest = { _ in false }
        }
        .onChange(of: state.mode) { _, mode in
            if mode >= 4, let request = LearningRequest.from(PreviewFixtures.model) {
                PreviewFixtures.learning.isExpanded = true
                PreviewFixtures.learning.generate(for: request)
            } else if mode == 3 {
                PreviewFixtures.learning.reset()
            }
        }
    }
}

final class PreviewPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@main struct PreviewApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let window = PreviewPanel(
            contentRect: NSRect(x: 100, y: 100, width: 1030, height: 550), styleMask: [.borderless], backing: .buffered,
            defer: false)
        let menu = NSMenu()
        let states = NSMenuItem(title: "预览状态", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for (index, title) in ["处理中", "未配置模型", "连接失败", "成功", "成功与学习"].enumerated() {
            let item = NSMenuItem(
                title: title, action: #selector(PreviewState.choose(_:)), keyEquivalent: String(index + 1))
            item.target = PreviewState.shared
            item.tag = index
            submenu.addItem(item)
        }
        submenu.addItem(.separator())
        submenu.addItem(NSMenuItem(title: "退出预览", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        states.submenu = submenu
        menu.addItem(states)
        app.mainMenu = menu
        window.minSize = NSSize(width: 1030, height: 550)
        window.maxSize = window.minSize
        window.title = "Owlet Panel Preview"
        window.backgroundColor = .clear
        window.isOpaque = false
        let surface = NSView(frame: window.contentLayoutRect)
        let host = NSHostingView(rootView: PreviewView())
        host.translatesAutoresizingMaskIntoConstraints = true
        host.frame = surface.bounds
        host.autoresizingMask = [.width, .height]
        surface.addSubview(host)
        window.contentView = surface
        window.center()
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        if let output = ProcessInfo.processInfo.environment["OWLET_PREVIEW_SCREENSHOTS"] {
            Task { @MainActor in
                do {
                    let directory = URL(fileURLWithPath: output, isDirectory: true)
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    for (mode, name) in [
                        "processing", "missing-config", "connection-failure", "success", "learning",
                        "learning-selected", "learning-deselected",
                    ]
                    .enumerated() {
                        PreviewState.shared.mode = min(mode, 4)
                        if mode >= 5, case .success(let items) = PreviewFixtures.learning.state, let item = items.first
                        {
                            let saved = PreviewFixtures.collection.setCollected(
                                mode == 5,
                                draft: VocabularyDraft(
                                    expression: item.text, language: item.language, context: item.context),
                                meaning: item.meaning)
                            guard saved else { throw NSError(domain: "PanelPreview.Collection", code: 1) }
                            let entry = try PreviewFixtures.store.entry(language: item.language, expression: item.text)
                            guard (entry != nil) == (mode == 5) else {
                                throw NSError(domain: "PanelPreview.Collection", code: 2)
                            }
                        }
                        // Give SwiftUI and the fixture transport time to finish rendering each state.
                        try await Task.sleep(for: .seconds(1))
                        host.layoutSubtreeIfNeeded()
                        let capture = Process()
                        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                        capture.arguments = [
                            "-x", "-l", String(window.windowNumber),
                            directory.appendingPathComponent("\(name).png").path,
                        ]
                        try capture.run()
                        capture.waitUntilExit()
                        guard capture.terminationStatus == 0 else {
                            throw NSError(domain: "PanelPreview.Screenshot", code: Int(capture.terminationStatus))
                        }
                    }
                } catch {
                    print("Screenshot export failed: \(error)")
                    exit(1)
                }
                app.terminate(nil)
            }
        }
        app.run()
    }
}
