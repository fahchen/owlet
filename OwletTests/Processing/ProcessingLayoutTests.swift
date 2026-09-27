import Testing

@testable import Owlet

/// The 文本处理 page switches arrangement at exactly 720pt of content area.
struct ProcessingLayoutTests {
    @Test func switchesAtTheThreshold() {
        #expect(ProcessingLayout.sideBySideThreshold == 720)
        #expect(ProcessingLayout.choose(width: 719) == .stacked)
        #expect(ProcessingLayout.choose(width: 720) == .sideBySide)
        #expect(ProcessingLayout.choose(width: 1200) == .sideBySide)
    }
}
