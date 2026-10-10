import Foundation
import NaturalLanguage

/// What a reading area already knows about the text it shows (BDR-0005): the language the text is
/// written in, when known, and the language its explanations must use.
struct LookupOrigin: Equatable, Sendable {
    var language: String?
    var definitionLanguage: String

    /// A finished result is written in its result language. A translation is explained in its own
    /// target; a polish in the mapped target of its source, or the fallback.
    static func result(
        of operation: Operation, languages: (source: String, target: String), mapping: TargetMapping
    ) -> LookupOrigin {
        switch operation {
        case .translate:
            LookupOrigin(language: languages.target, definitionLanguage: languages.target)
        case .polish:
            LookupOrigin(
                language: languages.source,
                definitionLanguage: mapping.target(forSource: LanguageTag.key(languages.source)))
        }
    }
}

/// One explicit lookup: the selected text, the local context it was read in, and every setting that
/// changes the answer. Equal queries are the same lookup, which is what exact reuse keys on.
struct LookupQuery: Hashable, Sendable {
    var text: String
    /// Whole sentences covering the selection; nil when the expression has no source sentence.
    var context: String?
    /// Where `text` starts inside `context`, in characters, so the same word twice in one sentence
    /// stays two lookups.
    var offset: Int?
    var language: String?
    var definitionLanguage: String
    /// BDR-0006's pronunciation system for the known language; nil asks for the per-language default.
    var pronunciation: String?
    /// The model settings that change an answer, without the API key.
    var service: String = ""

    /// Longer selections are refused with a reason instead of being cut short.
    static let maxText = 300
    /// The context always covers the whole selection; only the surrounding text is bounded.
    static let maxContext = 1200

    enum Refusal: Error, Equatable {
        /// Only whitespace or punctuation was selected.
        case empty
        case tooLong

        var message: String {
            switch self {
            case .empty: "所选内容没有可查询的文字"
            case .tooLong: "所选超过 \(LookupQuery.maxText) 字，请缩短后查询"
            }
        }
    }

    /// A sentence ends in terminal punctuation or runs long. The request states which, so the null
    /// rule for sentences is never left to the model's own guess.
    var isSentence: Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let last = trimmed.last, ".!?。！？".contains(last) { return true }
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = trimmed
        return tokenizer.tokens(for: trimmed.startIndex..<trimmed.endIndex).count >= 8
    }

    /// Snapshots the selection inside `full`. Surrounding whitespace is dropped, never the selected
    /// words; a selection over the limit is refused rather than truncated.
    static func make(
        selection: NSRange, in full: String, origin: LookupOrigin
    ) -> Result<LookupQuery, Refusal> {
        let ns = full as NSString
        guard selection.location != NSNotFound, NSMaxRange(selection) <= ns.length,
            var range = Range(selection, in: full)
        else { return .failure(.empty) }
        while range.lowerBound < range.upperBound, full[range.lowerBound].isWhitespace {
            range = full.index(after: range.lowerBound)..<range.upperBound
        }
        while range.lowerBound < range.upperBound, full[full.index(before: range.upperBound)].isWhitespace {
            range = range.lowerBound..<full.index(before: range.upperBound)
        }
        let text = String(full[range])
        guard text.unicodeScalars.contains(where: CharacterSet.alphanumerics.contains) else {
            return .failure(.empty)
        }
        guard text.count <= maxText else { return .failure(.tooLong) }
        let window = contextRange(covering: range, in: full)
        return .success(
            LookupQuery(
                text: text, context: String(full[window]),
                offset: full.distance(from: window.lowerBound, to: range.lowerBound),
                language: origin.language, definitionLanguage: origin.definitionLanguage,
                pronunciation: origin.language.map(pronunciationSystem)))
    }

    /// An expression with no source sentence: the card gives its general meaning and says so.
    static func withoutContext(_ text: String, origin: LookupOrigin) -> LookupQuery {
        LookupQuery(
            text: text, context: nil, offset: nil, language: origin.language,
            definitionLanguage: origin.definitionLanguage,
            pronunciation: origin.language.map(pronunciationSystem))
    }

    /// The sentences the selection touches; when they run past `maxContext`, a window of that size
    /// centred on the selection, which still contains all of it.
    static func contextRange(covering range: Range<String.Index>, in full: String)
        -> Range<String.Index>
    {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = full
        var lower = range.lowerBound
        var upper = range.upperBound
        tokenizer.enumerateTokens(in: full.startIndex..<full.endIndex) { sentence, _ in
            if sentence.overlaps(range) {
                lower = min(lower, sentence.lowerBound)
                upper = max(upper, sentence.upperBound)
            }
            return sentence.lowerBound < range.upperBound
        }
        let selected = full.distance(from: range.lowerBound, to: range.upperBound)
        if full.distance(from: lower, to: upper) > maxContext {
            let spare = (maxContext - selected) / 2
            lower = full.index(range.lowerBound, offsetBy: -spare, limitedBy: lower) ?? lower
            upper = full.index(range.upperBound, offsetBy: spare, limitedBy: upper) ?? upper
        }
        while lower < range.lowerBound, full[lower].isWhitespace { lower = full.index(after: lower) }
        while upper > range.upperBound, full[full.index(before: upper)].isWhitespace {
            upper = full.index(before: upper)
        }
        return lower..<upper
    }

    /// BDR-0006 defaults: kana for Japanese, pinyin for Chinese, IPA for English and the rest.
    /// ponytail: fixed defaults until BDR-0006 adds the per-language setting; read it here then.
    static func pronunciationSystem(for language: String) -> String {
        switch LanguageTag.key(language) {
        case "ja": "kana"
        case "zh-Hans", "zh-Hant": "pinyin"
        default: "IPA"
        }
    }

    /// Model, endpoint, provider and effort change an answer; the key never enters the cache key.
    static func service(_ config: ServiceConfig) -> String {
        [config.provider.rawValue, config.baseURL.absoluteString, config.model, config.effort.rawValue]
            .joined(separator: "|")
    }
}
