import Foundation
import Testing

@testable import Owlet

/// The rows the 快捷键 page prints for the panel's fixed keys; the page renders exactly this data.
struct PanelKeyTests {
    @Test func listsThePanelsThreeKeysInPanelFooterOrder() {
        #expect(PanelKey.all.map(\.keys) == ["⌘ ↩", "⌘ ⇧ C", "Esc"])
    }

    /// A row without an action or a scope would render as a bare glyph, so the page's copy lives here.
    @Test func everyRowStatesWhatItDoesAndWhere() {
        for key in PanelKey.all {
            #expect(!key.title.isEmpty)
            #expect(!key.scope.isEmpty)
        }
    }

    @Test func everyKeyIsListedOnce() {
        #expect(Set(PanelKey.all.map(\.keys)).count == PanelKey.all.count)
    }

    /// Esc stops a run before it closes the panel, so its row has to name both outcomes.
    @Test func escapeRowNamesBothOutcomes() {
        let escape = PanelKey.all.first { $0.keys == "Esc" }
        #expect(escape?.title == "停止处理 / 关闭")
    }
}
