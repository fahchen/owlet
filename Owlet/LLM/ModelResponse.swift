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
        guard !isBlank(sourceLanguage) else { throw ModelError.format }
        guard sameLanguage(target, targetLanguage ?? sourceLanguage) else {
            throw ModelError.targetMismatch(
                requested: targetLanguage ?? sourceLanguage, returned: target)
        }
        guard normalized(segments.map(\.source).joined()) == normalized(submitted) else {
            throw ModelError.sourceMismatch
        }
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
        LanguageTag.same(lhs, rhs)
    }

    static func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Validated learning response per `spec/llm/contract.md`; the same contract carries the manually
/// requested meaning fill, which is why it lives with the other response contracts.
struct LearningResult: Equatable {
    struct Item: Equatable {
        var text: String
        var language: String
        var kind: String
        var meaning: String
        var context: String
        /// The dictionary form, only when it differs from `text` and is certain (BDR-0009).
        var lemma: String?
    }
    var items: [Item]

    static let keys: Set<String> = ["text", "language", "kind", "meaning", "context", "lemma"]

    /// Response schema sent to the provider; the constraints OpenAI strict mode rejects are
    /// enforced by `parse` instead.
    static var providerSchema: [String: Any] {
        [
            "type": "object",
            "additionalProperties": false,
            "required": ["items"],
            "properties": [
                "items": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "additionalProperties": false,
                        "required": ["text", "language", "kind", "meaning", "context", "lemma"],
                        "properties": [
                            "text": ["type": "string"],
                            "language": ["type": "string"],
                            "kind": ["type": "string", "enum": ["word", "phrase", "sentence"]],
                            "meaning": ["type": "string"],
                            "context": ["type": "string"],
                            "lemma": ["type": ["string", "null"]],
                        ],
                    ],
                ]
            ],
        ]
    }

    /// Validates the whole learning payload: only `items`, non-blank fields, a known kind, each
    /// expression appearing in its own context, and a lemma that either differs from the expression
    /// or is null; an empty list is valid because padding is forbidden.
    static func parse(_ content: String) throws -> [Item] {
        guard let data = TranslationResult.unfenced(content)?.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            Set(object.keys) == ["items"],
            let rawItems = object["items"] as? [Any]
        else { throw ModelError.format }
        return try rawItems.map { raw -> Item in
            guard let dict = raw as? [String: Any], Set(dict.keys) == keys,
                let text = dict["text"] as? String, !TranslationResult.isBlank(text),
                let language = dict["language"] as? String, !TranslationResult.isBlank(language),
                let kind = dict["kind"] as? String,
                ["word", "phrase", "sentence"].contains(kind),
                let meaning = dict["meaning"] as? String, !TranslationResult.isBlank(meaning),
                let context = dict["context"] as? String, !TranslationResult.isBlank(context),
                TranslationResult.normalized(context).localizedStandardContains(
                    TranslationResult.normalized(text))
            else { throw ModelError.format }
            let lemma = try optional(dict["lemma"])
            // Repeating the expression buys nothing; the contract asks for null instead.
            if let lemma, TranslationResult.normalized(lemma) == TranslationResult.normalized(text) {
                throw ModelError.format
            }
            return Item(
                text: text, language: language, kind: kind, meaning: meaning, context: context,
                lemma: lemma)
        }
    }

    /// A nullable field: null, or a non-blank string.
    private static func optional(_ value: Any?) throws -> String? {
        switch value {
        case is NSNull: return nil
        case let string as String where !TranslationResult.isBlank(string): return string
        default: throw ModelError.format
        }
    }

    /// Why `parse` refused, phrased as an instruction for the model — the shape a corrective retry
    /// needs. Empty when the payload parses, and also when it does not even parse as one object: a
    /// reply with no JSON in it has nothing to repair, so the caller only spends a round when this
    /// names at least one rule the model can follow next time.
    ///
    /// The rejection reasons are named rather than counted: a model told only "invalid JSON" repeats
    /// the same mistake, while one told which rule it broke can fix that one.
    static func diagnose(_ content: String) -> [String] {
        guard let data = TranslationResult.unfenced(content)?.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [] }
        guard Set(object.keys) == ["items"] else {
            return ["the object must have exactly the key items; it has \(object.keys.sorted())"]
        }
        guard let rawItems = object["items"] as? [Any] else {
            return ["items must be an array of objects"]
        }
        var reasons: [String] = []
        for raw in rawItems {
            guard let dict = raw as? [String: Any] else {
                reasons.append("every item must be an object")
                continue
            }
            let text = dict["text"] as? String
            if let extra = Set(dict.keys).subtracting(keys).sorted().first {
                reasons.append("no item may have a key other than \(keys.sorted()); found \(extra)")
            }
            if let missing = keys.subtracting(dict.keys).sorted().first {
                reasons.append("every item needs all of \(keys.sorted()); one is missing \(missing)")
            }
            for field in ["text", "language", "meaning", "context"] {
                if let value = dict[field] as? String {
                    if TranslationResult.isBlank(value) { reasons.append("\(field) must not be blank") }
                } else {
                    reasons.append("\(field) must be a non-empty string")
                }
            }
            if let kind = dict["kind"] as? String {
                if !["word", "phrase", "sentence"].contains(kind) {
                    reasons.append("kind must be word, phrase or sentence; found \(kind)")
                }
            } else {
                reasons.append("kind must be word, phrase or sentence")
            }
            guard let text, !TranslationResult.isBlank(text),
                let context = dict["context"] as? String, !TranslationResult.isBlank(context)
            else { continue }
            if !TranslationResult.normalized(context).localizedStandardContains(
                TranslationResult.normalized(text))
            {
                reasons.append(
                    "text \(text) is not in its context, but text must be copied from the context "
                        + "exactly as it is written there")
            }
            switch dict["lemma"] {
            case is NSNull:
                break
            case let lemma as String where !TranslationResult.isBlank(lemma):
                if TranslationResult.normalized(lemma) == TranslationResult.normalized(text) {
                    reasons.append("lemma repeats text \(text), but a lemma equal to text must be null")
                }
            default:
                reasons.append("lemma must be the dictionary form as a string, or null")
            }
        }
        return Array(Set(reasons)).sorted()
    }

    /// Returns the item matching `expression`; an empty list or a mismatch is a format error so the
    /// saved entry stays and the user can retry.
    static func item(_ content: String, expression: String) throws -> Item {
        let wanted = TranslationResult.normalized(expression)
        guard
            let match = try parse(content).first(where: {
                TranslationResult.normalized($0.text) == wanted
            })
        else { throw ModelError.format }
        return match
    }
}
