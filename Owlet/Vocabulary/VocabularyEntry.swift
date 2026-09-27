import Foundation
import SwiftData

/// A collected expression — word, phrase or sentence — keyed by its language and its
/// whitespace-trimmed text, so the same expression is never stored twice.
@Model
final class VocabularyEntry {
    #Unique<VocabularyEntry>([\.language, \.expression])

    var expression: String = ""
    var language: String = ""
    /// Simplified Chinese meaning; empty until the meaning request succeeds.
    var meaning: String = ""
    var createdAt: Date = Date()
    /// Cascades, so deleting an entry also removes the sentences it was collected from.
    @Relationship(deleteRule: .cascade, inverse: \VocabularyContext.entry)
    var contexts: [VocabularyContext] = []

    init(expression: String, language: String, meaning: String = "", createdAt: Date = Date()) {
        self.expression = expression
        self.language = language
        self.meaning = meaning
        self.createdAt = createdAt
    }
}

/// One independent snapshot of the sentence an expression was collected from, plus the polish
/// before/after pair when the expression came from a polish result.
@Model
final class VocabularyContext {
    var source: String = ""
    var polishBefore: String?
    var polishAfter: String?
    var createdAt: Date = Date()
    var entry: VocabularyEntry?

    init(
        source: String, polishBefore: String? = nil, polishAfter: String? = nil,
        createdAt: Date = Date()
    ) {
        self.source = source
        self.polishBefore = polishBefore
        self.polishAfter = polishAfter
        self.createdAt = createdAt
    }
}

/// The snapshot a collect action takes from the current source or result.
struct VocabularyDraft: Equatable {
    var expression: String
    var language: String
    /// The sentence the expression was collected from; the meaning request uses it as context.
    var context: String
    var polishBefore: String?
    var polishAfter: String?
}
