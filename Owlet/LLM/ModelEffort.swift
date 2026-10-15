import Foundation

/// Maps the app's Reasoning Effort choice to the `reasoning_effort` value one model actually accepts.
///
/// Providers disagree on the vocabulary: DeepSeek folds `medium` into `high`, o-series tops out at
/// `high` and has no non-thinking mode, GPT-6 Astra rejects `none` with HTTP 400, and plain
/// completion models take no effort parameter at all. The table below is maintained from the
/// providers' docs. A level a model does not offer is sent as the nearest lower supported one
/// instead of failing the request; an unknown model keeps the value as-is.
enum ModelEffort {
    /// The value to send for this model, or nil to omit the field (Automatic, a non-reasoning model, or a
    /// model with no usable level).
    static func reasoningEffort(for level: EffortLevel, model: String) -> String? {
        guard level != .automatic else { return nil }
        let table = mapping(for: model)
        guard !table.isEmpty, let start = EffortLevel.ordered.firstIndex(of: level) else { return nil }
        for index in stride(from: start, through: 0, by: -1) {
            if let value = table[EffortLevel.ordered[index]] { return value }
        }
        return nil
    }

    /// The value per UI level for one model. An empty table means the field must be omitted.
    static func mapping(for model: String) -> [EffortLevel: String] {
        let id = model.lowercased()
        guard !id.isEmpty else { return identity }
        if id.hasPrefix("deepseek") { return deepSeek }
        if id.hasPrefix("o1") || id.hasPrefix("o3") || id.hasPrefix("o4") { return openAIOSeries }
        // Astra must be checked before the generic gpt-6 rule.
        if id.hasPrefix("gpt-6-astra") { return openAIAstra }
        if id.hasPrefix("gpt-5") || id.hasPrefix("gpt-6") { return openAIGPT }
        if nonReasoning.contains(where: { id.hasPrefix($0) }) { return [:] }
        return identity
    }

    /// DeepSeek documents none／low／high／max and folds medium→high, so Medium is sent as high.
    private static let deepSeek: [EffortLevel: String] = [
        .off: "none", .low: "low", .medium: "high", .high: "high", .max: "max",
    ]

    /// o-series only reasons; the lowest setting is low and the highest is high.
    private static let openAIOSeries: [EffortLevel: String] = [
        .off: "low", .low: "low", .medium: "medium", .high: "high", .max: "high",
    ]

    /// GPT-6 Astra returns HTTP 400 for none, so Off becomes the lowest reasoning instead.
    private static let openAIAstra: [EffortLevel: String] = [
        .off: "minimal", .low: "low", .medium: "medium", .high: "high", .max: "max",
    ]

    /// GPT-5／GPT-6 reasoning models accept the whole range.
    private static let openAIGPT: [EffortLevel: String] = [
        .off: "none", .low: "low", .medium: "medium", .high: "high", .max: "max",
    ]

    /// Unknown models keep the value as-is, which is what the OpenAI-style field expects.
    private static let identity = openAIGPT

    /// Completion models that have no reasoning parameter, so it must never be sent.
    private static let nonReasoning = ["gpt-4o", "gpt-4.1", "gpt-4-turbo", "gpt-4-", "gpt-4", "gpt-3.5"]
}

extension EffortLevel {
    /// Lowest to highest, without Automatic; the order the mapping walks down when a level is unsupported.
    static let ordered: [EffortLevel] = [.off, .low, .medium, .high, .max]
}
