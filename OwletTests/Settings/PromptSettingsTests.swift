import Foundation
import Testing

@testable import Owlet

/// Prompt settings persist per operation, refuse blank text, and fall back to the built-in default.
struct PromptSettingsTests {
    let suite = "PromptSettingsTests.\(UUID().uuidString)"
    var defaults: UserDefaults { UserDefaults(suiteName: suite)! }

    @Test func noSavedPromptUsesTheBuiltInDefault() {
        #expect(SettingsStore.prompt(for: .translate, in: defaults) == DefaultPrompts.translate)
        #expect(SettingsStore.prompt(for: .polish, in: defaults) == DefaultPrompts.polish)
        #expect(!SettingsStore.isCustomized(.translate, in: defaults))
        #expect(!SettingsStore.isCustomized(.polish, in: defaults))
    }

    @Test func aSavedPromptReadsBackAsCustomizedAndStaysPerOperation() {
        #expect(SettingsStore.setPrompt("只输出 JSON", for: .translate, in: defaults))
        #expect(SettingsStore.prompt(for: .translate, in: defaults) == "只输出 JSON")
        #expect(SettingsStore.isCustomized(.translate, in: defaults))
        #expect(SettingsStore.prompt(for: .polish, in: defaults) == DefaultPrompts.polish)
        #expect(!SettingsStore.isCustomized(.polish, in: defaults))
    }

    @Test func blankTextIsRefusedAndKeepsThePreviousValue() {
        #expect(SettingsStore.setPrompt("保留", for: .translate, in: defaults))
        #expect(!SettingsStore.setPrompt("   \n\t ", for: .translate, in: defaults))
        #expect(SettingsStore.prompt(for: .translate, in: defaults) == "保留")
    }

    /// Saving the built-in text is the restore path, so the state must read Default again.
    @Test func savingTheDefaultClearsTheCustomMark() {
        #expect(SettingsStore.setPrompt("自定义", for: .translate, in: defaults))
        #expect(SettingsStore.isCustomized(.translate, in: defaults))
        #expect(SettingsStore.setPrompt(DefaultPrompts.translate, for: .translate, in: defaults))
        #expect(!SettingsStore.isCustomized(.translate, in: defaults))
        #expect(SettingsStore.prompt(for: .translate, in: defaults) == DefaultPrompts.translate)
    }

    /// Each editor commits on its own, so a blank one must not disturb the other operation.
    @Test func aRefusedBlankLeavesTheOtherOperationAlone() {
        #expect(SettingsStore.setPrompt("翻译2", for: .translate, in: defaults))
        #expect(!SettingsStore.setPrompt("  ", for: .polish, in: defaults))
        #expect(SettingsStore.prompt(for: .translate, in: defaults) == "翻译2")
        #expect(SettingsStore.prompt(for: .polish, in: defaults) == DefaultPrompts.polish)
    }
}
