import Foundation
import Testing

@testable import Owlet

let testConfig = ServiceConfig(
    baseURL: URL(string: "https://example.test/v1")!, model: "m", apiKey: "sk-test")

func stub(status: Int = 200, body: String) -> Transport {
    { request in
        (
            Data(body.utf8),
            HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        )
    }
}

func chatBody(_ content: String, finishReason: String = "stop", refusal: String? = nil)
    -> String
{
    var message: [String: Any] = ["content": content]
    message["refusal"] = refusal
    let data = try! JSONSerialization.data(withJSONObject: [
        "choices": [["message": message, "finish_reason": finishReason]]
    ])
    return String(decoding: data, as: UTF8.self)
}

/// Fills in the `lemma` every learning item must carry, so a fixture only writes the fields its own
/// test is about (BDR-0009). Malformed fixtures, and items that already state a lemma, pass through.
func learningJSON(_ itemsJSON: String) -> String {
    guard var object = try? JSONSerialization.jsonObject(with: Data(itemsJSON.utf8)) as? [String: Any],
        let items = object["items"] as? [[String: Any]]
    else { return itemsJSON }
    object["items"] = items.map { item -> [String: Any] in
        var item = item
        if item["lemma"] == nil { item["lemma"] = NSNull() }
        return item
    }
    guard let data = try? JSONSerialization.data(withJSONObject: object) else { return itemsJSON }
    return String(decoding: data, as: UTF8.self)
}

/// A learning reply: `learningJSON` wrapped in the provider's chat envelope.
func learningBody(_ itemsJSON: String) -> String {
    chatBody(learningJSON(itemsJSON))
}

/// A client whose behaviour prompt is the built-in one. Request-shape tests assert against
/// `DefaultPrompts`, so they must not inherit a prompt saved in the developer's own settings.
func clientWithBuiltInPrompt() -> ModelClient {
    var client = ModelClient()
    client.promptForOperation = { $0.prompt }
    return client
}

/// The chat body as the HTTP service receives it: where the OpenAI-style effort parameter belongs,
/// and invisible to an assertion on the request value alone.
func wireBody(_ request: ModelRequest, config: ServiceConfig) throws -> [String: Any] {
    let data = try OpenAICompatibleBackend.body(for: request, config: config)
    return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

/// The schema a request asked the provider to enforce, or nil when it asked for `json_object` instead.
func schema(of request: ModelRequest) -> (name: String, data: Data)? {
    guard case .jsonSchema(let name, let data) = request.format else { return nil }
    return (name, data)
}

/// The request the HTTP backend actually posts. The value no longer carries a URL, a method or the
/// credentials, so the wire is read off a capturing transport.
func posted(_ request: ModelRequest, config: ServiceConfig) async throws -> URLRequest {
    let seen = Captured()
    _ = try await OpenAICompatibleBackend(transport: { urlRequest in
        seen.request = urlRequest
        return try await stub(body: chatBody("{}"))(urlRequest)
    }).complete(request, config: config)
    return try #require(seen.request)
}

@Test func requestConstruction() async throws {
    let request = try clientWithBuiltInPrompt().translationRequest(
        text: "Hello", to: "zh-Hans", config: testConfig)
    #expect(request.model == "m")
    #expect(request.turns == [.user("Hello")])
    #expect(!request.system.contains("Hello"))
    #expect(request.system.hasPrefix(DefaultPrompts.translate))
    let schema = try #require(schema(of: request))
    #expect(schema.name == "translation")
    #expect(!String(decoding: schema.data, as: UTF8.self).contains("minLength"))

    let wire = try await posted(request, config: testConfig)
    #expect(wire.url?.absoluteString == "https://example.test/v1/chat/completions")
    #expect(wire.httpMethod == "POST")
    #expect(wire.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
}

@Test func deepSeekUsesJSONObjectFormat() async throws {
    let config = ServiceConfig(
        baseURL: URL(string: "https://api.deepseek.com")!, model: "deepseek-chat", apiKey: "k",
        provider: .deepSeek)
    let request = try ModelClient().translationRequest(
        text: "Hello", to: "zh-Hans", config: config)
    #expect(request.format == .jsonObject)
    #expect(request.system.contains("json"))
    let wire = try await posted(request, config: config)
    #expect(wire.url?.absoluteString == "https://api.deepseek.com/chat/completions")
}

@Test func automaticEffortOmitsTheReasoningParameter() throws {
    var config = testConfig
    config.effort = .automatic
    let request = try ModelClient().translationRequest(
        text: "Hello", to: "zh-Hans", config: config)
    #expect(try wireBody(request, config: config)["reasoning_effort"] == nil)
}

/// 关闭 is the default, so an untouched config must ask for no thinking rather than leaving it to the
/// provider.
@Test func theDefaultConfigAsksForNoThinking() throws {
    let request = try ModelClient().translationRequest(
        text: "Hello", to: "zh-Hans", config: testConfig)
    #expect(try wireBody(request, config: testConfig)["reasoning_effort"] as? String == "none")
}

@Test func aChosenEffortRidesOnTheMainAndLearningRequests() throws {
    let config = ServiceConfig(
        baseURL: URL(string: "https://api.deepseek.com")!, model: "deepseek-flash", apiKey: "k",
        provider: .deepSeek, effort: .low)
    let main = try ModelClient().translationRequest(
        text: "Hello", to: "zh-Hans", config: config)
    #expect(try wireBody(main, config: config)["reasoning_effort"] as? String == "low")
    let learning = try ModelClient().learningRequest(
        text: "Hello", operation: .translate, targetLanguage: "zh-Hans", result: "你好",
        config: config)
    #expect(try wireBody(learning, config: config)["reasoning_effort"] as? String == "low")
}

@Test func effortOffReachesTheProviderAsNone() throws {
    let config = ServiceConfig(
        baseURL: URL(string: "https://api.deepseek.com")!, model: "deepseek-flash", apiKey: "k",
        provider: .deepSeek, effort: .off)
    let request = try ModelClient().translationRequest(
        text: "Hello", to: "zh-Hans", config: config)
    #expect(try wireBody(request, config: config)["reasoning_effort"] as? String == "none")
}

/// The per-model table decides the wire value, so DeepSeek's missing 中 becomes high.
@Test func theModelMappingDecidesTheSentValue() throws {
    let config = ServiceConfig(
        baseURL: URL(string: "https://api.deepseek.com")!, model: "deepseek-flash", apiKey: "k",
        provider: .deepSeek, effort: .medium)
    let request = try ModelClient().translationRequest(
        text: "Hello", to: "zh-Hans", config: config)
    #expect(try wireBody(request, config: config)["reasoning_effort"] as? String == "high")
}

@Test func deepSeekPresetMatchesDocs() {
    #expect(Provider.deepSeek.preset?.baseURL == "https://api.deepseek.com")
    #expect(Provider.openAICompatible.preset == nil)
    #expect(Provider.openAICompatible.keychainAccount == "default")
}

@Test func deepSeekResponseParses() async throws {
    let content = #"{"source_language":"en","target_language":"zh-Hans","segments":[{"source":"Hi","target":"你好"}]}"#
    let client = ModelClient(transport: stub(body: chatBody(content)))
    let config = ServiceConfig(
        baseURL: URL(string: "https://api.deepseek.com")!, model: "deepseek-chat", apiKey: "k",
        provider: .deepSeek)
    #expect(try await client.translate("Hi", to: "zh-Hans", config: config) == "你好")
}

@Test func unauthorizedMapsToAuthError() async {
    let client = ModelClient(transport: stub(status: 401, body: "{}"))
    await #expect(throws: ModelError.unauthorized) {
        try await client.translate("Hi", to: "zh-Hans", config: testConfig)
    }
}

@Test func serverErrorMapsToHTTP() async {
    let client = ModelClient(transport: stub(status: 500, body: "{}"))
    await #expect(throws: ModelError.http(500)) {
        try await client.translate("Hi", to: "zh-Hans", config: testConfig)
    }
}

@Test func networkFailureMapsToNetwork() async {
    let client = ModelClient(transport: { _ in throw URLError(.notConnectedToInternet) })
    await #expect {
        try await client.translate("Hi", to: "zh-Hans", config: testConfig)
    } throws: { error in
        if case .network = error as? ModelError { return true }
        return false
    }
}

@Test func emptyContentMapsToEmptyResponse() async {
    let client = ModelClient(transport: stub(body: chatBody("  ")))
    await #expect(throws: ModelError.emptyResponse) {
        try await client.translate("Hi", to: "zh-Hans", config: testConfig)
    }
}

@MainActor @Test func missingConfigIsReported() {
    let model = TextProcessingModel(client: ModelClient(), config: { nil })
    model.input = "Hi"
    model.process(to: "zh-Hans")
    #expect(model.state == .missingConfig)
}

@MainActor @Test func staleResponseDoesNotOverwriteNewer() async {
    let client = ModelClient(transport: { request in
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        let text = (body["messages"] as! [[String: String]]).last!["content"]!
        if text == "old" { try? await Task.sleep(for: .milliseconds(200)) }
        return try await stub(body: chatBody(TestReplies.reply(for: text)))(request)
    })
    let model = TextProcessingModel(client: client, config: { testConfig })
    model.input = "old"
    let first = model.process(to: "zh-Hans")
    model.input = "new"
    let second = model.process(to: "zh-Hans")
    await second?.value
    await first?.value
    #expect(model.state == .success("T:new"))
}

enum TestReplies {
    static func reply(for text: String) -> String {
        #"{"source_language":"en","target_language":"zh-Hans","segments":[{"source":"\#(text)","target":"T:\#(text)"}]}"#
    }
}

@Test func listModelsRequestsAndDecodes() async throws {
    let seen = Captured()
    let client = ModelClient(transport: { request in
        seen.request = request
        return try await stub(
            body:
                #"{"object":"list","data":[{"id":"deepseek-chat","object":"model","owned_by":"deepseek"},{"id":"deepseek-reasoner","object":"model","owned_by":"deepseek"}]}"#
        )(request)
    })
    let ids = try await client.listModels(
        baseURL: URL(string: "https://api.deepseek.com")!, apiKey: "sk-test")
    #expect(ids == ["deepseek-chat", "deepseek-reasoner"])
    #expect(seen.request?.url?.absoluteString == "https://api.deepseek.com/models")
    #expect(seen.request?.httpMethod == "GET")
    #expect(seen.request?.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
}

@Test func listModelsMapsErrors() async {
    let url = URL(string: "https://api.deepseek.com")!
    await #expect(throws: ModelError.unauthorized) {
        try await ModelClient(transport: stub(status: 401, body: "")).listModels(
            baseURL: url, apiKey: "k")
    }
    await #expect(throws: ModelError.format) {
        try await ModelClient(transport: stub(body: "{}")).listModels(baseURL: url, apiKey: "k")
    }
}

final class Captured: @unchecked Sendable { var request: URLRequest? }

/// BDR-0005: a translation's explanations use its own target; a polish's use the mapped target of the
/// text it polished. A polish keeps the text's language, so reading the request's language verbatim
/// would explain 润色英文 in English instead of the mapped 中文.
@Test func aRecommendationIsExplainedInTheMappedLanguage() throws {
    var client = ModelClient()
    client.targetMapping = { TargetMapping(targets: ["en": "zh-Hans"], fallback: "zh-Hans") }

    // Qualified: `Foundation.Operation` is in scope here too, and the two are ambiguous unqualified.
    func prompt(_ operation: Owlet.Operation, text language: String) throws -> String {
        try client.learningRequest(
            text: "Hello", operation: operation, targetLanguage: language, result: "你好",
            config: testConfig
        ).system
    }

    // Compared through `LanguageCatalog.name` rather than a literal: the test bundle resolves a
    // different language than the app does, so a hard-coded name would be fragile.
    let chinese = LanguageCatalog.name(for: "zh-Hans")
    let english = LanguageCatalog.name(for: "en")
    #expect(chinese != english)

    // 润色英文: the mapped target of the text's language, not the language itself.
    #expect(try prompt(.polish, text: "en").contains(chinese))
    #expect(!(try prompt(.polish, text: "en").contains("meaning is \(english)")))
    // 翻译成英文: its own target, and the mapping must not override it.
    #expect(try prompt(.translate, text: "en").contains("meaning is \(english)"))
}

/// BDR-0012: a phrase the reader already speaks is not worth learning. The prompt asks the model not
/// to offer one, and this filter is what makes the rule hold when it does anyway.
@Test func recommendationsInTheReadersOwnLanguageAreDropped() async throws {
    var client = ModelClient()
    client.capture = .off
    client.nativeLanguages = { ["zh-Hans"] }
    client.transport = { request in
        let items =
            #"{"items":[{"text":"跳ね上がる","language":"ja","kind":"word","meaning":"上涨","context":"原油価格が跳ね上がる。"},{"text":"随后跟进","language":"zh-Hans","kind":"phrase","meaning":"follow up later","context":"随后跟进。"}]}"#
        return try await stub(body: learningBody(items))(request)
    }
    let items = try await client.learning(
        text: "原油価格が跳ね上がる。", operation: .translate, targetLanguage: "zh-Hans",
        result: "油价上涨。", config: testConfig)
    #expect(items.count == 1)
    #expect(items.first?.language == "ja")
}

/// The same request with no native language set keeps everything, so the setting does not change
/// behaviour for anyone who has not chosen one.
@Test func withNoNativeLanguageEveryRecommendationIsKept() async throws {
    var client = ModelClient()
    client.capture = .off
    client.nativeLanguages = { [] }
    client.transport = { request in
        let items =
            #"{"items":[{"text":"跳ね上がる","language":"ja","kind":"word","meaning":"上涨","context":"原油価格が跳ね上がる。"},{"text":"随后跟进","language":"zh-Hans","kind":"phrase","meaning":"follow up later","context":"随后跟进。"}]}"#
        return try await stub(body: learningBody(items))(request)
    }
    let items = try await client.learning(
        text: "原油価格が跳ね上がる。", operation: .translate, targetLanguage: "zh-Hans",
        result: "油价上涨。", config: testConfig)
    #expect(items.count == 2)
}
