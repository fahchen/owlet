import Foundation
import Testing

@testable import Owlet

/// The detector decides the source language before the request, because the target mapping needs a
/// target before the model can report a source. The samples are fixed; the thresholds are what keep
/// an unsure answer away from the fallback target.
struct LanguageDetectorTests {
    @Test func englishIsDetected() {
        #expect(LanguageDetector.detect("Could you send me the report?") == "en")
    }

    @Test func simplifiedChineseIsDetected() {
        #expect(LanguageDetector.detect("请把报告发给我。") == "zh-Hans")
    }

    @Test func japaneseIsDetected() {
        #expect(LanguageDetector.detect("お手数ですが、明日までにご確認いただけますと幸いです。") == "ja")
    }

    @Test func blankTextIsUnknown() {
        #expect(LanguageDetector.detect("") == nil)
        #expect(LanguageDetector.detect("   \n\t ") == nil)
    }

    /// A single word is not enough to trust, so the caller uses the fallback target instead of
    /// guessing a direction from one token.
    @Test func aSingleWordIsUnknown() {
        #expect(LanguageDetector.detect("Hello") == nil)
        #expect(LanguageDetector.detect("OK") == nil)
    }

    /// 好 is valid in both Chinese scripts, so the near tie must not be guessed either.
    @Test func aCoinFlipIsUnknown() {
        #expect(LanguageDetector.detect("好") == nil)
    }
}

/// The comparison key: the primary subtag decides, and Chinese keeps its script because Simplified and
/// Traditional Chinese are different targets in the contract.
struct LanguageTagTests {
    @Test func chineseKeepsItsScript() {
        #expect(LanguageTag.key("zh") == "zh-Hans")
        #expect(LanguageTag.key("zh-CN") == "zh-Hans")
        #expect(LanguageTag.key("zh_TW") == "zh-Hant")
        #expect(LanguageTag.key("zh-Hant") == "zh-Hant")
    }

    @Test func otherLanguagesUseThePrimarySubtag() {
        #expect(LanguageTag.key("en-US") == "en")
        #expect(LanguageTag.key("JA") == "ja")
        #expect(LanguageTag.same("en", "en-US"))
        #expect(!LanguageTag.same("zh-Hans", "zh-Hant"))
    }
}
