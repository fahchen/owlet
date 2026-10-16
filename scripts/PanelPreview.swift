import AVFoundation
import AppKit
import ApplicationServices
import SwiftUI
import SwiftData

@MainActor enum PreviewFixtures {
    nonisolated static let sentences = [
        "蒹葭蒼蒼，白露為霜。\n",
        "所謂伊人，在水一方。\n",
        "溯洄從之，道阻且長。\n",
        "溯游從之，宛在水中央。",
    ]
    nonisolated static let source = sentences.joined()
    static let live = ProcessInfo.processInfo.arguments.contains("--live")
    static let config = ServiceConfig(
        baseURL: URL(string: live ? "https://api.deepseek.com" : "https://preview.invalid")!,
        model: "deepseek-chat", apiKey: ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"] ?? "fixture",
        supportsJSONSchema: ServicePreset.deepSeek.supportsJSONSchema)
    static let client = live ? ModelClient(capture: .off) : fixtureClient
    static let defaults = UserDefaults(suiteName: "dev.fahchen.owlet.panel-preview")!
    static let fixtureClient = ModelClient(
        transport: fixtureTransport, promptForOperation: { _ in "Preview" }, capture: .off)
    /// The fixture answer after a pause, so the transition recording sees Translating… before the result.
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
        let targets = translations[target] ?? translations["en"]!
        let content: [String: Any] =
            isLearning
            ? [
                "items": [
                    [
                        "text": "lush", "language": "en", "kind": "word",
                        "meaning": "Growing thickly and richly; full of green.",
                        "context": "The reeds are lush and gray-green;", "lemma": NSNull(),
                    ],
                    [
                        "text": "long for", "language": "en", "kind": "phrase",
                        "meaning": "To miss and want someone very much, often someone far away.",
                        "context": "The one I long for is somewhere across the water.", "lemma": NSNull(),
                    ],
                    [
                        "text": "seek", "language": "en", "kind": "word", "meaning": "To look for; to try to find.",
                        "context": "Upstream I go to seek her,", "lemma": NSNull(),
                    ],
                ]
            ]
            : [
                "source_language": "zh-Hant", "target_language": target,
                "segments": sentences.indices.map { ["source": sentences[$0], "target": targets[$0]] },
            ]
        let serialized = String(decoding: try JSONSerialization.data(withJSONObject: content), as: UTF8.self)
        let data = try JSONSerialization.data(withJSONObject: [
            "choices": [["message": ["content": serialized], "finish_reason": "stop"]]
        ])
        return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
    /// Lookups answer after a pause so loading is visible. "frost" breaks the lookup contract the
    /// first time only, so the failure and Retry paths can be driven by hand.
    nonisolated(unsafe) static var failedOnce = false
    nonisolated static func lookupFixture(system: String, data: String, url: URL) throws -> (Data, URLResponse) {
        Thread.sleep(forTimeInterval: 1.2)
        let query = try JSONSerialization.jsonObject(with: Data(data.utf8)) as! [String: Any]
        let text = query["text"] as! String
        let sentence = text.hasSuffix(".") || text.hasSuffix("。")
        let definition = system.components(separatedBy: "definition_language is ")[1].components(separatedBy: ".")[0]
        let content: String
        if text == "frost", !failedOnce {
            failedOnce = true
            content = "not json"
        } else {
            let answer: [String: Any] = [
                "text": text, "language": query["language"] ?? NSNull(), "definition_language": definition,
                "meaning": query["context"] is NSNull
                    ? "（预览）「\(text)」的一般含义。" : "（预览）「\(text)」在这句话中的意思。",
                "lemma": text == "seems" ? "seem" : NSNull(),
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
    nonisolated static let translations: [String: [String]] = [
        "en": [
            "The reeds are lush and gray-green; the white dew has turned to frost. ",
            "The one I long for is somewhere across the water. ",
            "Upstream I go to seek her, but the way is hard and long. ",
            "Downstream I go to seek her, and there she seems, in the middle of the water.",
        ],
        "ja": [
            "葦は青々と茂り、白露は霜となる。", "思うあの人は、川の向こう岸にいる。",
            "流れをさかのぼって追えば、道は険しく遠い。", "流れに沿って追えば、まるで水の真ん中にいるようだ。",
        ],
        "zh-Hans": [
            "芦苇苍苍，白露凝成了霜。", "我思念的那个人，就在河水的另一边。",
            "逆流而上去追寻她，道路艰险又漫长。", "顺流而下去追寻她，她仿佛就在水中央。",
        ],
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
        // As in the app: the card's Add to Notebook writes through the same notebook the pages use.
        lookups.collection = collection
        return lookups
    }()
    static let learning: LearningModel = {
        let learning = LearningModel(client: client, config: { config })
        learning.autoRequest = { _ in false }
        return learning
    }()
    /// The word the card preview looks up: 蒹葭, the first word of the fixture source.
    static let cardQuery: LookupQuery? = {
        guard case .success(let query) = LookupQuery.make(
            selection: NSRange(location: 0, length: 2), in: source,
            origin: LookupOrigin(language: "zh-Hant", definitionLanguage: "en"))
        else { return nil }
        return query
    }()
}

@Observable @MainActor final class PreviewState: NSObject {
    static let shared = PreviewState()
    var mode = 3
    /// Where the glass sits in the window, written beside each screenshot so it can be cut out exactly.
    var panelFrame: CGRect = .zero
    /// The main window's page, driven from outside by `--app-shots`.
    var mainPage = 0
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
                    // The card itself, so its layout (bookmark beside Speak) can be read off a window
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
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { state.panelFrame = $0 }
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

/// `--settings`: renders the General, Debug and Model settings panes to PNG offscreen. Drawing a view into a bitmap
/// needs no Screen Recording grant, unlike the window screenshots `--screenshots` takes, so the pane
/// can be exported on a machine that has never granted it. The pane is a plain grouped `Form` with
/// no glass surface, so the offscreen draw is faithful to the window.
@MainActor enum SettingsPanePreview {
    /// Wide enough for the longest toggle label, tall enough that every row of the grouped `Form` is
    /// in frame without scrolling.
    static let size = NSSize(width: 620, height: 660)

    struct Variant {
        let name: String
        let wholeField: Bool
        let dark: Bool
    }

    /// The new whole-field toggle, in both states, each in light and dark. Off is the default.
    static let variants = [
        Variant(name: "settings-general-off", wholeField: false, dark: false),
        Variant(name: "settings-general-on", wholeField: true, dark: false),
        Variant(name: "settings-general-off-dark", wholeField: false, dark: true),
        Variant(name: "settings-general-on-dark", wholeField: true, dark: true),
    ]

    static func export(to output: String) async -> Bool {
        let directory = URL(fileURLWithPath: output, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            print("Settings export failed: \(error)")
            return false
        }
        for variant in variants {
            // The preview's own suite, so the export can neither read nor write the real settings.
            PreviewFixtures.defaults.set(variant.wholeField, forKey: SettingsStore.wholeFieldTextKey)
            guard let data = png(variant) else {
                print("Settings export failed: \(variant.name)")
                return false
            }
            do {
                try data.write(to: directory.appendingPathComponent("\(variant.name).png"))
            } catch {
                print("Settings export failed: \(error)")
                return false
            }
        }
        PreviewFixtures.defaults.removeObject(forKey: SettingsStore.wholeFieldTextKey)
        guard exportDebug(to: directory) else { return false }
        return await exportModel(to: directory)
    }

    /// The Model pane after a real Test run. The run goes through `ModelSettingsPane.runTest` and the
    /// real client, contract checks included; only the network is a fixture, and the key is a fake one
    /// so the export never touches the keychain.
    private static func exportModel(to directory: URL) async -> Bool {
        let reply = "Reeds and rushes, green and lush; the white dew turns to frost."
        let shots: [(name: String, preset: ServicePreset, model: String, effort: String, answer: Answer)] = [
            ("settings-model-deepseek", .deepSeek, "deepseek-chat", EffortLevel.high.rawValue, .chat(reply)),
            ("settings-model-anthropic", .anthropic, "claude-opus-5-5", "xhigh", .anthropic(reply)),
            ("settings-model-responses", .openAIResponses, "gpt-6", EffortLevel.medium.rawValue, .unauthorized),
        ]
        // The preview app's own domain and suite, so nothing the real app reads is touched.
        let standard = UserDefaults.standard
        defer {
            standard.removeObject(forKey: SettingsStore.serviceChoiceKey)
            for key in [SettingsStore.baseURLKey, SettingsStore.modelKey, SettingsStore.effortKey] {
                PreviewFixtures.defaults.removeObject(forKey: key)
            }
        }
        for shot in shots {
            let baseURL = shot.preset.baseURL ?? "https://preview.invalid"
            standard.set(shot.preset.id, forKey: SettingsStore.serviceChoiceKey)
            PreviewFixtures.defaults.set(baseURL, forKey: SettingsStore.baseURLKey)
            PreviewFixtures.defaults.set(shot.model, forKey: SettingsStore.modelKey)
            PreviewFixtures.defaults.set(shot.effort, forKey: SettingsStore.effortKey)
            let client = ModelClient(
                transport: transport(shot.answer), promptForOperation: { _ in "Preview" }, capture: .off)
            let config = ServiceConfig(
                baseURL: URL(string: baseURL)!, model: shot.model, apiKey: "fixture",
                provider: shot.preset.provider, effort: EffortLevel(rawValue: shot.effort) ?? .off,
                customEffort: EffortLevel(rawValue: shot.effort) == nil ? shot.effort : nil,
                supportsJSONSchema: shot.preset.supportsJSONSchema)
            let check = await ModelSettingsPane.runTest(config: config, target: "en", client: client)
            for dark in [false, true] {
                let view = ModelSettingsPane(
                    promptFocus: .constant(nil), client: client, readKey: { _ in "fixture-key" }, check: check
                )
                .frame(width: size.width, height: size.height)
                .background(Color(nsColor: .windowBackgroundColor))
                .environment(\.controlActiveState, .key)
                .environment(\.colorScheme, dark ? .dark : .light)
                .defaultAppStorage(PreviewFixtures.defaults)
                guard let data = render(AnyView(view), dark: dark) else { return false }
                let name = "\(shot.name)\(dark ? "-dark" : "").png"
                do { try data.write(to: directory.appendingPathComponent(name)) } catch { return false }
            }
        }
        return true
    }

    enum Answer {
        case chat(String), anthropic(String), unauthorized
    }

    /// Model lists answer every GET; the POST gets the shot's reply in its protocol's envelope after a
    /// pause, so the measured time reads like a real round trip.
    private static func transport(_ answer: Answer) -> Transport {
        let sentence = ModelSettingsPane.testSentence
        let text = answerText(answer)
        return { request in
            let url = request.url!
            func reply(_ status: Int, _ body: String) -> (Data, URLResponse) {
                (Data(body.utf8), HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!)
            }
            if request.httpMethod != "POST" {
                return reply(200, #"{"data":[{"id":"deepseek-chat"},{"id":"claude-opus-5-5"},{"id":"gpt-6"}]}"#)
            }
            let result = try JSONSerialization.data(withJSONObject: [
                "source_language": "zh-Hant", "target_language": "en",
                "segments": [["source": sentence, "target": text]],
            ])
            let json = String(decoding: result, as: UTF8.self)
            switch answer {
            case .chat:
                try await Task.sleep(for: .milliseconds(1240))
                let envelope = try JSONSerialization.data(withJSONObject: [
                    "choices": [["message": ["content": json], "finish_reason": "stop"]]
                ])
                return reply(200, String(decoding: envelope, as: UTF8.self))
            case .anthropic:
                try await Task.sleep(for: .milliseconds(1860))
                let envelope = try JSONSerialization.data(withJSONObject: [
                    "content": [["type": "text", "text": json]], "stop_reason": "end_turn",
                ])
                return reply(200, String(decoding: envelope, as: UTF8.self))
            case .unauthorized:
                try await Task.sleep(for: .milliseconds(380))
                return reply(401, #"{"error":{"message":"Incorrect API key provided"}}"#)
            }
        }
    }

    private static func answerText(_ answer: Answer) -> String {
        switch answer {
        case .chat(let text), .anthropic(let text): text
        case .unauthorized: ""
        }
    }



    /// The Debug pane with one success and one contract failure, collapsed and with the failure open.
    private static func exportDebug(to directory: URL) -> Bool {
        let log = DebugLog.shared
        log.clear()
        log.add(
            DebugExchange(
                date: Date(timeIntervalSince1970: 1_760_520_000), title: "Translate · en",
                request: #"{"model": "deepseek-chat", "messages": [ … ]}"#, submitted: PreviewFixtures.source,
                response: #"{"target_language": "en", "segments": [ … ]}"#))
        var failed = DebugExchange(
            date: Date(timeIntervalSince1970: 1_760_520_180), title: "Study Expressions",
            request: #"{"model": "deepseek-chat", "response_format": {"type": "json_object"}}"#,
            submitted: PreviewFixtures.source, response: #"{"items": [{"text": "lush"}]}"#)
        failed.failure = ModelError.format.message
        failed.failureKind = .contract
        log.add(failed)
        for dark in [false, true] {
            for (suffix, open) in [("", Set<UUID>()), ("-open", [failed.id])] {
                let name = "settings-debug\(suffix)\(dark ? "-dark" : "")"
                let view = DebugSettingsPane(expanded: open)
                    .frame(width: size.width, height: size.height)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .environment(\.controlActiveState, .key)
                    .environment(\.colorScheme, dark ? .dark : .light)
                guard let data = render(AnyView(view), dark: dark) else { return false }
                do { try data.write(to: directory.appendingPathComponent("\(name).png")) } catch { return false }
            }
        }
        log.clear()
        return true
    }

    private static func content(_ variant: Variant) -> some View {
        GeneralSettingsPane()
            .frame(width: size.width, height: size.height)
            .background(Color(nsColor: .windowBackgroundColor))
            // The controls should read as in an active window, which is how the pane is seen.
            .environment(\.controlActiveState, .key)
            .environment(\.colorScheme, variant.dark ? .dark : .light)
            .defaultAppStorage(PreviewFixtures.defaults)
    }

    /// `NSHostingView` + `cacheDisplay` rather than `ImageRenderer`: the latter draws neither the
    /// grouped `Form`'s rows nor the `Picker`/`Toggle` controls, leaving an empty image.
    private static func png(_ variant: Variant) -> Data? {
        render(AnyView(content(variant)), dark: variant.dark)
    }

    private static func render(_ view: AnyView, dark: Bool) -> Data? {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        // A `List` only lays out its rows inside a window; this one is never ordered on screen.
        let window = NSWindow(
            contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        host.layoutSubtreeIfNeeded()
        // A 2x rep keeps the export as crisp as the Retina window it stands in for.
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return nil }
        rep.size = size
        host.cacheDisplay(in: host.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }
}

final class PreviewPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@main struct PreviewApp {
    /// Keeps the real panel controller alive for `--panel`.
    @MainActor static var panel: PanelController?

    /// OWLET_PREVIEW_CARD_CHECK=1: drives the card's Add to Notebook through the real presenter and
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
                    selection: NSRange(location: 0, length: 2), in: PreviewFixtures.source, origin: origin)
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
        if let output = ProcessInfo.processInfo.environment["OWLET_PREVIEW_SETTINGS"] {
            // Offscreen only: no window is opened and no permission is requested.
            app.setActivationPolicy(.prohibited)
            Task { @MainActor in
                // One run-loop turn, so the hosting view and its AppKit controls are laid out.
                try? await Task.sleep(for: .milliseconds(100))
                exit(await SettingsPanePreview.export(to: output) ? 0 : 1)
            }
            app.run()
            return
        }
        if let output = ProcessInfo.processInfo.environment["OWLET_PREVIEW_APP_SHOTS"] {
            AppShots.run(app, output: output)
            return
        }
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
                        let frame = PreviewState.shared.panelFrame
                        try JSONSerialization.data(withJSONObject: [
                            "x": frame.minX, "y": frame.minY, "width": frame.width, "height": frame.height,
                            "window": host.bounds.width,
                        ]).write(to: directory.appendingPathComponent("\(name).json"))
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

    /// Runs the production path, PanelController and FloatingPanel, from Translating… to the result, and
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
    @State private var state = PreviewState.shared
    let history = HistoryStore(container: PreviewFixtures.store.container)

    var body: some View {
        NavigationSplitView {
            List(selection: Binding<Int?>(get: { state.mainPage }, set: { state.mainPage = $0 ?? state.mainPage })) {
                Label(L10n.shared.string("Translate & Polish"), systemImage: "translate").tag(0)
                Section(L10n.shared.string("My Collection")) {
                    Label(L10n.shared.string("Notebook"), systemImage: "books.vertical").tag(1)
                    Label(L10n.shared.string("History"), systemImage: "clock").tag(2)
                }
            }
        } detail: {
            switch state.mainPage {
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
            // A few languages, so the notebook's language filter and rows read as they do in use.
            for (expression, language, context, meaning) in [
                ("木漏れ日", "ja", "木漏れ日が揺れる。", "Sunlight filtering through the leaves of trees."),
                ("flâner", "fr", "J'aime flâner le long de la Seine.", "To stroll without hurry, for the pleasure of it."),
                ("seek", "en", "Upstream I go to seek her,", "To look for; to try to find."),
                ("lush", "en", "The reeds are lush and gray-green;", "Growing thickly and richly; full of green."),
                (
                    "long for", "en", "The one I long for is somewhere across the water.",
                    "To miss and want someone very much, often someone far away."
                ),
            ] {
                _ = PreviewFixtures.collection.setCollected(
                    true, draft: VocabularyDraft(expression: expression, language: language, context: context),
                    meaning: meaning)
            }
            let now = Date()
            _ = try? history.record(
                operation: .translate, source: "木漏れ日が揺れる。", result: "Sunlight flickers through the leaves.",
                language: "en", at: now.addingTimeInterval(-86_400))
            _ = try? history.record(
                operation: .polish, source: "The moon is very beautiful tonight, it makes me remember my hometown.",
                result: "The moon is beautiful tonight. It reminds me of home.", language: "en",
                at: now.addingTimeInterval(-3_600))
            _ = try? history.record(
                operation: .translate, source: PreviewFixtures.source,
                result: PreviewFixtures.translations["en"]!.joined(), language: "en")
        }
    }
}

/// `--app-shots`: the notebook and history pages and the Language settings pane, for the website.
/// A solid window sits right behind the main window, so the sidebar's translucency picks up that
/// colour instead of the desktop, and only the main window itself is captured.
@MainActor enum AppShots {
    static func run(_ app: NSApplication, output: String) {
        app.setActivationPolicy(.regular)
        L10n.shared.use(.english)
        SettingsStore.setPinnedTarget("en", in: PreviewFixtures.defaults)
        // The Language pane reads the standard defaults; in this process that is the preview's own
        // domain, never Owlet's, and it is wiped again before exit.
        SettingsStore.setLanguages(["en", "zh-Hans", "ja", "fr", "ko", "es"])
        SettingsStore.setTargetMapping(
            TargetMapping(targets: ["en": "zh-Hans", "ja": "zh-Hans", "fr": "en", "ko": "en", "zh-Hans": "en"], fallback: "en"))
        SettingsStore.setNativeLanguages(["zh-Hans"])

        let frame = NSRect(x: 160, y: 120, width: 1080, height: 690)
        let backdrop = NSWindow(
            contentRect: frame.insetBy(dx: -80, dy: -80), styleMask: .borderless, backing: .buffered, defer: false)
        backdrop.backgroundColor = NSColor(white: 0.95, alpha: 1)
        backdrop.orderFront(nil)
        let window = NSWindow(
            contentRect: frame, styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: MainPreview())
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)

        Task { @MainActor in
            let directory = URL(fileURLWithPath: output, isDirectory: true)
            var ok = true
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                // The fixture translation and the seeded rows land within this pause.
                try await Task.sleep(for: .seconds(2))
                for (page, name) in [(1, "notebook"), (2, "history")] {
                    PreviewState.shared.mainPage = page
                    try await Task.sleep(for: .seconds(1))
                    try capture(window, to: directory.appendingPathComponent("\(name).png"))
                }
                try languagePane().write(to: directory.appendingPathComponent("settings-language.png"))
            } catch {
                print("App shots failed: \(error)")
                ok = false
            }
            if let domain = Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName: domain) }
            exit(ok ? 0 : 1)
        }
        app.run()
    }

    static func capture(_ window: NSWindow, to url: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        // -o leaves the window shadow out; -l captures this window and nothing around it.
        process.arguments = ["-x", "-o", "-l", String(window.windowNumber), url.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "PanelPreview.AppShots", code: Int(process.terminationStatus))
        }
    }

    /// Offscreen, like `--settings`: a grouped `Form` has no glass, so the bitmap matches the window.
    static func languagePane() throws -> Data {
        // Tall enough for every section; the website script trims the empty space below.
        let size = NSSize(width: 620, height: 1300)
        let host = NSHostingView(
            rootView: LanguageSettingsPane()
                .frame(width: size.width, height: size.height)
                .background(Color(nsColor: .windowBackgroundColor))
                .environment(\.controlActiveState, .key))
        host.frame = NSRect(origin: .zero, size: size)
        host.appearance = NSAppearance(named: .aqua)
        host.layoutSubtreeIfNeeded()
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
            case _ = { rep.size = size; host.cacheDisplay(in: host.bounds, to: rep) }(),
            let data = rep.representation(using: .png, properties: [:])
        else { throw NSError(domain: "PanelPreview.AppShots", code: -1) }
        return data
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
