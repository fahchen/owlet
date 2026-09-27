import Foundation
import Testing

@testable import Owlet

private let valid =
    #"{"source_language":"en","target_language":"zh-Hans","segments":[{"source":"Good morning. ","target":"早上好。"},{"source":"Let's begin.","target":"我们开始吧。"}]}"#

private func parse(
    _ content: String, _ submitted: String = "Good morning. Let's begin.",
    target: String = "zh-Hans"
) throws -> TranslationResult {
    try TranslationResult.parse(content, submitted: submitted, targetLanguage: target)
}

@Test func multiSentenceConcatenatesTargets() throws {
    let json =
        #"{"source_language":"zh","target_language":"en","segments":[{"source":"早上好。","target":"Good morning. "},{"source":"开始吧。","target":"Let's begin."}]}"#
    #expect(try parse(json, "早上好。开始吧。", target: "en").text == "Good morning. Let's begin.")
}

@Test func whitespaceOnlyDifferencesPass() throws {
    #expect(try parse(valid, "  Good   morning.\nLet's\tbegin.\n").text == "早上好。我们开始吧。")
}

@Test func equivalentLanguageTags() throws {
    #expect(try parse(valid, target: "zh-CN").segments.count == 2)
    let en = valid.replacingOccurrences(of: "zh-Hans", with: "en-US")
    #expect(try parse(en, target: "en").segments.count == 2)
    #expect(TranslationResult.sameLanguage("zh", "zh-SG"))
    #expect(TranslationResult.sameLanguage("zh-TW", "zh-Hant-HK"))
    #expect(!TranslationResult.sameLanguage("zh-TW", "zh-Hans"))
}

@Test func singleFenceAccepted() throws {
    #expect(try parse("```json\n\(valid)\n```").segments.count == 2)
    #expect(try parse("```\n\(valid)\n```").segments.count == 2)
}

@Test(arguments: [
    "Here you go:\n```json\n\(valid)\n```",
    "```json\n\(valid)\n```\nDone.",
    "Result: \(valid)",
    "not json",
    #"{"source_language":"en","segments":[{"source":"Good morning. Let's begin.","target":"x"}]}"#,
    #"{"source_language":"en","target_language":"zh-Hans","segments":"x"}"#,
    #"{"source_language":"en","target_language":"zh-Hans","segments":[{"source":1,"target":"x"}]}"#,
    #"{"source_language":"en","target_language":"zh-Hans","segments":[{"source":"Good morning. ","target":"早上好。"}]}"#,
    #"{"source_language":"en","target_language":"zh-Hans","segments":[]}"#,
    #"{"source_language":"en","target_language":"zh-Hans","segments":[{"source":"Good morning. Let's begin.","target":" "}]}"#,
    #"{"source_language":"en","target_language":"zh-Hans","extra":1,"segments":[{"source":"Good morning. Let's begin.","target":"x"}]}"#,
    valid.replacingOccurrences(of: "zh-Hans", with: "ja"),
    valid.replacingOccurrences(of: "zh-Hans", with: "zh-TW"),
])
func invalidResponsesAreFormatErrors(content: String) {
    #expect(throws: ModelError.format) { try parse(content) }
}

@Test func nfcNormalizationPasses() throws {
    let json =
        #"{"source_language":"fr","target_language":"en","segments":[{"source":"caf\u00e9","target":"cafe"}]}"#
    #expect(try parse(json, "cafe\u{301}", target: "en").text == "cafe")
}

@Test func truncatedAndRefusedAreDistinct() async throws {
    let text = "Good morning. Let's begin."
    let truncated = ModelClient(transport: stub(body: chatBody(valid, finishReason: "length")))
    await #expect(throws: ModelError.truncated) {
        try await truncated.translate(text, to: "zh-Hans", config: testConfig)
    }
    let filtered = ModelClient(
        transport: stub(body: chatBody(valid, finishReason: "content_filter")))
    await #expect(throws: ModelError.refused) {
        try await filtered.translate(text, to: "zh-Hans", config: testConfig)
    }
    let refusal = ModelClient(transport: stub(body: chatBody("", refusal: "No.")))
    await #expect(throws: ModelError.refused) {
        try await refusal.translate(text, to: "zh-Hans", config: testConfig)
    }
    let ok = ModelClient(transport: stub(body: chatBody(valid)))
    #expect(try await ok.translate(text, to: "zh-Hans", config: testConfig) == "早上好。我们开始吧。")
}
