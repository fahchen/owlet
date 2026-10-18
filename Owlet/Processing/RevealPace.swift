import Foundation
import NaturalLanguage

/// Turns what a stream has completed into what a display may show now: the pairs in arrival order,
/// each one a word at a time, and each one staying for at least `pairDwell` before the next begins.
/// A reply that arrived in one piece therefore still reads as a process, and one that arrives faster
/// than the pace is caught up with within `budget` of the moment its text arrived, so a whole answer
/// never waits to be seen for long.
///
/// Display only (BDR-0017): this decides when text is seen, never whether it counts as a result.
struct RevealPace {
    /// Seconds between one word and the next, while there is room for that pace.
    var word: TimeInterval = 0.02
    /// The shortest time a pair stays on screen before the next pair starts, while there is room.
    var pairDwell: TimeInterval = 0.1
    /// The longest text that has already arrived waits to be on screen.
    var budget: TimeInterval = 0.5
    /// The floor between words once the deadline presses.
    var floor: TimeInterval = 0.0025

    /// Everything the stream has completed, in arrival order.
    private var queue: [TranslationResult.Segment] = []
    /// Words in each queued target.
    private var counts: [Int] = []
    /// Pairs fully on screen, and words on screen of the pair being typed.
    private var shown = 0
    private var words = 0
    /// Where the words of the pair being typed end, so a step need not tokenise it again.
    private var ends: [String.Index]?
    /// When the pair being typed first appeared, and when its next word is due.
    private var pairStarted: Date?
    private var dueWord = Date.distantPast
    /// By when everything that has arrived is to be on screen.
    private var dueBy = Date.distantPast

    /// How long until `advance` could change what is on screen; set by the last `advance`.
    private(set) var wait: TimeInterval = 0

    /// Whether everything that has arrived is on screen.
    var isDrained: Bool { shown == queue.count }

    /// The pairs and word prefixes a display may show right now.
    var visible: [TranslationResult.Segment] {
        var pairs = Array(queue.prefix(shown))
        guard words > 0, shown < queue.count else { return pairs }
        let target = queue[shown].target
        let boundaries = ends ?? Self.wordEnds(target)
        let end = boundaries[min(words, boundaries.count) - 1]
        pairs.append(.init(source: queue[shown].source, target: String(target[..<end])))
        return pairs
    }

    /// What the stream has completed. The pairs replace whatever was queued — a corrective round may
    /// take text back — and a fresh arrival renews the deadline for everything waiting.
    mutating func push(_ pairs: [TranslationResult.Segment], at now: Date) {
        queue = pairs
        counts = pairs.map { Self.wordEnds($0.target).count }
        shown = min(shown, queue.count)
        if shown == queue.count { words = 0 }
        // The pair being typed may be the one that just went: its text decides where its words end.
        if words > 0, shown < queue.count {
            ends = Self.wordEnds(queue[shown].target)
        } else {
            ends = nil
        }
        dueWord = max(dueWord, now)
        dueBy = max(dueBy, now.addingTimeInterval(budget))
    }

    /// Puts every word that is due on screen, and records how long to wait for the next one.
    mutating func advance(to now: Date) {
        wait = 0
        while true {
            guard shown < queue.count else { return }
            if words == 0, shown > 0, let started = pairStarted, lingers(now, since: started) {
                wait = max(0.001, started.addingTimeInterval(pairDwell).timeIntervalSince(now))
                return
            }
            guard now >= dueWord else {
                wait = max(0.001, dueWord.timeIntervalSince(now))
                return
            }
            reveal(at: now)
        }
    }

    /// Whether the pair about to start waits its turn: it does while the previous pair has not been
    /// on screen for `pairDwell` yet, and only while the text that has arrived still has room to be
    /// shown at the relaxed pace.
    private func lingers(_ now: Date, since started: Date) -> Bool {
        guard now < started.addingTimeInterval(pairDwell) else { return false }
        return dueBy.timeIntervalSince(now) - Double(remainingWords) * word >= pairDwell
    }

    private mutating func reveal(at now: Date) {
        guard shown < queue.count else { return }
        if counts[shown] == 0 {
            // A pair with no words of its own — the blank line between two sections — is on screen at
            // once, so a wordless target can never hold the rest back.
            shown += 1
            pairStarted = now
        } else {
            if ends == nil { ends = Self.wordEnds(queue[shown].target) }
            words += 1
            if words == 1 { pairStarted = now }
            if words >= counts[shown] {
                shown += 1
                words = 0
                ends = nil
            }
        }
        dueWord += step(at: now)
    }

    /// How long the next word may take: the relaxed pace while there is room, and faster as the
    /// deadline for what has already arrived comes close.
    private func step(at now: Date) -> TimeInterval {
        let remaining = Double(remainingWords)
        guard remaining > 0 else { return word }
        return min(word, max(floor, dueBy.timeIntervalSince(now) / remaining))
    }

    /// Words of the queued pairs that are not on screen yet.
    private var remainingWords: Int {
        counts[min(shown, counts.count)...].reduce(0, +) - words
    }

    /// Where each word of a target ends, so a target can be shown up to a word boundary.
    private static func wordEnds(_ text: String) -> [String.Index] {
        guard !text.isEmpty else { return [] }
        var ends: [String.Index] = []
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            ends.append(range.upperBound)
            return true
        }
        return ends
    }
}
