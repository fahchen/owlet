import SwiftUI

/// Prompt pane: one editor per operation, the built-in default behind a disclosure, a restore that
/// only fills the editor, and the fixed JSON response example. There is no save button: an editor
/// commits when it gives up focus, so the settings window behaves like a settings window.
struct PromptSettingsPane: View {
    /// One-shot request from the panel's contract-error entry, so the failing operation's editor is
    /// the one that focuses.
    @Binding var promptFocus: Operation?
    @State private var translateDraft = ""
    @State private var polishDraft = ""
    /// Operations whose saved prompt differs from the built-in default, which is what the badge shows.
    @State private var customized: Set<Operation> = []
    /// Operation whose draft was blank when it last tried to commit.
    @State private var invalid: Operation?
    @FocusState private var focused: Operation?

    var body: some View {
        Form {
            editor(.translate, text: $translateDraft)
            editor(.polish, text: $polishDraft)
            Section {
                DisclosureGroup("查看返回示例") {
                    Text(DefaultPrompts.responseExample)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }
            } header: {
                Text("返回格式 · JSON")
            } footer: {
                Text("改动在编辑框失去焦点后生效，只影响之后的新请求。")
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: load)
        .onChange(of: promptFocus) { _, _ in applyFocus() }
        // Committing on the edge of focus is what replaces the old save button; leaving the pane also
        // gives up focus, so switching tabs cannot lose an edit.
        .onChange(of: focused) { previous, current in
            if let previous, previous != current { commit(previous) }
        }
        .onDisappear { if let focused { commit(focused) } }
    }

    /// One operation's editor, its state badge, the default disclosure and the restore action.
    @ViewBuilder private func editor(_ operation: Operation, text: Binding<String>) -> some View {
        let defaultPrompt = SettingsStore.defaultPrompt(for: operation)
        Section {
            TextEditor(text: text)
                .font(.system(size: 12))
                .lineSpacing(3)
                .frame(minHeight: 120)
                .focused($focused, equals: operation)
                .accessibilityLabel("\(operation.title) System Prompt")
            if invalid == operation {
                Text("内容不能为空；这次改动没有生效。")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
            DisclosureGroup("查看默认 Prompt") {
                Text(defaultPrompt)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }
            GlassEffectContainer {
                // Fills the editor only: the restore takes effect when the editor commits.
                Button("恢复默认") { text.wrappedValue = defaultPrompt }
                    .buttonStyle(.glass)
            }
        } header: {
            HStack {
                Text("\(operation.title) System Prompt")
                Spacer(minLength: 0)
                Text(customized.contains(operation) ? "已自定义" : "默认")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Writes one editor's text; a blank draft is refused so the previous text stays in force.
    private func commit(_ operation: Operation) {
        let draft = operation == .translate ? translateDraft : polishDraft
        if SettingsStore.setPrompt(draft, for: operation) {
            invalid = nil
            customized = Set(Operation.allCases.filter { SettingsStore.isCustomized($0) })
        } else {
            invalid = operation
        }
    }

    /// Loads the effective prompts into the editors and remembers which ones are customised.
    private func load() {
        translateDraft = SettingsStore.prompt(for: .translate)
        polishDraft = SettingsStore.prompt(for: .polish)
        customized = Set(Operation.allCases.filter { SettingsStore.isCustomized($0) })
        invalid = nil
    }

    /// Focuses the editor the panel asked for, then clears the one-shot request.
    private func applyFocus() {
        guard let operation = promptFocus else { return }
        focused = operation
        promptFocus = nil
    }
}
