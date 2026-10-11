import AppKit
import ApplicationServices
import Foundation
import NaturalLanguage
import SwiftData
import Synchronization
import Testing

@testable import Owlet

let english = LookupOrigin(language: "en", definitionLanguage: "zh-Hans")
/// Read-only settings for lookup stores, so no test reads the developer's own reading notation.
nonisolated(unsafe) let lookupDefaults = UserDefaults(suiteName: "LookupTests.readOnly")!

func query(_ text: String, in full: String, origin: LookupOrigin = english) throws -> LookupQuery {
    let range = (full as NSString).range(of: text)
    return try LookupQuery.make(selection: range, in: full, origin: origin).get()
}

/// A valid `$defs.lookup` answer for `query`, as the model would send it.
func lookupReply(
    _ query: LookupQuery, meaning: String = "河岸", overrides: [String: Any] = [:]
) -> String {
    var answer: [String: Any] = [
        "text": query.text, "language": query.language ?? NSNull(),
        "definition_language": query.definitionLanguage, "meaning": meaning,
        "lemma": NSNull(), "pronunciation": NSNull(), "part_of_speech": NSNull(),
    ]
    answer.merge(overrides) { $1 }
    return String(decoding: try! JSONSerialization.data(withJSONObject: answer), as: UTF8.self)
}

@Suite struct LookupQueryTests {
    let river = "We sat on the bank of the river. Then we left."

    @Test func snapshotsTheSentenceAroundTheSelection() throws {
        let query = try query("bank", in: river)
        #expect(query.context == "We sat on the bank of the river.")
        #expect(query.offset == 14)
        #expect(query.language == "en")
        #expect(query.pronunciation == nil)
    }

    @Test func aSelectionAcrossSentencesKeepsBothWhole() throws {
        let query = try query("river. Then", in: river)
        #expect(query.text == "river. Then")
        #expect(query.context == river)
    }

    @Test func surroundingWhitespaceIsDroppedButNotTheWords() throws {
        let full = "a  follow up  b"
        let range = NSRange(location: 1, length: 12)
        let query = try LookupQuery.make(selection: range, in: full, origin: english).get()
        #expect(query.text == "follow up")
    }

    @Test func punctuationOrSpaceAloneIsNotALookup() {
        let full = "Hi, there."
        for range in [NSRange(location: 2, length: 2), NSRange(location: 0, length: 0)] {
            #expect(LookupQuery.make(selection: range, in: full, origin: english) == .failure(.empty))
        }
    }

    @Test func anOverlongSelectionIsRefusedNotCut() {
        let full = String(repeating: "word ", count: 100)
        let range = NSRange(location: 0, length: (full as NSString).length)
        #expect(LookupQuery.make(selection: range, in: full, origin: english) == .failure(.tooLong))
    }

    @Test func aLongSentenceIsWindowedAroundTheWholeSelection() throws {
        let filler = String(repeating: "lorem ", count: 300)
        let full = filler + "target words here " + filler + "."
        let query = try query("target words here", in: full)
        let context = try #require(query.context)
        #expect(context.count <= LookupQuery.maxContext)
        #expect(context.contains("target words here"))
    }

    @MainActor @Test func readingNotationDefaultsPerLanguageAndFollowsTheSetting() {
        // A suite of this test's own, so no other test reads the notation it saves.
        let defaults = UserDefaults(suiteName: "LookupQueryTests.\(UUID().uuidString)")!
        #expect(SettingsStore.pronunciationSystem(for: "ja", in: defaults) == .kana)
        #expect(SettingsStore.pronunciationSystem(for: "zh-CN", in: defaults) == .pinyin)
        #expect(SettingsStore.pronunciationSystem(for: "fr", in: defaults) == .ipa)
        #expect(PronunciationSystem.options(for: "en") == [.ipa])
        SettingsStore.setPronunciationSystem(.romaji, for: "ja", in: defaults)
        #expect(SettingsStore.pronunciationSystem(for: "ja-JP", in: defaults) == .romaji)

        let store = LookupStore(config: { testConfig }, defaults: defaults)
        let japanese = LookupQuery.withoutContext(
            "推敲", origin: LookupOrigin(language: "ja", definitionLanguage: "zh-Hans"))
        let romaji = store.stamped(japanese)
        #expect(romaji.pronunciation == "romaji")
        SettingsStore.setPronunciationSystem(.kana, for: "ja", in: defaults)
        #expect(store.stamped(japanese) != romaji)
        #expect(
            store.stamped(
                LookupQuery.withoutContext("x", origin: LookupOrigin(language: nil, definitionLanguage: "en"))
            ).pronunciation == nil)
    }

    @Test func definitionLanguageFollowsTheSourceRule() {
        let mapping = TargetMapping(targets: ["en": "zh-Hans", "zh-Hans": "en"], fallback: "zh-Hans")
        let translated = LookupOrigin.result(
            of: .translate, languages: ("zh-Hans", "en"), mapping: mapping)
        #expect(translated == LookupOrigin(language: "en", definitionLanguage: "en"))
        let polished = LookupOrigin.result(of: .polish, languages: ("en", "en"), mapping: mapping)
        #expect(polished == LookupOrigin(language: "en", definitionLanguage: "zh-Hans"))
        let japanese = LookupOrigin.result(of: .polish, languages: ("ja", "ja"), mapping: mapping)
        #expect(japanese.definitionLanguage == "zh-Hans")
    }
}

@Suite struct LookupContractTests {
    let bank = try! query("bank", in: "We sat on the bank of the river.")

    @Test func acceptsAValidAnswer() throws {
        let content = lookupReply(bank, overrides: ["lemma": "bank", "pronunciation": "bæŋk"])
        let result = try LookupResult.parse("```json\n\(content)\n```", query: bank)
        #expect(result.meaning == "河岸")
        #expect(result.pronunciation == "bæŋk")
    }

    @Test(
        arguments: [
            ["extra": "x"], ["meaning": " "], ["lemma": ""], ["language": NSNull()], ["language": "fr"],
            ["meaning": 1],
        ] as [[String: any Sendable]])
    func rejectsTheWrongShape(_ override: [String: any Sendable]) {
        #expect(throws: ModelError.format) {
            try LookupResult.parse(lookupReply(bank, overrides: override), query: bank)
        }
    }

    @Test func rejectsAnswersForOtherText() {
        #expect(throws: ModelError.sourceMismatch) {
            try LookupResult.parse(lookupReply(bank, overrides: ["text": "river"]), query: bank)
        }
    }

    @Test func rejectsAnotherDefinitionLanguage() {
        #expect(throws: ModelError.targetMismatch(requested: "zh-Hans", returned: "en")) {
            try LookupResult.parse(
                lookupReply(bank, overrides: ["definition_language": "en"]), query: bank)
        }
    }

    @Test func anUnknownLanguageMayStayNull() throws {
        let unknown = LookupQuery.withoutContext(
            "bank", origin: LookupOrigin(language: nil, definitionLanguage: "zh-Hans"))
        #expect(try LookupResult.parse(lookupReply(unknown), query: unknown).language == nil)
    }

    @Test func requestKeepsTextAsDataAndUsesTheProviderFormat() throws {
        let request = try ModelClient().makeLookupRequest(bank, config: testConfig)
        let body = String(decoding: request.httpBody!, as: UTF8.self)
        #expect(!body.contains("sk-test"))
        let json = try #require(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
        let messages = try #require(json["messages"] as? [[String: String]])
        #expect(messages[0]["content"]?.contains("bank of the river") == false)
        #expect(messages[0]["content"]?.contains("zh-Hans") == true)
        let data = try #require(messages[1]["content"]?.data(using: .utf8))
        let payload = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(payload["context"] as? String == "We sat on the bank of the river.")
        #expect(payload["selection_start"] as? Int == 14)
        let format = try #require(json["response_format"] as? [String: Any])
        #expect(format["type"] as? String == "json_schema")

        var deepSeek = testConfig
        deepSeek.provider = .deepSeek
        let plain = try ModelClient().makeLookupRequest(bank, config: deepSeek)
        let plainJSON = try #require(JSONSerialization.jsonObject(with: plain.httpBody!) as? [String: Any])
        #expect((plainJSON["response_format"] as? [String: String]) == ["type": "json_object"])
    }

    @Test func aFailureIsCapturedForDebuggingWithoutTheKey() async throws {
        let captured = Mutex<[DebugExchange]>([])
        let client = ModelClient(
            transport: stub(body: chatBody("not json")),
            capture: DebugCapture(
                isEnabled: { true }, record: { exchange in captured.withLock { $0.append(exchange) } }))
        await #expect(throws: ModelError.format) { try await client.lookup(bank, config: testConfig) }
        try await Task.sleep(for: .milliseconds(50))
        let exchange = try #require(captured.withLock { $0.first })
        #expect(exchange.title == "查词 · zh-Hans")
        #expect(exchange.response == "not json")
        #expect(!exchange.request.contains("sk-test"))
    }
}

/// Counts requests and answers each with whatever `reply` says, after a release when gated.
final class LookupTransport: Sendable {
    let calls = Mutex(0)
    let reply: @Sendable (LookupQuery) -> String
    let queries: [LookupQuery]
    let gate = Mutex<[CheckedContinuation<Void, Never>]>([])
    let gated: Bool

    init(
        _ queries: [LookupQuery], gated: Bool = false,
        reply: @escaping @Sendable (LookupQuery) -> String = { lookupReply($0) }
    ) {
        self.queries = queries
        self.gated = gated
        self.reply = reply
    }

    var count: Int { calls.withLock { $0 } }
    func release() { gate.withLock { $0.removeFirst() }.resume() }

    var transport: Transport {
        { [self] request in
            calls.withLock { $0 += 1 }
            if gated { await withCheckedContinuation { continuation in gate.withLock { $0.append(continuation) } } }
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            let data = (body["messages"] as! [[String: String]])[1]["content"]!
            let sent = try JSONSerialization.jsonObject(with: Data(data.utf8)) as! [String: Any]
            let match = queries.first {
                $0.text == sent["text"] as? String && $0.context == sent["context"] as? String
            }!
            return try await stub(body: chatBody(reply(match)))(request)
        }
    }
}

@MainActor @Suite struct LookupStoreTests {
    let river = try! query("bank", in: "We sat on the bank of the river.")
    let money = try! query("bank", in: "She works at the bank downtown.")

    func store(_ transport: LookupTransport, config: ServiceConfig? = testConfig) -> LookupStore {
        LookupStore(
            client: ModelClient(transport: transport.transport, capture: .off), config: { config },
            defaults: lookupDefaults)
    }

    func settle(_ store: LookupStore) async {
        for _ in 0..<200 where store.entries.values.contains(.loading) {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test func theSameQueryJoinsTheRequestInFlightAndIsReused() async {
        let transport = LookupTransport([river], gated: true)
        let store = store(transport)
        let query = store.stamped(river)
        store.open(query)
        store.open(query)
        try? await Task.sleep(for: .milliseconds(20))
        #expect(transport.count == 1)
        transport.release()
        await settle(store)
        store.open(query)
        #expect(transport.count == 1)
        guard case .success(let result) = store.entries[query] else { Issue.record("no result"); return }
        #expect(result.meaning == "河岸")
    }

    @Test func anotherSentenceOffersTheOldAnswerUntilRechecked() async {
        let transport = LookupTransport([river, money]) {
            $0 == river ? lookupReply($0) : lookupReply($0, meaning: "银行")
        }
        let store = store(transport)
        let first = store.stamped(river)
        store.open(first)
        await settle(store)
        let second = store.stamped(money)
        #expect(store.open(second) == first)
        #expect(transport.count == 1)
        #expect(store.entries[second] == nil)
        store.request(second)
        await settle(store)
        guard case .success(let now) = store.entries[second], case .success(let old) = store.entries[first]
        else { Issue.record("missing"); return }
        #expect(now.meaning == "银行")
        #expect(old.meaning == "河岸")
    }

    @Test func aFailedRecheckLeavesTheOldAnswerAndOnlyRetriesOnRequest() async {
        let transport = LookupTransport([river, money]) { $0 == river ? lookupReply($0) : "not json" }
        let store = store(transport)
        let first = store.stamped(river)
        store.open(first)
        await settle(store)
        let second = store.stamped(money)
        store.open(second)
        store.request(second)
        await settle(store)
        #expect(store.entries[second] == .failure(ModelError.format.message))
        guard case .success = store.entries[first] else { Issue.record("old answer lost"); return }
        store.open(second)
        #expect(transport.count == 2)
        store.request(second)
        await settle(store)
        #expect(transport.count == 3)
    }

    @Test(arguments: ["language", "text", "definition", "pronunciation", "service", "noContext"])
    func incompatibleAnswersAreNotOfferedFromAnotherSentence(_ difference: String) async {
        let old = difference == "noContext" ? LookupQuery.withoutContext("bank", origin: english) : river
        let store = store(LookupTransport([old]))
        store.open(store.stamped(old))
        await settle(store)
        var current = store.stamped(money)
        switch difference {
        case "language": current.language = nil
        case "text": current.text = "Bank"
        case "definition": current.definitionLanguage = "en"
        case "pronunciation": current.pronunciation = "kana"
        case "service": current.service = "other"
        default: break
        }
        #expect(store.otherSentence(for: current) == nil)
    }

    @Test func aContextFreeAnswerIsReusedOnlyWithoutContext() async {
        let general = LookupQuery.withoutContext("bank", origin: english)
        let transport = LookupTransport([general])
        let store = store(transport)
        let query = store.stamped(general)
        store.open(query)
        await settle(store)
        store.open(store.stamped(general))
        #expect(transport.count == 1)
        #expect(store.otherSentence(for: store.stamped(money)) == nil)
    }

    @Test func aChangedModelSettingIsANewLookup() async {
        var config = testConfig
        let transport = LookupTransport([river])
        let store = LookupStore(
            client: ModelClient(transport: transport.transport, capture: .off), config: { config },
            defaults: lookupDefaults)
        store.open(store.stamped(river))
        await settle(store)
        config.model = "other"
        store.open(store.stamped(river))
        await settle(store)
        #expect(transport.count == 2)
    }

    @Test func missingServiceFailsWithoutARequest() {
        let transport = LookupTransport([river])
        let store = store(transport, config: nil)
        let query = store.stamped(river)
        store.open(query)
        #expect(store.entries[query] == .failure("模型服务未配置"))
        #expect(transport.count == 0)
    }

    @Test func memoryIsBounded() async {
        let transport = LookupTransport([])
        let store = store(transport, config: nil)
        for index in 0...LookupStore.capacity {
            store.open(LookupQuery.withoutContext("w\(index)", origin: english))
        }
        #expect(store.entries.count == LookupStore.capacity)
        #expect(store.entries[store.stamped(LookupQuery.withoutContext("w0", origin: english))] == nil)
    }
}

@MainActor @Suite struct LookupPresenterTests {
    let a = try! query("bank", in: "We sat on the bank of the river.")
    let b = try! query("river", in: "We sat on the bank of the river.")

    final class Spoken { var said: [String] = []; var stops = 0 }

    func presenter(_ transport: LookupTransport, spoken: Spoken = Spoken()) -> LookupPresenter {
        LookupPresenter(
            store: LookupStore(
                client: ModelClient(transport: transport.transport, capture: .off), config: { testConfig },
                defaults: lookupDefaults),
            speech: LookupSpeech(
                canSpeak: { $0 == "en" }, speak: { text, _ in spoken.said.append(text) },
                stop: { spoken.stops += 1 }))
    }

    @Test func aLateAnswerNeitherReplacesTheNewCardNorReopensAClosedOne() async {
        let transport = LookupTransport([a, b], gated: true)
        let presenter = presenter(transport)
        presenter.lookUp(a, at: nil, in: nil)
        presenter.lookUp(b, at: nil, in: nil)
        try? await Task.sleep(for: .milliseconds(20))
        transport.release()
        try? await Task.sleep(for: .milliseconds(50))
        guard case .card(let shown, _)? = presenter.mode else { Issue.record("no card"); return }
        #expect(shown.text == "river")
        #expect(presenter.close())
        transport.release()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(presenter.mode == nil)
        #expect(!presenter.close())
    }

    @Test func theToolbarQueriesOnlyItsOwnSelection() {
        let transport = LookupTransport([a])
        let presenter = presenter(transport)
        presenter.showToolbar(.failure(.tooLong), at: .zero, in: nil)
        presenter.confirmToolbar()
        #expect(presenter.mode == .toolbar(.failure(.tooLong)))
        #expect(transport.count == 0)
        presenter.showToolbar(.success(a), at: .zero, in: nil)
        #expect(transport.count == 0)
        presenter.confirmToolbar()
        guard case .card(let shown, _)? = presenter.mode else { Issue.record("no card"); return }
        #expect(shown.text == "bank")
    }

    @Test func speechStopsOnSwitchAndClose() {
        let spoken = Spoken()
        let presenter = presenter(LookupTransport([a, b]), spoken: spoken)
        presenter.lookUp(a, at: nil, in: nil)
        presenter.speak("bank", language: "en")
        let before = spoken.stops
        presenter.lookUp(b, at: nil, in: nil)
        #expect(spoken.stops == before + 1)
        presenter.close()
        #expect(spoken.stops == before + 2)
        #expect(spoken.said == ["bank"])
    }
}

/// Esc and the lookup share the panel: the card goes first, and a lookup writes nothing anywhere.
@MainActor @Suite(.serialized) struct PanelLookupTests {
    final class OffScreenPanel: FloatingPanel {
        private(set) var closes = 0
        override func show(anchor: PanelPlacement.Anchor) {}
        override func close() {
            closes += 1
            super.close()
        }
    }

    @Test func escClosesTheCardBeforeThePanelAndNothingIsWritten() async throws {
        let schema = Schema([VocabularyEntry.self, VocabularyContext.self])
        let vocabulary = VocabularyStore(
            container: try ModelContainer(
                for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]))
        let bank = try query("bank", in: "We sat on the bank of the river.")
        let transport = LookupTransport([bank])
        let model = TextProcessingModel(
            client: ModelClient(transport: stub(body: chatBody(TestReplies.reply(for: "Hello")))),
            config: { testConfig })
        let lookups = LookupPresenter(
            store: LookupStore(
                client: ModelClient(transport: transport.transport, capture: .off), config: { testConfig },
                defaults: lookupDefaults),
            speech: LookupSpeech(canSpeak: { _ in true }, speak: { _, _ in }, stop: {}))
        let panel = PanelController(
            model: model, defaults: UserDefaults(suiteName: "PanelLookupTests.\(UUID().uuidString)")!,
            lookups: lookups)
        let window = OffScreenPanel(rootView: PanelRootView(controller: panel))
        panel.makeWindow = { _ in window }
        panel.collection = CollectionAction(
            store: vocabulary, client: ModelClient(transport: transport.transport), config: { testConfig })
        var writes: [String] = []
        panel.write = { _, text in
            writes.append(text)
            return .pasted
        }
        panel.read = {
            $0(.success(Selection(text: "Hello", element: AXUIElementCreateSystemWide(), app: nil, range: nil)))
        }
        panel.processSelection()
        try await Task.sleep(for: .milliseconds(100))

        lookups.lookUp(bank, at: nil, in: nil)
        try await Task.sleep(for: .milliseconds(50))
        panel.run(.cancel)
        #expect(lookups.mode == nil)
        #expect(window.closes == 0)
        panel.run(.cancel)
        #expect(window.closes == 1)

        #expect(writes.isEmpty)
        #expect(try vocabulary.entries().isEmpty)
        #expect(model.input == "Hello")
        #expect(transport.count == 1)
    }
}

/// Single-click hits use the system word tokenizer; whitespace and punctuation hit nothing.
@MainActor @Suite struct LookupWordHitTests {
    func word(at character: String, occurrence: Int = 0, in text: String) -> String? {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var search = text.startIndex..<text.endIndex
        var found = text.range(of: character, range: search)
        for _ in 0..<occurrence {
            search = found!.upperBound..<text.endIndex
            found = text.range(of: character, range: search)
        }
        let index = NSRange(found!, in: text).location
        return LookupTextView.word(at: index, in: text, tokenizer: tokenizer).map {
            (text as NSString).substring(with: $0)
        }
    }

    @Test func englishWordsAndTheGapsBetweenThem() {
        let text = "\"Tui Qiao\" is not just an ancient allusion."
        #expect(word(at: "ncie", in: text) == "ancient")
        #expect(word(at: " ", in: text) == nil)
        #expect(word(at: "\"", in: text) == nil)
        #expect(word(at: ".", in: text) == nil)
    }

    @Test func japaneseUsesTheSystemSegmentation() {
        let text = "「推敲」は古い文学の故事である。"
        #expect(word(at: "翻", in: "正確な翻訳の最高") == "翻訳")
        #expect(word(at: "文", in: text) == "文学")
        #expect(word(at: "「", in: text) == nil)
        #expect(word(at: "。", in: text) == nil)
    }

    @Test func chineseUsesTheSystemSegmentation() {
        let text = "推敲不仅是古老的文学典故，也是精准翻译的最高境界。"
        #expect(word(at: "典", in: text) == "典故")
        #expect(word(at: "，", in: text) == nil)
    }
}
