import Foundation
import Testing

@testable import Owlet

/// The fixed keys the Shortcuts page lists and the buttons bind; the page renders exactly this data.
struct KeyHintTests {
    @Test func printsCombinationsTheWayMenusDo() {
        #expect(KeyHint.panelReplace.keys == "⌘↩")
        #expect(KeyHint.panelCopy.keys == "⌘C")
        #expect(KeyHint.panelCancel.keys == "Esc")
        #expect(KeyHint.delete.keys == "⌘⌫")
        // The tooltip is the action's name followed by its key. The name is translated, so this checks
        // the shape and the combination rather than the wording, which the catalog owns.
        #expect(KeyHint.copy.tooltip.hasSuffix(" ⌘C"))
        #expect(KeyHint.copy.tooltip != " ⌘C")
        #expect(KeyHint.panelReplace.tooltip.hasSuffix(" ⌘↩"))
        #expect(KeyHint.lookUp.keys == "↩")
    }

    /// A cell without an action would render as a bare glyph.
    @Test func everyKeyStatesWhatItDoes() {
        for group in KeyHint.groups {
            for key in group.keys { #expect(!key.title.isEmpty) }
        }
    }

    @Test func noKeyIsClaimedTwiceInOnePlace() {
        for group in KeyHint.groups {
            #expect(Set(group.keys.map(\.keys)).count == group.keys.count)
        }
    }

    /// Esc stops a run before it closes the panel, so its row has to name both outcomes.
    @Test func escapeRowNamesBothOutcomes() {
        #expect(KeyHint.panelCancel.title == "Stop / Close")
    }
}
