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

/// The model may give a paragraph break a segment of its own: "\n" is content, not an empty field.
/// Rejecting it turned a structurally correct reply into "a missing field, a wrong type, or empty
/// content" (reported from a real translation of a Japanese mail).
@Test func aBlankLineMayBeItsOwnSegment() throws {
    let json =
        #"{"source_language":"ja","target_language":"en","segments":[{"source":"お世話になっております。\n","target":"Thank you.\n"},{"source":"\n","target":"\n"},{"source":"よろしくお願いいたします。","target":"Best regards."}]}"#
    let result = try parse(json, "お世話になっております。\n\nよろしくお願いいたします。", target: "en")
    #expect(result.segments.count == 3)
    #expect(result.text == "Thank you.\n\nBest regards.")
}

/// Fence characters inside a string value are content, not structure: a reply that carries an
/// ```sh block inside a segment's text (translating a README) is one complete JSON object, and
/// any fence-existence check rejects a reply the contract would accept (reported from a real
/// translation of a README).
@Test func fencesInsideStringValuesAreContent() throws {
    let json = #"""
        {"source_language":"en","target_language":"zh-Hans","segments":[{"source":"```sh\nmise run check\n```\nInstall the tools first.","target":"先安装工具。"}]}
        """#
    #expect(
        try parse(json, "```sh\nmise run check\n```\nInstall the tools first.").text == "先安装工具。")
}

/// Even when the model does wrap the whole reply in one fence, inner fence sequences stay content.
@Test func aWrappedReplyMayHoldFencesInsideItsValues() throws {
    let json = #"""
        ```json
        {"source_language":"en","target_language":"zh-Hans","segments":[{"source":"```sh\nmise run check\n```","target":"先安装工具。"}]}
        ```
        """#
    #expect(try parse(json, "```sh\nmise run check\n```").text == "先安装工具。")
}

/// A reply that is neither wrapped nor a single object still fails, as the contract says.
@Test func proseAroundAFenceIsStillAFormatError() {
    do {
        _ = try parse(
            #"Sure! ```json {"source_language":"en","target_language":"zh-Hans","segments":[{"source":"a","target":"甲"}]} ```"#
        )
        Issue.record("the prose reply was accepted")
    } catch let error as ModelError {
        if case .formatDetail = error { return }
        Issue.record("not a structure failure: \(error)")
    } catch {
        Issue.record("unexpected error type: \(error)")
    }
}

/// Accepting a blank line must not accept a reply that translates nothing at all.
@Test func aReplyWithNoTranslationIsStillRefused() throws {
    let json =
        #"{"source_language":"ja","target_language":"en","segments":[{"source":"お世話になっております。","target":"\n"},{"source":"\n","target":""}]}"#
    #expect(
        throws: ModelError.formatDetail("No segment translated anything.")
    ) {
        try parse(json, "お世話になっております。\n", target: "en")
    }
}

/// A segment with nothing in it is still a missing field.
@Test func anEmptySegmentIsRefused() throws {
    let json =
        #"{"source_language":"en","target_language":"zh-Hans","segments":[{"source":"","target":""}]}"#
    #expect(
        throws: ModelError.formatDetail("Segment 1 had a field with nothing in it.")
    ) { try parse(json, "", target: "zh-Hans") }
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
    #"{"source_language":"en","target_language":"zh-Hans","segments":[]}"#,
    #"{"source_language":"en","target_language":"zh-Hans","segments":[{"source":"Good morning. Let's begin.","target":" "}]}"#,
    #"{"source_language":"en","target_language":"zh-Hans","extra":1,"segments":[{"source":"Good morning. Let's begin.","target":"x"}]}"#,
])
func invalidResponsesAreFormatErrors(content: String) {
    do {
        _ = try parse(content)
        Issue.record("expected the reply to be refused")
    } catch let error as ModelError {
        // The user-facing sentence is the structure one either way; the debug detail names the
        // exact check that refused it, and details that quote the JSON decoder are not asserted.
        if case .format = error { return }
        if case .formatDetail = error { return }
        Issue.record("not a structure failure: \(error)")
    } catch {
        Issue.record("unexpected error type: \(error)")
    }
}

/// A well-formed response that answers in another language is its own failure: the user has to know
/// the model ignored the requested target, not that the JSON was malformed.
@Test func anAnswerInAnotherLanguageIsATargetMismatch() {
    #expect(throws: ModelError.targetMismatch(requested: "zh-Hans", returned: "ja")) {
        try parse(valid.replacingOccurrences(of: "zh-Hans", with: "ja"))
    }
    // zh-TW is Traditional, which the contract keeps apart from the requested Simplified.
    #expect(throws: ModelError.targetMismatch(requested: "zh-Hans", returned: "zh-TW")) {
        try parse(valid.replacingOccurrences(of: "zh-Hans", with: "zh-TW"))
    }
}

/// A response whose sources do not reassemble into the submitted text cannot be paired, so it is
/// reported as its own failure instead of a raw structure problem.
@Test func sourcesThatDoNotReassembleAreASourceMismatch() {
    let partial =
        #"{"source_language":"en","target_language":"zh-Hans","segments":[{"source":"Good morning. ","target":"早上好。"}]}"#
    #expect(throws: ModelError.sourceMismatch) { try parse(partial) }
}

/// A space moved to the next segment, or dropped at the boundary, is what models routinely do with the
/// split; the pairing still holds, so the reply is accepted rather than thrown away.
@Test func boundaryWhitespaceDoesNotFailTheSourceCheck() throws {
    let moved =
        #"{"source_language":"en","target_language":"zh-Hans","segments":[{"source":"Good morning.","target":"早上好。"},{"source":"Let's begin.","target":"我们开始吧。"}]}"#
    #expect(try parse(moved).segments.count == 2)
}

/// A copy carries characters that stand for nothing readable: an inline object's placeholder, a
/// soft hyphen, a zero-width space and a byte-order mark. A reply that drops them still pairs.
@Test(arguments: ["\u{FFFC}", "\u{00AD}", "\u{200B}", "\u{FEFF}"])
func invisibleCopyCharactersDoNotFailTheSourceCheck(_ character: String) throws {
    #expect(try parse(valid, "Good morning. \(character) Let's begin.").segments.count == 2)
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
