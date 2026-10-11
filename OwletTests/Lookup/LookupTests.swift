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
        #expect(exchange.title == "Look Up · zh-Hans")
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
        #expect(store.entries[query] == .failure(String(localized: "The model service is not configured")))
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

/// Each reading area explains in its source's definition language (BDR-0005, word-lookup.feature).
@MainActor @Suite struct LookupAreaTests {
    let mapping = TargetMapping(targets: ["en": "zh-Hans", "zh-Hans": "en"], fallback: "zh-Hans")

    @Test func historyFollowsTheRecordsOperation() {
        let translated = HistoryRecord(
            operation: .translate, source: "我会跟进", result: "I will follow up", language: "en")
        #expect(
            translated.lookupOrigins(mapping: mapping).result == LookupOrigin(language: "en", definitionLanguage: "en"))
        #expect(
            translated.lookupOrigins(mapping: mapping).source == LookupOrigin(language: nil, definitionLanguage: "en"))
        let polished = HistoryRecord(operation: .polish, source: "收敛", result: "收敛", language: "zh-Hans")
        #expect(
            polished.lookupOrigins(mapping: mapping).result
                == LookupOrigin(language: "zh-Hans", definitionLanguage: "en"))
        let japanese = HistoryRecord(operation: .polish, source: "銀行", result: "銀行", language: "ja")
        #expect(japanese.lookupOrigins(mapping: mapping).result.definitionLanguage == "zh-Hans")
    }

    @Test func vocabularyUsesTheEntrysMeaningLanguage() {
        let entry = VocabularyEntry(expression: "bank", language: "en")
        #expect(entry.lookupOrigin == LookupOrigin(language: "en", definitionLanguage: "zh-Hans"))
    }

    @Test func anotherAreaReusesTheSameLookupAndNothingIsSaved() async throws {
        let bank = try query("bank", in: "We sat on the bank of the river.")
        let transport = LookupTransport([bank])
        let store = LookupStore(
            client: ModelClient(transport: transport.transport, capture: .off), config: { testConfig },
            defaults: lookupDefaults)
        let silent = LookupSpeech(canSpeak: { _ in true }, speak: { _, _ in }, stop: {})
        let panel = LookupPresenter(store: store, speech: silent)
        let window = LookupPresenter(store: store, speech: silent)
        let schema = Schema([VocabularyEntry.self, VocabularyContext.self])
        let vocabulary = VocabularyStore(
            container: try ModelContainer(
                for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]))
        let entry = try #require(
            CollectionAction(store: vocabulary, client: ModelClient(transport: transport.transport), config: { nil })
                .collect(
                    VocabularyDraft(expression: "bank", language: "en", context: "We sat on the bank of the river."),
                    meaning: "河岸"))

        panel.lookUp(bank, at: nil, in: nil)
        try await Task.sleep(for: .milliseconds(100))
        window.lookUp(bank, at: nil, in: nil)
        try await Task.sleep(for: .milliseconds(50))
        #expect(transport.count == 1)
        #expect(entry.meaning == "河岸")
        #expect(try vocabulary.entries().count == 1)
    }

    @Test func aLearningExpressionIsLookedUpInsideItsSentence() throws {
        let view = LookupTextView(usingTextLayoutManager: false)
        view.string = "follow up"
        view.origin = english
        view.sentence = "I will follow up tomorrow."
        view.setSelectedRange(NSRange(location: 7, length: 2))
        let query = try #require(try view.selectedQuery?.get())
        #expect(query.text == "up")
        #expect(query.context == "I will follow up tomorrow.")
        #expect(query.offset == 14)
    }

    @Test func aNewSelectionClearsTheOldOneInTheWindow() {
        let presenter = LookupPresenter(
            store: LookupStore(config: { nil }, defaults: lookupDefaults),
            speech: LookupSpeech(canSpeak: { _ in false }, speak: { _, _ in }, stop: {}))
        let first = LookupTextView(usingTextLayoutManager: false)
        let second = LookupTextView(usingTextLayoutManager: false)
        for view in [first, second] {
            view.string = "target contract"
            view.origin = english
            view.presenter = presenter
        }
        first.setSelectedRange(NSRange(location: 7, length: 8))
        second.setSelectedRange(NSRange(location: 0, length: 6))
        #expect(first.selectedRange().length == 0)
        #expect(second.selectedRange().length == 6)
    }

    @Test func leavingTheWindowClosesThatTextsCard() async throws {
        let presenter = LookupPresenter(
            store: LookupStore(config: { nil }, defaults: lookupDefaults),
            speech: LookupSpeech(canSpeak: { _ in false }, speak: { _, _ in }, stop: {}))
        let view = LookupTextView(usingTextLayoutManager: false)
        view.presenter = presenter
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [], backing: .buffered, defer: true)
        window.contentView?.addSubview(view)
        let bank = try query("bank", in: "We sat on the bank of the river.")
        presenter.lookUp(bank, at: .zero, in: view)
        #expect(presenter.isShown)
        view.removeFromSuperview()
        #expect(!presenter.isShown)
    }
}

/// The defects the first review of the lookup branch found (2026-10-11, codex P2).
@MainActor @Suite struct LookupReviewFixTests {
    /// A notebook entry's own form has no source sentence: querying it asks for the general meaning
    /// and says so, instead of passing the expression off as its own context.
    @Test func aStandaloneExpressionIsLookedUpWithoutAContext() throws {
        let view = LookupTextView(usingTextLayoutManager: false)
        view.string = "跳ね上がる"
        view.origin = LookupOrigin(language: "ja", definitionLanguage: "zh-Hans")
        view.hasSentence = false
        view.setSelectedRange(NSRange(location: 0, length: 5))

        let query = try #require(try view.selectedQuery?.get())
        #expect(query.text == "跳ね上がる")
        #expect(query.context == nil)
        #expect(query.offset == nil)
        #expect(query.language == "ja")
    }

    /// Selecting only whitespace in a standalone expression is still nothing to look up.
    @Test func whitespaceAloneInAStandaloneExpressionIsRefused() throws {
        let view = LookupTextView(usingTextLayoutManager: false)
        view.string = "follow  up"
        view.origin = english
        view.hasSentence = false
        view.setSelectedRange(NSRange(location: 6, length: 2))
        let outcome = try #require(view.selectedQuery)
        guard case .failure(.empty) = outcome else {
            Issue.record("expected an empty refusal, got \(outcome)")
            return
        }
    }

    /// 重试 must re-stamp: the request and the key it is cached under have to agree, or switching
    /// models would let one model's answer come back as another's.
    @Test func retryingReStampsTheQuery() throws {
        var config = testConfig
        let store = LookupStore(config: { config }, defaults: lookupDefaults)
        let presenter = LookupPresenter(
            store: store, speech: LookupSpeech(canSpeak: { _ in false }, speak: { _, _ in }, stop: {}))
        let bank = try query("bank", in: "We sat on the bank of the river.")
        presenter.lookUp(bank, at: nil, in: nil)

        config.model = "other"
        presenter.requestCurrent()

        guard case .card(let current, _)? = presenter.mode else {
            Issue.record("expected a card, got \(String(describing: presenter.mode))")
            return
        }
        #expect(current.service != bank.service)
        #expect(current == store.stamped(bank))
        // The request landed under the re-stamped key, not the one the card was opened with.
        #expect(store.entries[current] == .loading)
        #expect(store.entries[bank] == nil)
    }
}

/// The corrective round a lookup gets when the reply breaks the contract (2026-10-11): a
/// `json_object` provider that leaves out a nullable key is asked again, told which key is missing.
@MainActor @Suite struct LookupRetryTests {
    let river = try! query("bank", in: "We sat on the bank of the river.")

    /// A reply missing the three nullable keys: the exact failure the seven-key contract invites from
    /// a provider without a schema.
    nonisolated func replyMissingNullableKeys(_ query: LookupQuery) -> String {
        """
        {"text":"\(query.text)","language":"en","definition_language":"\(query.definitionLanguage)",\
        "meaning":"河岸"}
        """
    }

    @Test func aReplyMissingNullableKeysIsCorrected() async throws {
        let calls = Mutex(0)
        let sawCorrection = Mutex(false)
        let client = ModelClient(
            transport: { request in
                let count = calls.withLock { value -> Int in
                    value += 1
                    return value
                }
                if count == 2 {
                    let body = try JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any]
                    let messages = body?["messages"] as? [[String: String]] ?? []
                    sawCorrection.withLock {
                        $0 =
                            messages.contains { $0["role"] == "assistant" }
                            && messages.contains {
                                $0["role"] == "user"
                                    && ($0["content"]?.contains("lemma") ?? false)
                                    && ($0["content"]?.contains("missing") ?? false)
                            }
                    }
                }
                let content =
                    count == 1
                    ? replyMissingNullableKeys(river) : lookupReply(river, meaning: "河岸")
                return try await stub(body: chatBody(content))(request)
            }, capture: .off)

        let result = try await client.lookup(river, config: testConfig)
        #expect(calls.withLock { $0 } == 2)
        #expect(sawCorrection.withLock { $0 })
        #expect(result.meaning == "河岸")
        #expect(result.lemma == nil)
    }

    /// The failure the user hit on 2026-10-11: the model explained the text in the text's own language
    /// while the reader's target asked for another, and the reply was otherwise perfect. The retry must
    /// name that claim, not only the structural ones.
    @Test func anExplanationInTheWrongLanguageIsCorrected() async throws {
        // The reader practises English, so the explanation is requested in English; the reply is
        // structurally perfect and explains it in the text's own Chinese instead.
        let readerTarget = {
            var target = self.river
            target.definitionLanguage = "en"
            return target
        }()
        let wrongLanguage =
            #"{"text":"bank","language":"en","definition_language":"zh-Hans","meaning":"河岸。","lemma":null,"pronunciation":null,"part_of_speech":null}"#
        let calls = Mutex(0)
        let sawRule = Mutex(false)
        let client = ModelClient(
            transport: { request in
                let count = calls.withLock { value -> Int in
                    value += 1
                    return value
                }
                if count == 2 {
                    let body = try JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any]
                    let messages = body?["messages"] as? [[String: String]] ?? []
                    sawRule.withLock {
                        $0 = messages.contains {
                            $0["role"] == "user"
                                && ($0["content"]?.contains("definition_language must be en") ?? false)
                                && ($0["content"]?.contains("requested in") ?? false)
                        }
                    }
                }
                let content =
                    count == 1 ? wrongLanguage : lookupReply(readerTarget, meaning: "river bank")
                return try await stub(body: chatBody(content))(request)
            }, capture: .off)

        let result = try await client.lookup(readerTarget, config: testConfig)
        #expect(calls.withLock { $0 } == 2)
        #expect(sawRule.withLock { $0 })
        #expect(result.meaning == "river bank")
        #expect(result.definitionLanguage == "en")
    }

    /// A correctable failure that the app cannot describe as a rule still gets no second round.
    @Test func anUndescribableFailureIsNotRetried() async throws {
        let calls = Mutex(0)
        let client = ModelClient(
            transport: { request in
                calls.withLock { $0 += 1 }
                return try await stub(body: chatBody("not json at all"))(request)
            }, capture: .off)
        await #expect(throws: ModelError.format) {
            try await client.lookup(self.river, config: testConfig)
        }
        #expect(calls.withLock { $0 } == 1)
    }

    /// One corrective round only, and a transport failure has no reply to correct.
    @Test func oneCorrectionOnly() async throws {
        let calls = Mutex(0)
        let client = ModelClient(
            transport: { request in
                calls.withLock { $0 += 1 }
                return try await stub(body: chatBody(self.replyMissingNullableKeys(self.river)))(request)
            }, capture: .off)
        await #expect(throws: ModelError.format) {
            try await client.lookup(self.river, config: testConfig)
        }
        #expect(calls.withLock { $0 } == 2)
    }

    @Test func aTransportFailureIsNotRetried() async throws {
        let calls = Mutex(0)
        let client = ModelClient(
            transport: { _ in
                calls.withLock { $0 += 1 }
                throw URLError(.notConnectedToInternet)
            }, capture: .off)
        await #expect(throws: (any Error).self) {
            try await client.lookup(self.river, config: testConfig)
        }
        #expect(calls.withLock { $0 } == 1)
    }
}

/// 加入生词本 on the lookup card: the answer the query already produced becomes a notebook entry,
/// with no second request, and the same card can undo it.
@MainActor @Suite struct LookupCollectionTests {
    let river = try! query("bank", in: "We sat on the bank of the river.")
    /// A look-up whose text language the reading area does not know, so the model's answer supplies it.
    let unknownLanguage = LookupQuery.withoutContext(
        "推敲", origin: LookupOrigin(language: nil, definitionLanguage: "zh-Hans"))

    func notebook() throws -> (CollectionAction, VocabularyStore) {
        let store = try makeVocabularyStore()
        return (CollectionAction(store: store, client: ModelClient(), config: { nil }), store)
    }

    @Test func addingSavesTheAnswerWithoutASecondRequest() throws {
        let (collection, store) = try notebook()
        let answer = try LookupResult.parse(
            lookupReply(river, meaning: "河岸", overrides: ["lemma": "bank"]), query: river)

        #expect(!collection.isCollected(language: "en", expression: "bank"))
        #expect(collection.setCollected(true, query: river, result: answer))
        #expect(collection.isCollected(language: "en", expression: "bank"))

        let entry = try #require(try store.entries().first)
        withExtendedLifetime(store) {
            #expect(entry.expression == "bank")
            #expect(entry.language == "en")
            // The card's own meaning, its language, and the dictionary form it established.
            #expect(entry.meaning == "河岸")
            #expect(entry.definitionLocale == "zh-Hans")
            #expect(entry.lemma == "bank")
            #expect(entry.contexts.map(\.source) == ["We sat on the bank of the river."])
            #expect(entry.contexts.first?.language == "en")
        }
    }

    /// The reading area did not know the language; the model's answer does, and the entry is keyed
    /// under it, so removing finds the same entry again.
    @Test func anUnknownLanguageComesFromTheAnswer() throws {
        let (collection, store) = try notebook()
        let answer = try LookupResult.parse(
            lookupReply(unknownLanguage, meaning: "反复琢磨。", overrides: ["language": "ja"]),
            query: unknownLanguage)

        #expect(collection.setCollected(true, query: unknownLanguage, result: answer))
        let entry = try #require(try store.entries().first)
        withExtendedLifetime(store) {
            #expect(entry.expression == "推敲")
            #expect(entry.language == "ja")
        }
        #expect(collection.isCollected(language: "ja", expression: "推敲"))
        #expect(collection.setCollected(false, query: unknownLanguage, result: answer))
        #expect(try store.entries().isEmpty)
    }

    /// A lookup with no source sentence has no context to store, but still keeps the answer.
    @Test func aContextFreeLookupSavesNoContext() throws {
        let (collection, store) = try notebook()
        let free = LookupQuery.withoutContext("bank", origin: english)
        let answer = try LookupResult.parse(lookupReply(free, meaning: "银行"), query: free)

        #expect(collection.setCollected(true, query: free, result: answer))
        let entry = try #require(try store.entries().first)
        withExtendedLifetime(store) {
            #expect(entry.meaning == "银行")
            #expect(entry.contexts.isEmpty)
        }
    }

    /// Collecting the same word from another sentence appends that sentence and keeps the first
    /// meaning, which is the notebook's existing rule for a repeated expression.
    @Test func aSecondSentenceAppendsAndKeepsTheAnswer() throws {
        let (collection, store) = try notebook()
        let other = try query("bank", in: "She works at the bank downtown.")
        let first = try LookupResult.parse(lookupReply(river, meaning: "河岸"), query: river)
        let second = try LookupResult.parse(lookupReply(other, meaning: "银行"), query: other)

        #expect(collection.setCollected(true, query: river, result: first))
        #expect(collection.setCollected(true, query: other, result: second))

        let entries = try store.entries()
        let entry = try #require(entries.first)
        withExtendedLifetime(store) {
            #expect(entries.count == 1)
            #expect(entry.meaning == "河岸")
            #expect(
                Set(entry.contexts.map(\.source)) == [
                    "We sat on the bank of the river.", "She works at the bank downtown.",
                ])
        }
    }

    /// The card mirrors membership through the notebook's revision, and that is the only thing that
    /// redraws it: the store is SwiftData, which a popover outside its container does not observe.
    /// Both directions must bump it, or the bookmark would only change on the next card.
    @Test func togglingMembershipBumpsTheRevisionTheCardReads() throws {
        let (collection, store) = try notebook()
        let answer = try LookupResult.parse(lookupReply(river), query: river)
        let before = collection.revision

        #expect(collection.setCollected(true, query: river, result: answer))
        let added = collection.revision
        #expect(added != before)

        #expect(collection.setCollected(false, query: river, result: answer))
        #expect(collection.revision != added)
        #expect(try store.entries().isEmpty)

        // Removing something that was never collected changes nothing, so nothing is redrawn.
        let unchanged = collection.revision
        #expect(collection.setCollected(false, query: river, result: answer))
        #expect(collection.revision == unchanged)
    }

    /// A meaning filled in later is a change to the entry the card mirrors, so it redraws too.
    @Test func aFilledMeaningBumpsTheRevision() async throws {
        let store = try makeVocabularyStore()
        let answer = learningBody(
            #"{"items":[{"text":"follow up","language":"en","kind":"phrase","meaning":"跟进。","context":"I will follow up."}]}"#
        )
        let collection = CollectionAction(
            store: store,
            client: ModelClient(transport: stub(body: answer), capture: .off),
            config: { testConfig })
        let entry = try store.collect(
            VocabularyDraft(
                expression: "follow up", language: "en", context: "I will follow up.",
                contextLanguage: "en", definitionLocale: "zh-Hans"))
        #expect(entry.meaning.isEmpty)
        let before = collection.revision

        collection.fillMeaning(for: entry)
        await collection.task?.value

        #expect(entry.meaning == "跟进。")
        #expect(collection.revision != before)
    }

    /// Reopening the card for a word already in the notebook shows it as collected, which is what
    /// makes the button's two states reachable at all.
    @Test func aStoredWordReadsAsCollectedWhenTheCardReopens() throws {
        let (collection, store) = try notebook()
        let answer = try LookupResult.parse(lookupReply(river), query: river)
        #expect(!collection.isCollected(language: "en", expression: "bank"))
        #expect(collection.setCollected(true, query: river, result: answer))
        #expect(collection.isCollected(language: "en", expression: "bank"))
        // A second card for the same query, from the same notebook, still reads as collected.
        let reopened = CollectionAction(store: store, client: ModelClient(), config: { nil })
        #expect(reopened.isCollected(language: "en", expression: "bank"))
        // And the word reached the notebook's own list, which is what the page shows.
        #expect(try store.entries().map(\.expression) == ["bank"])
    }

    /// Removing the entry from the notebook is the same toggle the learning rows use, and a lookup
    /// that was never added is not an error.
    @Test func removingDeletesTheEntry() throws {
        let (collection, store) = try notebook()
        let answer = try LookupResult.parse(lookupReply(river), query: river)
        #expect(collection.setCollected(true, query: river, result: answer))
        #expect(collection.setCollected(false, query: river, result: answer))
        #expect(try store.entries().isEmpty)
        #expect(collection.status == .idle)
    }
}
