import AppKit
import ApplicationServices
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
        transport: fixtureTransport, promptForOperation: { _ in "Preview" }, capture: .off)
    /// The fixture answer after a pause, so the transition recording sees 翻译中 before the result.
    static let slowClient = ModelClient(
        transport: { request in
            try await Task.sleep(for: .seconds(1.5))
            return try await fixtureTransport(request)
        }, promptForOperation: { _ in "Preview" }, capture: .off)
    nonisolated static let fixtureTransport: Transport = { request in
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        let messages = body["messages"] as! [[String: String]]
        let isLearning = messages[0]["content"]!.contains("key items")
        let target =
            messages[0]["content"]!.components(separatedBy: "Target language: ").dropFirst().first?
            .components(separatedBy: ".").first ?? "en"
        if messages[0]["content"]!.contains("Explain the text a reader selected") {
            return try lookupFixture(system: messages[0]["content"]!, data: messages[1]["content"]!, url: request.url!)
        }
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
                "source_language": "zh-Hans", "target_language": target,
                "segments": [
                    [
                        "source": source,
                        "target": translations[target]
                            ?? "\"Tui Qiao\" (deliberation) is not just an ancient literary allusion, but the ultimate pursuit of precise translation. Much like ancient poets weighing every character, we meticulously deliberate context, nuance, and emotion in every language pairing. Instead of stilted literal conversion, we refine each expression for maximum naturalness, making every cross-language exchange both perfectly accurate and beautifully articulate.",
                    ]
                ],
            ]
        let serialized = String(decoding: try JSONSerialization.data(withJSONObject: content), as: UTF8.self)
        let data = try JSONSerialization.data(withJSONObject: [
            "choices": [["message": ["content": serialized], "finish_reason": "stop"]]
        ])
        return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
    /// Lookups answer after a pause so loading is visible. "literary" breaks the lookup contract the
    /// first time only, so the failure and 重试 paths can be driven by hand.
    nonisolated(unsafe) static var failedOnce = false
    nonisolated static func lookupFixture(system: String, data: String, url: URL) throws -> (Data, URLResponse) {
        Thread.sleep(forTimeInterval: 1.2)
        let query = try JSONSerialization.jsonObject(with: Data(data.utf8)) as! [String: Any]
        let text = query["text"] as! String
        let sentence = text.hasSuffix(".") || text.hasSuffix("。")
        let definition = system.components(separatedBy: "definition_language is ")[1].components(separatedBy: ".")[0]
        let content: String
        if text == "literary", !failedOnce {
            failedOnce = true
            content = "not json"
        } else {
            let answer: [String: Any] = [
                "text": text, "language": query["language"] ?? NSNull(), "definition_language": definition,
                "meaning": query["context"] is NSNull
                    ? "（预览）「\(text)」的一般含义。" : "（预览）「\(text)」在这句话中的意思。",
                "lemma": text == "weighing" ? "weigh" : NSNull(),
                // Not a real reading: the fixture cannot know one, so it must not look like one.
                "pronunciation": sentence ? NSNull() : "预览读音",
                "part_of_speech": sentence ? NSNull() : "词",
            ]
            content = String(decoding: try JSONSerialization.data(withJSONObject: answer), as: UTF8.self)
        }
        let body = try JSONSerialization.data(withJSONObject: [
            "choices": [["message": ["content": content], "finish_reason": "stop"]]
        ])
        return (body, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
    /// Results in the other preview targets, so Chinese and Japanese word hits can be checked.
    nonisolated static let translations = [
        "ja": "「推敲」は古い文学の故事であるだけでなく、正確な翻訳の最高の境地でもある。私たちは言葉を一つずつ吟味し、自然な表現を磨き上げる。",
        "zh-Hans": "推敲不仅是古老的文学典故，也是精准翻译的最高境界。我们反复斟酌语境、语义与情感，打磨最自然的表达。",
    ]
    static let model = TextProcessingModel(client: client, config: { config })
    static let store = VocabularyStore(
        container: try! ModelContainer(
            for: VocabularyEntry.self, VocabularyContext.self, HistoryRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    static let collection = CollectionAction(store: store, client: client, config: { config })
    /// OWLET_PREVIEW_NO_VOICE stands in for a Mac without the voice, without touching system voices.
    static let lookups: LookupPresenter = {
        let lookups = LookupPresenter(
            store: LookupStore(client: client, config: { config }, defaults: defaults),
            speech: ProcessInfo.processInfo.environment["OWLET_PREVIEW_NO_VOICE"] == "1"
                ? LookupSpeech(canSpeak: { _ in false }, speak: { _, _ in }, stop: {}) : .live)
        // As in the app: the card's 加入生词本 writes through the same notebook the pages use.
        lookups.collection = collection
        return lookups
    }()
    static let learning: LearningModel = {
        let learning = LearningModel(client: client, config: { config })
        learning.autoRequest = { _ in false }
        return learning
    }()
    /// The word the card preview looks up: the first word of the fixture source, which is in English.
    static let cardQuery: LookupQuery? = {
        guard case .success(let query) = LookupQuery.make(
            selection: NSRange(location: 0, length: 8), in: source,
            origin: LookupOrigin(language: "en", definitionLanguage: "zh-Hans"))
        else { return nil }
        return query
    }()
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
                case 6:
                    // The card itself, so its layout (bookmark beside 发音) can be read off a window
                    // screenshot without hunting for the transient popover.
                    VStack {
                        if let query = PreviewFixtures.cardQuery, case .card(let shown, let other)? = PreviewFixtures.lookups.mode {
                            LookupCard(presenter: PreviewFixtures.lookups, query: shown, other: other)
                                .background(Color(nsColor: .windowBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        } else {
                            ProgressView()
                        }
                    }
                    .task(id: state.mode) {
                        guard state.mode == 6, let query = PreviewFixtures.cardQuery else { return }
                        PreviewFixtures.lookups.lookUp(query, at: nil, in: nil)
                    }
                default:
                    ExpandedPanel(
                        model: PreviewFixtures.model, replace: nil, copy: { _ in },
                        collection: PreviewFixtures.collection, openNotebook: {}, notice: nil, recover: { _ in },
                        retry: {}, cancel: {}, openSettings: {}, close: {},
                        lookupOrigin: PreviewFixtures.model.languages.map {
                            .result(of: .translate, languages: $0, mapping: TargetMapping(targets: [:], fallback: "zh-Hans"))
                        }, learning: PreviewFixtures.learning
                    )
                    .panelSurface(.regular)
                    .environment(\.lookups, PreviewFixtures.lookups)
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
    /// Keeps the real panel controller alive for `--panel`.
    @MainActor static var panel: PanelController?

    /// OWLET_PREVIEW_CARD_CHECK=1: drives the card's 加入生词本 through the real presenter and
    /// notebook, prints one line, and exits — the same evidence `--panel` gives by hand, without
    /// needing synthetic clicks. No model is called for the collect action itself.
    @MainActor static func runCardCheck(_ controller: PanelController) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard let languages = PreviewFixtures.model.languages else {
                print("CARD-CHECK FAIL: no result language")
                NSApp.terminate(nil)
                return
            }
            let origin = LookupOrigin.result(
                of: .translate, languages: languages,
                mapping: TargetMapping(targets: [:], fallback: "zh-Hans"))
            guard
                case .success(let query) = LookupQuery.make(
                    selection: NSRange(location: 0, length: 8), in: PreviewFixtures.source, origin: origin)
            else {
                print("CARD-CHECK FAIL: no query")
                NSApp.terminate(nil)
                return
            }
            controller.lookups.lookUp(query, at: nil, in: nil)
            try? await Task.sleep(for: .seconds(3))
            // The presenter stamps a query with the current settings before requesting, so the
            // answer is keyed under the stamped query, not the one handed in.
            let stamped = PreviewFixtures.lookups.store.stamped(query)
            guard case .success(let result) = PreviewFixtures.lookups.store.entries[stamped] else {
                print("CARD-CHECK FAIL: no lookup answer")
                NSApp.terminate(nil)
                return
            }
            let language = stamped.lookupLanguage(from: result) ?? "nil"
            let collection = PreviewFixtures.collection
            let before = collection.isCollected(language: language, expression: stamped.text)
            collection.setCollected(true, query: stamped, result: result)
            let after = collection.isCollected(language: language, expression: stamped.text)
            let entry = try? PreviewFixtures.store.entry(language: language, expression: stamped.text)
            let meaning = entry?.meaning ?? ""
            let contexts = entry?.contexts.count ?? 0
            collection.setCollected(false, query: stamped, result: result)
            let removed = collection.isCollected(language: language, expression: stamped.text)
            print(
                "CARD-CHECK text=\(stamped.text) language=\(language) before=\(before) after=\(after) "
                    + "meaning=\(meaning) contexts=\(contexts) removed=\(removed)")
            let passed = !before && after && !meaning.isEmpty && contexts == 1 && !removed
            print(passed ? "CARD-CHECK PASS" : "CARD-CHECK FAIL")
            NSApp.terminate(nil)
        }
    }

    @MainActor static func main() {
        let app = NSApplication.shared
        if ProcessInfo.processInfo.arguments.contains("--main") {
            showMainWindow(app)
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--panel") {
            // The real controller and FloatingPanel, as the shortcut opens them: an accessory app
            // with a non-activating panel, so focus, Esc and outside clicks behave as in Owlet.
            app.setActivationPolicy(.accessory)
            // The fixture answers in English; pin it in the preview's own suite, not Owlet's.
            SettingsStore.setPinnedTarget(
                ProcessInfo.processInfo.environment["OWLET_PREVIEW_TARGET"] ?? "en", in: PreviewFixtures.defaults)
            // Appearance is set on this process only; the system setting is never touched.
            app.appearance = ProcessInfo.processInfo.environment["OWLET_PREVIEW_APPEARANCE"].flatMap {
                switch $0 {
                case "dark": NSAppearance(named: .darkAqua)
                case "contrast": NSAppearance(named: .accessibilityHighContrastAqua)
                case "darkContrast": NSAppearance(named: .accessibilityHighContrastDarkAqua)
                default: nil
                }
            }
            let controller = PanelController(
                model: PreviewFixtures.model, defaults: PreviewFixtures.defaults, lookups: PreviewFixtures.lookups)
            controller.read = { completion in
                completion(
                    .success(
                        Selection(
                            text: PreviewFixtures.source, element: AXUIElementCreateSystemWide(), app: nil,
                            range: nil)))
            }
            controller.collection = PreviewFixtures.collection
            panel = controller
            DispatchQueue.main.async { controller.processSelection() }
            if ProcessInfo.processInfo.environment["OWLET_PREVIEW_CARD_CHECK"] == "1" {
                runCardCheck(controller)
            }
            app.run()
            return
        }
        app.setActivationPolicy(.regular)
        if let output = ProcessInfo.processInfo.environment["OWLET_PREVIEW_TRANSITION"] {
            recordTransition(to: output)
            app.run()
            return
        }
        let window = PreviewPanel(
            contentRect: NSRect(x: 100, y: 100, width: 1030, height: 550), styleMask: [.borderless], backing: .buffered,
            defer: false)
        let menu = NSMenu()
        let states = NSMenuItem(title: "预览状态", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for (index, title) in ["处理中", "未配置模型", "连接失败", "成功", "成功与学习", "查词卡"].enumerated() {
            let item = NSMenuItem(
                title: title, action: #selector(PreviewState.choose(_:)),
                keyEquivalent: index < 5 ? String(index + 1) : String(index + 1))
            item.target = PreviewState.shared
            item.tag = index == 5 ? 6 : index
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

    /// Runs the production path, PanelController and FloatingPanel, from 翻译中 to the result, and
    /// records the panel's screen region as a movie. The recorder exits on its own; nothing on the
    /// main thread waits for it, so the panel keeps animating while it records.
    @MainActor static func recordTransition(to output: String) {
        let model = TextProcessingModel(client: PreviewFixtures.slowClient, config: { PreviewFixtures.config })
        // The fixture answers in English, so the target is pinned to match; the suite is the preview's own.
        let defaults = UserDefaults(suiteName: "dev.fahchen.owlet.panel-preview.transition")!
        defaults.set("en", forKey: SettingsStore.pinnedTargetKey)
        let controller = PanelController(model: model, defaults: defaults)
        let selection = Selection(
            text: PreviewFixtures.source, element: AXUIElementCreateApplication(getpid()), app: nil, range: nil)
        controller.read = { $0(.success(selection)) }
        NSApplication.shared.activate(ignoringOtherApps: true)
        controller.processSelection()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard let window = controller.panel, let screen = window.screen ?? NSScreen.main else { exit(1) }
            let top = Int(NSScreen.screens[0].frame.maxY - window.frame.maxY)
            let capture = Process()
            capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            capture.arguments = [
                "-x", "-v", "-V", "4",
                "-R\(Int(window.frame.minX)),\(top),\(Int(window.frame.width)),\(Int(min(560, screen.frame.height)))",
                output,
            ]
            capture.terminationHandler = { process in exit(process.terminationStatus) }
            do { try capture.run() } catch { exit(1) }
        }
    }
}

/// `--main`: the main window's three reading pages with fixture data in memory, so lookups in them
/// can be checked by hand without the user's store or a real model.
struct MainPreview: View {
    @State private var page = 0
    let history = HistoryStore(container: PreviewFixtures.store.container)

    var body: some View {
        NavigationSplitView {
            List(selection: Binding<Int?>(get: { page }, set: { page = $0 ?? page })) {
                Label("翻译与润色", systemImage: "translate").tag(0)
                Label("生词本", systemImage: "books.vertical").tag(1)
                Label("历史记录", systemImage: "clock").tag(2)
            }
        } detail: {
            switch page {
            case 0:
                TextProcessingView(model: PreviewFixtures.model, openSettings: {}, collection: PreviewFixtures.collection)
            case 1: VocabularyView(collection: PreviewFixtures.collection, openProcessing: {})
            default: HistoryView(store: history, collection: PreviewFixtures.collection, openProcessing: {})
            }
        }
        .modelContainer(PreviewFixtures.store.container)
        .environment(\.lookups, PreviewFixtures.lookups)
        .defaultAppStorage(PreviewFixtures.defaults)
        .task {
            PreviewFixtures.model.input = PreviewFixtures.source
            await PreviewFixtures.model.process(to: "en")?.value
            _ = PreviewFixtures.collection.setCollected(
                true,
                draft: VocabularyDraft(
                    expression: "deliberate", language: "en",
                    context: "we meticulously deliberate context, nuance, and emotion in every language pairing."),
                meaning: "仔细斟酌、深思熟虑。")
            _ = try? history.record(
                operation: .translate, source: PreviewFixtures.source,
                result: "Much like ancient poets weighing every character, we refine each expression.",
                language: "en")
        }
    }
}

@MainActor func showMainWindow(_ app: NSApplication) {
    app.setActivationPolicy(.regular)
    SettingsStore.setPinnedTarget("en", in: PreviewFixtures.defaults)
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 1080, height: 690),
        styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView], backing: .buffered,
        defer: false)
    window.title = "Owlet Main Preview"
    window.contentView = NSHostingView(rootView: MainPreview())
    window.setFrameTopLeftPoint(NSPoint(x: 200, y: (NSScreen.main?.visibleFrame.maxY ?? 900) - 40))
    window.makeKeyAndOrderFront(nil)
    app.activate(ignoringOtherApps: true)
    app.run()
}
