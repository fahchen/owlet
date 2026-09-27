import Foundation

/// Validated translation result per `spec/llm/contract.md`.
struct TranslationResult: Equatable {
    struct Segment: Equatable {
        var source: String
        var target: String
    }
    var sourceLanguage: String
    var targetLanguage: String
    var segments: [Segment]

    var text: String { segments.map(\.target).joined() }

    /// Response schema sent to the provider. Keywords unsupported by OpenAI strict mode
    /// (`minLength`, `minItems`) are omitted here and enforced by `parse` instead.
    static var providerSchema: [String: Any] {
        [
            "type": "object",
            "additionalProperties": false,
            "required": ["source_language", "target_language", "segments"],
            "properties": [
                "source_language": ["type": "string"],
                "target_language": ["type": "string"],
                "segments": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "additionalProperties": false,
                        "required": ["source", "target"],
                        "properties": ["source": ["type": "string"], "target": ["type": "string"]],
                    ],
                ],
            ],
        ]
    }

    /// A nil `targetLanguage` (polish) requires the result to stay in the source language.
    static func parse(_ content: String, submitted: String, targetLanguage: String?) throws
        -> TranslationResult
    {
        guard let data = unfenced(content)?.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            Set(object.keys) == ["source_language", "target_language", "segments"],
            let sourceLanguage = object["source_language"] as? String,
            let target = object["target_language"] as? String,
            let rawSegments = object["segments"] as? [Any], !rawSegments.isEmpty
        else { throw ModelError.format }
        let segments = try rawSegments.map { raw -> Segment in
            guard let dict = raw as? [String: Any], Set(dict.keys) == ["source", "target"],
                let source = dict["source"] as? String, let target = dict["target"] as? String,
                !isBlank(source), !isBlank(target)
            else { throw ModelError.format }
            return Segment(source: source, target: target)
        }
        guard !isBlank(sourceLanguage),
            sameLanguage(target, targetLanguage ?? sourceLanguage),
            normalized(segments.map(\.source).joined()) == normalized(submitted)
        else { throw ModelError.format }
        return TranslationResult(
            sourceLanguage: sourceLanguage, targetLanguage: target, segments: segments)
    }

    /// Strips one Markdown fence wrapping the whole message; nil if fences are malformed.
    static func unfenced(_ content: String) -> String? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return trimmed.contains("```") ? nil : trimmed }
        var lines = trimmed.components(separatedBy: "\n")
        guard lines.count >= 3, let first = lines.first, let last = lines.last,
            ["```", "```json"].contains(first.trimmingCharacters(in: .whitespaces)),
            last.trimmingCharacters(in: .whitespaces) == "```"
        else { return nil }
        lines.removeFirst()
        lines.removeLast()
        let inner = lines.joined(separator: "\n")
        return inner.contains("```") ? nil : inner
    }

    static func normalized(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    static func sameLanguage(_ lhs: String, _ rhs: String) -> Bool {
        languageKey(lhs) == languageKey(rhs)
    }

    private static func languageKey(_ tag: String) -> String {
        let parts = tag.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).map(
            String.init)
        guard let primary = parts.first else { return "" }
        guard primary == "zh" else { return primary }
        let rest = parts.dropFirst()
        if rest.contains("hant") { return "zh-hant" }
        if rest.contains("hans") { return "zh-hans" }
        return rest.contains(where: { ["tw", "hk", "mo"].contains($0) }) ? "zh-hant" : "zh-hans"
    }

    private static func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
