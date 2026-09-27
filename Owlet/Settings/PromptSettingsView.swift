import SwiftUI

/// Prompt group of the settings form: one editor per operation, the built-in default behind a
/// disclosure, a restore that only fills the draft, and the fixed JSON response example.
struct PromptSettingsView: View {
    @Binding var translateDraft: String
    @Binding var polishDraft: String
    /// Focus binding owned by the settings page, so the panel's format-error entry can raise the
    /// editor whose operation failed.
    @FocusState.Binding var focused: Operation?
    /// Operations whose saved prompt differs from the built-in default, which is what the badge shows.
    let customized: Set<Operation>
    /// Operation whose draft was blank on the last save attempt.
    let invalid: Operation?

    var body: some View {
        Section("Prompt") {
            editor(.translate, text: $translateDraft)
            editor(.polish, text: $polishDraft)
            responseExample
        }
    }

    /// One operation's editor, its state badge, the default disclosure and the restore action.
    @ViewBuilder private func editor(_ operation: Operation, text: Binding<String>) -> some View {
        let defaultPrompt = SettingsStore.defaultPrompt(for: operation)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("\(operation.title) System Prompt")
                Spacer(minLength: 0)
                Text(isCustomized(operation) ? "已自定义" : "默认")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            TextEditor(text: text)
                .font(.system(size: 12))
                .lineSpacing(3)
                .frame(minHeight: 120)
                .focused($focused, equals: operation)
                .accessibilityLabel("\(operation.title) System Prompt")
            if invalid == operation {
                Text("内容不能为空，请填写后再保存。")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
            HStack(alignment: .top, spacing: 12) {
                DisclosureGroup("查看默认 Prompt") {
                    Text(defaultPrompt)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }
                Spacer(minLength: 0)
                GlassEffectContainer {
                    // Fills the draft only: the contract makes 恢复默认 take effect on the next save.
                    Button("恢复默认") { text.wrappedValue = defaultPrompt }
                        .buttonStyle(.glass)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var responseExample: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("返回格式 · JSON")
                .font(.system(size: 12, weight: .semibold))
            DisclosureGroup("查看返回示例") {
                Text(DefaultPrompts.responseExample)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
    }

    /// Compares against the last save, not the draft, so 恢复默认 never claims to be in effect early.
    private func isCustomized(_ operation: Operation) -> Bool {
        customized.contains(operation)
    }
}
