import Testing

@testable import Owlet

/// Each model gets the effort vocabulary it supports; an unsupported level is sent as the nearest
/// lower one instead of failing the request.
struct ModelEffortTests {
    @Test func automaticNeverSendsTheParameter() {
        #expect(ModelEffort.reasoningEffort(for: .automatic, model: "deepseek-flash") == nil)
    }

    /// DeepSeek documents none／low／high／max and folds medium into high.
    @Test func deepSeekFoldsMediumIntoHigh() {
        #expect(ModelEffort.reasoningEffort(for: .off, model: "deepseek-flash") == "none")
        #expect(ModelEffort.reasoningEffort(for: .low, model: "deepseek-flash") == "low")
        #expect(ModelEffort.reasoningEffort(for: .medium, model: "deepseek-flash") == "high")
        #expect(ModelEffort.reasoningEffort(for: .high, model: "deepseek-v4-pro") == "high")
        #expect(ModelEffort.reasoningEffort(for: .max, model: "deepseek-v4-pro") == "max")
    }

    /// o-series has no non-thinking mode and tops out at high, so Off and Highest are clamped.
    @Test func oSeriesClampsToItsRange() {
        #expect(ModelEffort.reasoningEffort(for: .off, model: "o3") == "low")
        #expect(ModelEffort.reasoningEffort(for: .max, model: "o4-mini") == "high")
    }

    /// GPT-6 Astra rejects none with HTTP 400, so Off becomes the lowest reasoning.
    @Test func astraTurnsOffIntoMinimal() {
        #expect(ModelEffort.reasoningEffort(for: .off, model: "gpt-6-astra") == "minimal")
        #expect(ModelEffort.reasoningEffort(for: .high, model: "gpt-6-astra") == "high")
    }

    @Test func nonReasoningModelsOmitTheParameter() {
        #expect(ModelEffort.reasoningEffort(for: .high, model: "gpt-4o") == nil)
        #expect(ModelEffort.reasoningEffort(for: .low, model: "gpt-4.1") == nil)
    }

    @Test func anUnknownModelKeepsTheValue() {
        #expect(ModelEffort.reasoningEffort(for: .medium, model: "my-local-llm") == "medium")
    }

}
