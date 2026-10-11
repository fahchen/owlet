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

    /// Every claim `parse` would refuse, phrased for the model — the shape a corrective retry needs.
    /// The nullable keys are named explicitly because a `json_object` provider that "forgets" a key
    /// still has a field the app needs written as null. Empty when there is no JSON to correct, so
    /// the caller only spends a round on an answer whose claims can actually be repaired.
    static func diagnose(_ content: String, query: LookupQuery) -> [String] {
        let needed = Array(keys).sorted()
        guard let data = TranslationResult.unfenced(content)?.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [] }
        var reasons: [String] = []
        if let extra = Set(object.keys).subtracting(keys).sorted().first {
            reasons.append("no key other than \(needed) is allowed; found \(extra)")
        }
        if let missing = keys.subtracting(object.keys).sorted().first {
            reasons.append(
                "every key must be present, including the nullable ones written as null; missing \(missing)")
        }
        for field in ["text", "meaning"] {
            if let value = object[field] as? String {
                if TranslationResult.isBlank(value) {
                    reasons.append("\(field) must not be blank")
                }
            } else {
                reasons.append("\(field) must be a non-empty string")
            }
        }
        if let value = object["definition_language"] as? String {
            if TranslationResult.isBlank(value) {
                reasons.append("definition_language must not be blank")
            } else if !LanguageTag.same(value, query.definitionLanguage) {
                // The explanation has to be written in the language that was asked for, whichever
                // language the text itself turns out to be in.
                reasons.append(
                    "definition_language must be \(query.definitionLanguage), the language the "
                        + "explanation was requested in; write meaning and part_of_speech in "
                        + "\(query.definitionLanguage), not in the text's own language")
            }
        } else {
            reasons.append("definition_language must be a string")
        }
        let returnedLanguage: String?
        switch object["language"] {
        case is NSNull:
            returnedLanguage = nil
        case let value as String where !TranslationResult.isBlank(value):
            returnedLanguage = value
        default:
            returnedLanguage = nil
            reasons.append(
                "language must be the BCP 47 tag of the text, or null when it is unknown")
        }
        if let known = query.language {
            guard let returnedLanguage, LanguageTag.same(returnedLanguage, known) else {
                reasons.append(
                    "language must be \(known), the language the query asked about, and may not be null")
                return reasons
            }
        }
        for field in ["lemma", "pronunciation", "part_of_speech"] {
            switch object[field] {
            case is NSNull:
                break
            case let value as String where !TranslationResult.isBlank(value):
                break
            default:
                reasons.append("\(field) must be a non-empty string, or null when it does not apply")
            }
        }
        if let text = object["text"] as? String, !TranslationResult.isBlank(text),
            TranslationResult.normalized(text) != TranslationResult.normalized(query.text)
        {
            reasons.append(
                "text must equal the selected text \(query.text) exactly; found \(text)")
        }
        if !snapshotHoldsText(query) {
            reasons.append("text must start at the offset the query reported in its context")
        }
        return Array(Set(reasons)).sorted()
    }
}
