import Foundation

/// Validated `$defs.lookup` response per `spec/llm/contract.md`. It can prove the answer belongs to
/// this query and language; it cannot prove the meaning, lemma or pronunciation are right.
struct LookupResult: Equatable, Sendable {
    var text: String
    var language: String?
    var definitionLanguage: String
    var meaning: String
    var lemma: String?
    var pronunciation: String?
    var partOfSpeech: String?

    static let keys: Set<String> = [
        "text", "language", "definition_language", "meaning", "lemma", "pronunciation",
        "part_of_speech",
    ]

    /// Response schema sent to the provider; `minLength` is enforced by `parse`, as for the others.
    static var providerSchema: [String: Any] {
        let nullable = ["type": ["string", "null"]]
        return [
            "type": "object",
            "additionalProperties": false,
            "required": Array(keys).sorted(),
            "properties": [
                "text": ["type": "string"],
                "language": nullable,
                "definition_language": ["type": "string"],
                "meaning": ["type": "string"],
                "lemma": nullable,
                "pronunciation": nullable,
                "part_of_speech": nullable,
            ],
        ]
    }

    static func parse(_ content: String, query: LookupQuery) throws -> LookupResult {
        guard let data = TranslationResult.unfenced(content)?.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            Set(object.keys) == keys,
            let text = object["text"] as? String, !TranslationResult.isBlank(text),
            let definitionLanguage = object["definition_language"] as? String,
            !TranslationResult.isBlank(definitionLanguage),
            let meaning = object["meaning"] as? String, !TranslationResult.isBlank(meaning)
        else { throw ModelError.format }
        let language = try optional(object["language"])
        let lemma = try optional(object["lemma"])
        let pronunciation = try optional(object["pronunciation"])
        let partOfSpeech = try optional(object["part_of_speech"])
        if query.isSentence, pronunciation != nil || partOfSpeech != nil { throw ModelError.format }
        // A known text language must come back, and the same; the app knew it before asking.
        if let known = query.language {
            guard let language, LanguageTag.same(language, known) else { throw ModelError.format }
        }
        guard TranslationResult.normalized(text) == TranslationResult.normalized(query.text),
            snapshotHoldsText(query)
        else { throw ModelError.sourceMismatch }
        guard LanguageTag.same(definitionLanguage, query.definitionLanguage) else {
            throw ModelError.targetMismatch(
                requested: query.definitionLanguage, returned: definitionLanguage)
        }
        return LookupResult(
            text: text, language: language, definitionLanguage: definitionLanguage,
            meaning: meaning, lemma: lemma, pronunciation: pronunciation,
            partOfSpeech: partOfSpeech)
    }

    /// The range is the app's own snapshot, so a query whose context no longer holds its text at
    /// that offset is refused instead of explained against the wrong words.
    private static func snapshotHoldsText(_ query: LookupQuery) -> Bool {
        guard let context = query.context, let offset = query.offset else { return true }
        guard let start = context.index(context.startIndex, offsetBy: offset, limitedBy: context.endIndex)
        else { return false }
        return context[start...].hasPrefix(query.text)
    }

    /// A nullable field: null, or a non-blank string.
    private static func optional(_ value: Any?) throws -> String? {
        switch value {
        case is NSNull: return nil
        case let string as String where !TranslationResult.isBlank(string): return string
        default: throw ModelError.format
        }
    }
}
