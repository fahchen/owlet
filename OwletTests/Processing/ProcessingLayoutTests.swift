import Testing

@testable import Owlet

/// The Text page switches arrangement at exactly 600pt of content area.
struct ProcessingLayoutTests {
    @Test func switchesAtTheThreshold() {
        #expect(ProcessingLayout.sideBySideThreshold == 600)
        #expect(ProcessingLayout.choose(width: 599) == .stacked)
        #expect(ProcessingLayout.choose(width: 600) == .sideBySide)
        #expect(ProcessingLayout.choose(width: 1200) == .sideBySide)
    }
}
