import Foundation
import Testing

@testable import Owlet

/// The three further HTTP protocols (BDR-0016): each is asserted on its own wire shape, since a
/// field in the wrong place is a 400 no contract check would ever see.
@Suite struct ProtocolBackendTests {
    let schema = try! JSONSerialization.data(withJSONObject: ["type": "object"])

    func request(format: ModelResponseFormat? = nil, effort: EffortLevel = .automatic, model: String = "m")
        -> ModelRequest
    {
        ModelRequest(
            model: model, system: "sys", turns: [.user("u"), .assistant("a"), .user("again")],
            format: format ?? .jsonSchema(name: "translation", schema: schema), effort: effort)
    }

    func object(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func posted(_ backend: (@escaping Transport) -> any ModelBackend, reply: String, config: ServiceConfig)
        async throws -> URLRequest
    {
        let seen = Captured()
        _ = try await backend({ urlRequest in
            seen.request = urlRequest
            return try await stub(body: reply)(urlRequest)
        }).complete(request(), config: config)
        return try #require(seen.request)
    }

    // MARK: Anthropic

    @Test func anthropicPostsMessagesWithItsOwnHeaders() async throws {
        let config = ServiceConfig(
            baseURL: URL(string: "https://api.anthropic.com/v1")!, model: "m", apiKey: "sk-ant",
            provider: .anthropic)
        let wire = try await posted(
            { AnthropicBackend(transport: $0) },
            reply: #"{"content":[{"type":"text","text":"{}"}],"stop_reason":"end_turn"}"#,
            config: config)
        #expect(wire.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(wire.value(forHTTPHeaderField: "x-api-key") == "sk-ant")
        #expect(wire.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        #expect(wire.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func anthropicBodyCarriesSystemSchemaAndEffort() throws {
        let body = try object(AnthropicBackend.body(for: request(effort: .off)))
        #expect(body["system"] as? String == "sys")
        #expect(body["max_tokens"] as? Int == AnthropicBackend.maxTokens)
        let messages = try #require(body["messages"] as? [[String: String]])
        #expect(messages.map { $0["role"] } == ["user", "assistant", "user"])
        let output = try #require(body["output_config"] as? [String: Any])
        #expect((output["format"] as? [String: Any])?["type"] as? String == "json_schema")
        // Thinking cannot be switched off, so Off asks for the least.
        #expect(output["effort"] as? String == "low")

        let plain = try object(AnthropicBackend.body(for: request(format: .jsonObject)))
        #expect(plain["output_config"] == nil)
    }

    @Test func anthropicReadsTextAndMapsStopReasons() throws {
        let text =
            #"{"content":[{"type":"thinking","thinking":""},{"type":"text","text":"ok"}],"stop_reason":"end_turn"}"#
        #expect(try AnthropicBackend.content(from: Data(text.utf8)) == "ok")
        #expect(throws: ModelError.truncated) {
            try AnthropicBackend.content(from: Data(#"{"content":[],"stop_reason":"max_tokens"}"#.utf8))
        }
        #expect(throws: ModelError.refused) {
            try AnthropicBackend.content(from: Data(#"{"content":[],"stop_reason":"refusal"}"#.utf8))
        }
        #expect(throws: ModelError.emptyResponse) {
            try AnthropicBackend.content(from: Data(#"{"content":[],"stop_reason":"end_turn"}"#.utf8))
        }
    }

    // MARK: OpenAI Responses

    @Test func responsesPostsToResponsesWithBearer() async throws {
        let config = ServiceConfig(
            baseURL: URL(string: "https://api.openai.com/v1")!, model: "m", apiKey: "sk",
            provider: .openAIResponses)
        let wire = try await posted(
            { OpenAIResponsesBackend(transport: $0) },
            reply: #"{"output":[{"type":"message","content":[{"type":"output_text","text":"{}"}]}]}"#,
            config: config)
        #expect(wire.url?.absoluteString == "https://api.openai.com/v1/responses")
        #expect(wire.value(forHTTPHeaderField: "Authorization") == "Bearer sk")
    }

    @Test func responsesBodyUsesTextFormatAndReasoning() throws {
        let body = try object(OpenAIResponsesBackend.body(for: request(effort: .high, model: "gpt-6")))
        #expect(body["instructions"] as? String == "sys")
        #expect(body["store"] as? Bool == false)
        let format = try #require((body["text"] as? [String: Any])?["format"] as? [String: Any])
        #expect(format["type"] as? String == "json_schema")
        #expect(format["name"] as? String == "translation")
        #expect((body["reasoning"] as? [String: Any])?["effort"] as? String == "high")

        let plain = try object(OpenAIResponsesBackend.body(for: request(format: .jsonObject)))
        let plainFormat = (plain["text"] as? [String: Any])?["format"] as? [String: Any]
        #expect(plainFormat?["type"] as? String == "json_object")
        #expect(plain["reasoning"] == nil)
    }

    @Test func responsesReadsMessageItemsAndMapsIncomplete() throws {
        let ok = #"{"output":[{"type":"reasoning"},{"type":"message","content":[{"type":"output_text","text":"ok"}]}]}"#
        #expect(try OpenAIResponsesBackend.content(from: Data(ok.utf8)) == "ok")
        #expect(throws: ModelError.truncated) {
            try OpenAIResponsesBackend.content(
                from: Data(#"{"output":[],"incomplete_details":{"reason":"max_output_tokens"}}"#.utf8))
        }
        #expect(throws: ModelError.refused) {
            try OpenAIResponsesBackend.content(
                from: Data(#"{"output":[{"type":"message","content":[{"type":"refusal","refusal":"no"}]}]}"#.utf8))
        }
    }

    // MARK: Gemini

    @Test func geminiPostsGenerateContentWithItsKeyHeader() async throws {
        let config = ServiceConfig(
            baseURL: URL(string: "https://generativelanguage.googleapis.com/v1beta")!,
            model: "gemini-3-flash", apiKey: "g", provider: .gemini)
        let seen = Captured()
        _ = try await GeminiBackend(transport: { urlRequest in
            seen.request = urlRequest
            return try await stub(
                body: #"{"candidates":[{"content":{"parts":[{"text":"{}"}]},"finishReason":"STOP"}]}"#)(
                    urlRequest)
        }).complete(request(model: "gemini-3-flash"), config: config)
        let wire = try #require(seen.request)
        #expect(
            wire.url?.absoluteString
                == "https://generativelanguage.googleapis.com/v1beta/models/gemini-3-flash:generateContent")
        #expect(wire.value(forHTTPHeaderField: "x-goog-api-key") == "g")
    }

    @Test func geminiBodyUsesModelRoleAndJSONSchema() throws {
        let body = try object(GeminiBackend.body(for: request(effort: .off, model: "gemini-3-flash")))
        let contents = try #require(body["contents"] as? [[String: Any]])
        #expect(contents.map { $0["role"] as? String } == ["user", "model", "user"])
        let generation = try #require(body["generationConfig"] as? [String: Any])
        #expect(generation["responseMimeType"] as? String == "application/json")
        #expect(generation["responseJsonSchema"] != nil)
        #expect((generation["thinkingConfig"] as? [String: Any])?["thinkingLevel"] as? String == "MINIMAL")

        let plain = try object(GeminiBackend.body(for: request(format: .jsonObject, model: "gemini-2.5-pro")))
        let plainGeneration = try #require(plain["generationConfig"] as? [String: Any])
        #expect(plainGeneration["responseJsonSchema"] == nil)
        // thinkingLevel is an error before Gemini 3, so an older model gets none.
        #expect(plainGeneration["thinkingConfig"] == nil)
    }

    @Test func geminiThinkingLevelsFollowEachFamily() {
        #expect(GeminiBackend.thinkingLevel(for: .automatic, model: "gemini-3-flash") == nil)
        #expect(GeminiBackend.thinkingLevel(for: .medium, model: "gemini-3-pro-preview") == "LOW")
        #expect(GeminiBackend.thinkingLevel(for: .max, model: "gemini-3.1-pro-preview") == "HIGH")
        #expect(GeminiBackend.thinkingLevel(for: .off, model: "gemini-3.1-pro-preview") == "LOW")
        // Every pro model lacks MEDIUM, not just the ones named "gemini-3-pro".
        #expect(GeminiBackend.thinkingLevel(for: .medium, model: "gemini-3.1-pro-preview") == "LOW")
        #expect(GeminiBackend.thinkingLevel(for: .high, model: "gemini-2.5-flash") == nil)
    }

    @Test func geminiSkipsThoughtsAndMapsFinishReasons() throws {
        let ok =
            #"{"candidates":[{"content":{"parts":[{"text":"hmm","thought":true},{"text":"ok"}]},"finishReason":"STOP"}]}"#
        #expect(try GeminiBackend.content(from: Data(ok.utf8)) == "ok")
        #expect(throws: ModelError.truncated) {
            try GeminiBackend.content(from: Data(#"{"candidates":[{"finishReason":"MAX_TOKENS"}]}"#.utf8))
        }
        #expect(throws: ModelError.refused) {
            try GeminiBackend.content(from: Data(#"{"candidates":[{"finishReason":"SAFETY"}]}"#.utf8))
        }
        #expect(throws: ModelError.refused) {
            try GeminiBackend.content(from: Data(#"{"promptFeedback":{"blockReason":"OTHER"}}"#.utf8))
        }
    }

    /// A typed effort replaces the mapping in every protocol's own field.
    @Test func aCustomEffortIsSentVerbatimEverywhere() throws {
        var typed = request(effort: .off, model: "gemini-2.5-pro")
        typed.customEffort = "xhigh"
        let anthropic = try object(AnthropicBackend.body(for: typed))
        #expect((anthropic["output_config"] as? [String: Any])?["effort"] as? String == "xhigh")
        let responses = try object(OpenAIResponsesBackend.body(for: typed))
        #expect((responses["reasoning"] as? [String: Any])?["effort"] as? String == "xhigh")
        let gemini = try object(GeminiBackend.body(for: typed))
        let thinking = (gemini["generationConfig"] as? [String: Any])?["thinkingConfig"] as? [String: Any]
        #expect(thinking?["thinkingLevel"] as? String == "xhigh")
        let chat = try object(OpenAICompatibleBackend.body(for: typed, config: testConfig))
        #expect(chat["reasoning_effort"] as? String == "xhigh")
    }

    /// Each protocol lists models at its own path with its own key header, and Gemini's names lose
    /// their `models/` prefix and its non-chat models.
    @Test func modelListsFollowEachProtocol() async throws {
        let base = URL(string: "https://example.test/v1")!
        let seen = Captured()
        let anthropic = try await ModelClient(transport: { request in
            seen.request = request
            return try await stub(body: #"{"data":[{"id":"claude-opus-5-5"}]}"#)(request)
        }).listModels(baseURL: base, apiKey: "k", provider: .anthropic)
        #expect(anthropic == ["claude-opus-5-5"])
        #expect(seen.request?.value(forHTTPHeaderField: "x-api-key") == "k")

        let gemini = try await ModelClient(transport: { request in
            seen.request = request
            return try await stub(
                body:
                    #"{"models":[{"name":"models/gemini-3-flash","supportedGenerationMethods":["generateContent"]},{"name":"models/embed","supportedGenerationMethods":["embedContent"]}]}"#
            )(request)
        }).listModels(baseURL: base, apiKey: "g", provider: .gemini)
        #expect(gemini == ["gemini-3-flash"])
        #expect(seen.request?.value(forHTTPHeaderField: "x-goog-api-key") == "g")
    }

    /// Every provider resolves to the backend that speaks its protocol.
    @Test func eachProviderGetsItsOwnBackend() {
        let backend = { (provider: Provider) in
            provider.backend(transport: stub(body: ""), agent: LocalAgent())
        }
        #expect(backend(.openAICompatible) is OpenAICompatibleBackend)
        #expect(backend(.openAIResponses) is OpenAIResponsesBackend)
        #expect(backend(.anthropic) is AnthropicBackend)
        #expect(backend(.gemini) is GeminiBackend)
        #expect(backend(.claudeCode) is LocalAgentBackend)
    }
}
