import Foundation
import Testing

@testable import Owlet

private let polished =
    #"{"source_language":"en","target_language":"en","segments":[{"source":"i has a pen.","target":"I have a pen."}]}"#

@Test func polishRequestUsesPolishPromptWithoutTargetLanguage() throws {
    let request = try clientWithBuiltInPrompt().makeRequest(
        text: "i has a pen.", operation: .polish, targetLanguage: nil, config: testConfig)
    let json = try #require(
        JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
    let messages = try #require(json["messages"] as? [[String: String]])
    let system = try #require(messages.first?["content"])
    #expect(system.hasPrefix(DefaultPrompts.polish))
    #expect(!system.contains("Target language:"))
    #expect(system.contains("只给一个润色版本"))
    #expect(system.contains("保持原文语言和原意"))
    #expect(messages.last == ["role": "user", "content": "i has a pen."])
}

@Test func polishContractRequiresSourceLanguage() throws {
    let result = try TranslationResult.parse(
        polished, submitted: "i has a pen.", targetLanguage: nil)
    #expect(result.text == "I have a pen.")
    let switched = polished.replacingOccurrences(
        of: #""target_language":"en""#, with: #""target_language":"ja""#)
    #expect(throws: ModelError.targetMismatch(requested: "en", returned: "ja")) {
        try TranslationResult.parse(switched, submitted: "i has a pen.", targetLanguage: nil)
    }
}

@Test func polishUnchangedTextIsAllowed() throws {
    let same =
        #"{"source_language":"en","target_language":"en-US","segments":[{"source":"Fine.","target":"Fine."}]}"#
    #expect(try TranslationResult.parse(same, submitted: "Fine.", targetLanguage: nil).text == "Fine.")
}

@Test func polishIgnoresTargetLanguageSelection() async throws {
    let client = ModelClient(transport: stub(body: chatBody(polished)))
    let text = try await client.process(
        "i has a pen.", operation: .polish, to: "zh-Hans", config: testConfig)
    #expect(text == "I have a pen.")
}

@MainActor @Test func modelRunsSelectedOperation() async {
    let model = TranslationModel(
        client: ModelClient(transport: stub(body: chatBody(polished))), config: { testConfig })
    model.input = "i has a pen."
    model.operation = .polish
    await model.translate(to: "zh-Hans")?.value
    #expect(model.state == .success("I have a pen."))
}
