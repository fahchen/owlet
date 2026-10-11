import Foundation
import SwiftData

/// A collected expression — word, phrase or sentence — keyed by its language and its
/// whitespace-trimmed text, so the same expression is never stored twice.
@Model
final class VocabularyEntry {
    #Unique<VocabularyEntry>([\.language, \.expression])

    var expression: String = ""
    var language: String = ""
    /// The dictionary form and the meaning's language, both known only when a lookup or a learning
    /// recommendation supplied them; empty means "not known", which is also every entry saved before
    /// these fields existed (BDR-0009).
    var lemma: String = ""
    var definitionLocale: String = ""
    /// Simplified Chinese meaning; empty until the meaning request succeeds.
    var meaning: String = ""
    var createdAt: Date = Date()
    /// Cascades, so deleting an entry also removes the sentences it was collected from.
    @Relationship(deleteRule: .cascade, inverse: \VocabularyContext.entry)
    var contexts: [VocabularyContext] = []

    /// A lookup in this entry is explained in its meaning's language (BDR-0005), which older entries
    /// do not record, so they fall back to the Simplified Chinese they were all saved with.
    var lookupOrigin: LookupOrigin {
        LookupOrigin(
            language: language,
            definitionLanguage: definitionLocale.isEmpty ? "zh-Hans" : definitionLocale)
    }

    init(
        expression: String, language: String, meaning: String = "", createdAt: Date = Date(),
        lemma: String = "", definitionLocale: String = ""
    ) {
        self.expression = expression
        self.language = language
        self.meaning = meaning
        self.createdAt = createdAt
        self.lemma = lemma
        self.definitionLocale = definitionLocale
    }
}

/// One independent snapshot of the sentence an expression was collected from, plus the polish
/// before/after pair when the expression came from a polish result.
@Model
final class VocabularyContext {
    var source: String = ""
    /// The language this sentence is written in, which is not always the entry's: collecting an
    /// English expression out of a Chinese translation stores a Chinese 原句 under an `en` entry.
    /// Empty when the region could not tell (a translation's source language is never stored).
    var language: String = ""
    var polishBefore: String?
    var polishAfter: String?
    var createdAt: Date = Date()
    var entry: VocabularyEntry?

    init(
        source: String, language: String = "", polishBefore: String? = nil,
        polishAfter: String? = nil, createdAt: Date = Date()
    ) {
        self.source = source
        self.language = language
        self.polishBefore = polishBefore
        self.polishAfter = polishAfter
        self.createdAt = createdAt
    }
}

extension VocabularyContext {
    /// Whether this snapshot is the same collected context as another after trimming each string's
    /// leading and trailing whitespace only, so re-submitting one collect action never appends twice.
    func hasSameContent(as other: VocabularyContext) -> Bool {
        func normalized(_ value: String?) -> String? {
            value?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return source.trimmingCharacters(in: .whitespacesAndNewlines)
            == other.source.trimmingCharacters(in: .whitespacesAndNewlines)
            && normalized(polishBefore) == normalized(other.polishBefore)
            && normalized(polishAfter) == normalized(other.polishAfter)
    }
}

/// The snapshot a collect action takes from the current source or result.
struct VocabularyDraft: Equatable {
    var expression: String
    var language: String
    /// The sentence the expression was collected from; the meaning request uses it as context.
    var context: String
    /// The language of that sentence. It differs from `language` whenever the expression was taken
    /// from the result of a translation, whose 原句 stays in the source language.
    var contextLanguage: String?
    var polishBefore: String?
    var polishAfter: String?
    /// The dictionary form and the meaning's language when the source knows them (BDR-0009 and
    /// BDR-0005); nil from regions that only have text.
    var lemma: String?
    var definitionLocale: String?
}
