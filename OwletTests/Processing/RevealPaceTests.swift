import Foundation
import Testing

@testable import Owlet

/// The pace the arrival is shown at: word by word, each pair staying a shortest time before the next,
/// and everything that has arrived on screen within its budget — so a fast reply still reads as a
/// process. Display only: none of this decides whether a reply counts as a result (BDR-0017).
struct RevealPaceTests {
    private let origin = Date(timeIntervalSince1970: 1_000)

    private func at(_ seconds: TimeInterval) -> Date {
        origin.addingTimeInterval(seconds)
    }

    private func pairs(_ targets: [String]) -> [TranslationResult.Segment] {
        targets.enumerated().map { .init(source: "source \($0.offset)", target: $0.element) }
    }

    @Test func nothingShowsBeforeAnythingArrives() {
        var pace = RevealPace()
        pace.advance(to: at(0))
        #expect(pace.visible.isEmpty)
        #expect(pace.isDrained)
    }

    @Test func wordsFollowOneAtATime() {
        var pace = RevealPace(word: 0.05, pairDwell: 0, budget: 10)
        pace.push(pairs(["Hello world"]), at: at(0))
        pace.advance(to: at(0))
        #expect(pace.visible.map(\.target) == ["Hello"])
        #expect(!pace.isDrained)
        pace.advance(to: at(0.04))
        #expect(pace.visible.map(\.target) == ["Hello"])
        pace.advance(to: at(0.05))
        #expect(pace.visible.map(\.target) == ["Hello world"])
        #expect(pace.isDrained)
    }

    /// Every pair is on screen for the shortest time before the next one starts, so even a stream
    /// that hands over several pairs at once is watched one pair after another.
    @Test func aPairStaysBeforeTheNextBegins() {
        var pace = RevealPace(word: 0.01, pairDwell: 0.3, budget: 10)
        pace.push(pairs(["Hi", "Bye"]), at: at(0))
        pace.advance(to: at(0))
        #expect(pace.visible.map(\.target) == ["Hi"])
        pace.advance(to: at(0.1))
        #expect(pace.visible.map(\.target) == ["Hi"])
        pace.advance(to: at(0.3))
        #expect(pace.visible.map(\.target) == ["Hi", "Bye"])
    }

    /// A short answer that arrived in one piece is still caught up with inside its budget, and it is
    /// seen arriving rather than appearing at once.
    @Test func aShortArrivalIsOnScreenWithinItsBudget() {
        var pace = RevealPace(word: 0.05, pairDwell: 0.3, budget: 1.2)
        pace.push(pairs((1...5).map { "pair \($0) has words" }), at: at(0))
        // The caller's own loop: wake, show what is due, sleep until the next word.
        var now: TimeInterval = 0
        var midway = 0
        var steps = 0
        while !pace.isDrained, steps < 2_000 {
            pace.advance(to: at(now))
            if now >= 0.5, midway == 0 { midway = pace.visible.count }
            if pace.isDrained { break }
            now += pace.wait
            steps += 1
        }
        #expect(pace.isDrained)
        #expect(midway > 0)
        #expect(midway < 5, "the answer arrived in stages, not in one jump")
        #expect(now <= 1.25, "the whole answer is on screen inside its budget")
        #expect(pace.visible.count == 5)
    }

    /// A paragraph waiting to be shown is not typed out at length: nobody can follow that much text
    /// arriving word by word, so it lands almost at once instead (BDR-0017).
    @Test func aLongArrivalLandsAlmostAtOnce() {
        var pace = RevealPace(word: 0.05, pairDwell: 0.3, budget: 1.2)
        pace.push(pairs((1...40).map { "pair \($0) has four words" }), at: at(0))
        var now: TimeInterval = 0
        var steps = 0
        while !pace.isDrained, steps < 4_000 {
            pace.advance(to: at(now))
            if pace.isDrained { break }
            now += pace.wait
            steps += 1
        }
        #expect(pace.isDrained)
        #expect(pace.visible.count == 40)
        #expect(now <= 0.2, "a paragraph is read, not watched: it lands inside the hurry")
        #expect(now >= 0.1, "…and still arrives rather than appearing whole")
    }

    /// Once the answer as a whole is past the length, what is left of it is not typed out either: the
    /// tail of a long answer lands almost at once instead of waiting out its budget word by word.
    @Test func aLongAnswerHurriesOnceItHasGrownPastTheLength() {
        var pace = RevealPace(word: 0.05, pairDwell: 0, budget: 1.2)
        pace.push(pairs((1...4).map { "pair \($0) has words" }), at: at(0))
        pace.advance(to: at(0.5))
        #expect(!pace.isDrained, "the first pairs are still being typed at the relaxed pace")
        pace.push(pairs((1...8).map { "pair \($0) has words" }), at: at(0.5))
        var now: TimeInterval = 0.5
        var steps = 0
        while !pace.isDrained, steps < 2_000 {
            pace.advance(to: at(now))
            if pace.isDrained { break }
            now += pace.wait
            steps += 1
        }
        #expect(pace.isDrained)
        #expect(now <= 0.7, "the rest of a long answer lands almost at once")
    }

    /// Whatever the pace, a surface is asked to redraw at most once a frame: the pace says what is due
    /// by when, and the caller looks again at the frame, not at every word of a fast arrival.
    @Test func theSurfaceIsRedrawnAtMostOnceAFrame() {
        var pace = RevealPace(word: 0.02, pairDwell: 0, budget: 0.5, hurry: 0.15, hurryWords: 30)
        pace.push(pairs((1...10).map { "pair \($0) has words" }), at: at(0))
        pace.advance(to: at(0))
        #expect(!pace.isDrained, "a paragraph arriving at once is not all shown in the first look")
        #expect(pace.wait >= 1.0 / 60 - 0.0001, "the next look waits for a frame, not for a millisecond")

        // The frame does not stretch the pace: what is due by the next look is shown then.
        var now: TimeInterval = 0
        var steps = 0
        while !pace.isDrained, steps < 4_000 {
            pace.advance(to: at(now))
            if pace.isDrained { break }
            now += pace.wait
            steps += 1
        }
        #expect(pace.isDrained)
        #expect(now <= 0.2, "the paragraph still lands inside its hurry")
        #expect(steps <= 20, "…in about a dozen redraws, not one per word")
    }

    /// A corrective round may take text back: what the stream no longer holds leaves the screen.
    @Test func aWithdrawnArrivalLeavesTheScreenAtOnce() {
        var pace = RevealPace(word: 0.05, pairDwell: 0, budget: 10)
        pace.push(pairs(["one two", "three"]), at: at(0))
        pace.advance(to: at(1))
        #expect(pace.visible.map(\.target) == ["one two", "three"])
        pace.push(pairs(["one two"]), at: at(1.1))
        pace.advance(to: at(1.1))
        #expect(pace.visible.map(\.target) == ["one two"])
    }

    /// The blank line between two sections is a pair with no words: it must not hold the rest back.
    @Test func aPairWithNoWordsShowsAtOnce() {
        var pace = RevealPace(word: 0.05, pairDwell: 0.3, budget: 10)
        pace.push(pairs(["", "Late"]), at: at(0))
        pace.advance(to: at(0))
        #expect(pace.visible.map(\.target) == [""])
        pace.advance(to: at(0.3))
        #expect(pace.visible.map(\.target) == ["", "Late"])
    }

    /// The wait says when the next word is due, so a caller sleeps per word instead of polling.
    @Test func theWaitSaysWhenTheNextWordIsDue() {
        var pace = RevealPace(word: 0.05, pairDwell: 0.3, budget: 10)
        pace.push(pairs(["one two", "three"]), at: at(0))
        pace.advance(to: at(0))
        #expect(abs(pace.wait - 0.05) < 0.0001)
        pace.advance(to: at(0.05))
        #expect(abs(pace.wait - 0.25) < 0.0001, "the second pair waits out the shortest time")
    }
}
