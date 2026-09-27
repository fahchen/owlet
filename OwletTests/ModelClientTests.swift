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

func chatBody(_ content: String) -> String {
    let data = try! JSONSerialization.data(withJSONObject: [
        "choices": [["message": ["content": content], "finish_reason": "stop"]]
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
    #expect(model.state == .success(TestReplies.reply(for: "new")))
}

enum TestReplies {
    static func reply(for text: String) -> String { "T:\(text)" }
}
