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

@Test func requestConstruction() throws {
    let request = try ModelClient().makeRequest(
        text: "Hello", targetLanguage: "zh-Hans", config: testConfig)
    #expect(request.url?.absoluteString == "https://example.test/v1/chat/completions")
    #expect(request.httpMethod == "POST")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
    let json = try #require(
        JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
    #expect(json["model"] as? String == "m")
    let messages = try #require(json["messages"] as? [[String: String]])
    #expect(messages.last == ["role": "user", "content": "Hello"])
    #expect(messages.first?["role"] == "system")
    #expect(messages.first?["content"]?.contains("Hello") == false)
    #expect(messages.first?["content"]?.hasPrefix(DefaultPrompts.translate) == true)
    let format = try #require(json["response_format"] as? [String: Any])
    #expect(format["type"] as? String == "json_schema")
    let schema = try JSONSerialization.data(withJSONObject: format["json_schema"]!)
    #expect(!String(decoding: schema, as: UTF8.self).contains("minLength"))
}

@Test func deepSeekUsesJSONObjectFormat() throws {
    let config = ServiceConfig(
        baseURL: URL(string: "https://api.deepseek.com")!, model: "deepseek-chat", apiKey: "k",
        provider: .deepSeek)
    let request = try ModelClient().makeRequest(
        text: "Hello", targetLanguage: "zh-Hans", config: config)
    #expect(request.url?.absoluteString == "https://api.deepseek.com/chat/completions")
    let json = try #require(
        JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
    #expect((json["response_format"] as? [String: String]) == ["type": "json_object"])
    let messages = try #require(json["messages"] as? [[String: String]])
    #expect(messages.first?["content"]?.contains("json") == true)
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
    let model = TranslationModel(client: ModelClient(), config: { nil })
    model.input = "Hi"
    model.translate(to: "zh-Hans")
    #expect(model.state == .missingConfig)
}

@MainActor @Test func staleResponseDoesNotOverwriteNewer() async {
    let client = ModelClient(transport: { request in
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        let text = (body["messages"] as! [[String: String]]).last!["content"]!
        if text == "old" { try? await Task.sleep(for: .milliseconds(200)) }
        return try await stub(body: chatBody(TestReplies.reply(for: text)))(request)
    })
    let model = TranslationModel(client: client, config: { testConfig })
    model.input = "old"
    let first = model.translate(to: "zh-Hans")
    model.input = "new"
    let second = model.translate(to: "zh-Hans")
    await second?.value
    await first?.value
    #expect(model.state == .success("T:new"))
}

enum TestReplies {
    static func reply(for text: String) -> String {
        #"{"source_language":"en","target_language":"zh-Hans","segments":[{"source":"\#(text)","target":"T:\#(text)"}]}"#
    }
}
