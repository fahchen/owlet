import Foundation
import Testing

@testable import Owlet

/// The fixed keys the 快捷键 page lists and the buttons bind; the page renders exactly this data.
struct KeyHintTests {
    @Test func printsCombinationsTheWayMenusDo() {
        #expect(KeyHint.panelReplace.keys == "⌘↩")
        #expect(KeyHint.panelCopy.keys == "⌘C")
        #expect(KeyHint.panelCancel.keys == "Esc")
        #expect(KeyHint.delete.keys == "⌘⌫")
        #expect(KeyHint.copy.tooltip == "复制 ⌘C")
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
        #expect(KeyHint.panelCancel.title == "停止处理 / 关闭")
    }
}
