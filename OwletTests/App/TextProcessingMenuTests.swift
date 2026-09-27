import Testing

@testable import Owlet

/// The 文本处理 menu's two decisions, which are the parts a test can reach: SwiftUI menu wiring is
/// not unit-testable, and the rest of the item is a direct call into the model.
@MainActor
struct TextProcessingMenuTests {
    @Test func theSubmitItemIsNamedForTheCurrentOperation() {
        #expect(TextProcessingCommands.submitTitle(for: .translate) == "翻译文本")
        #expect(TextProcessingCommands.submitTitle(for: .polish) == "润色文本")
    }

    @Test func copyIsOfferedOnlyWithAResult() {
        #expect(TextProcessingCommands.canCopy(.success("你好")))
        #expect(!TextProcessingCommands.canCopy(.idle))
        #expect(!TextProcessingCommands.canCopy(.loading))
        #expect(!TextProcessingCommands.canCopy(.failure("boom")))
        #expect(!TextProcessingCommands.canCopy(.missingConfig))
    }
}
