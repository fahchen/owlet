import Foundation
import NaturalLanguage

/// Guesses the source language before the request, because the target mapping needs a target before
/// the model can report a source. Detection only picks the target: the response contract still
/// decides what is valid, and a low-confidence answer is treated as unknown and left to the fallback.
enum LanguageDetector {
    /// Below this the answer is not trusted, so the caller falls back.
    static let minimumConfidence = 0.5
    /// The winner must also beat the runner-up by this much, so a text that mixes two languages — or
    /// a Chinese script guess that is nearly a coin flip — is unknown instead of guessed.
    static let minimumMargin = 0.2
    /// Only the head of a long selection is inspected: enough to decide, and cheaper than the whole.
    static let sampleLength = 400

    /// The canonical source tag (`en`, `ja`, `zh-Hans`, `zh-Hant`), or nil when unsure.
    static func detect(_ text: String) -> String? {
        let sample = String(text.prefix(sampleLength))
        guard !TranslationResult.isBlank(sample) else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        guard let dominant = recognizer.dominantLanguage else { return nil }
        let ranked = recognizer.languageHypotheses(withMaximum: 2).sorted { $0.value > $1.value }
        guard let top = ranked.first, top.key == dominant, top.value >= minimumConfidence else {
            return nil
        }
        if ranked.count > 1, top.value - ranked[1].value < minimumMargin { return nil }
        return LanguageTag.key(dominant.rawValue)
    }
}
