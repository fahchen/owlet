import SwiftUI

/// The two prompt editors, as sections of the 模型 pane: they are about how the model is asked, which
/// is the same concern as which model is asked. There is no save button: an editor commits when it
/// gives up focus, so the settings window behaves like a settings window.
struct PromptSettingsView: View {
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
        // The two sections are handed to the surrounding `Form`; the lifecycle lives on the group so
        // it does not attach to whichever section happens to be last.
        Group {
            editor(.translate, text: $translateDraft)
            editor(.polish, text: $polishDraft)
        }
        .onAppear(perform: load)
        .onChange(of: promptFocus) { _, _ in applyFocus() }
        // Committing on the edge of focus is what replaces the old save button; leaving the pane also
        // gives up focus, so switching tabs cannot lose an edit.
        .onChange(of: focused) { previous, current in
            if let previous, previous != current { commit(previous) }
        }
        .onDisappear { if let focused { commit(focused) } }
    }

    /// One operation's editor, its header accessory and the restore action.
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
                Text("The content cannot be empty; this change was not applied.")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
        } header: {
            HStack(spacing: 8) {
                Text("\(operation.title) System Prompt")
                Spacer(minLength: 0)
                // The restore is only worth offering once there is something to restore.
                if customized.contains(operation) {
                    Button("Restore Default", systemImage: "arrow.uturn.backward") {
                        text.wrappedValue = defaultPrompt
                    }
                    .buttonStyle(.borderless)
                } else {
                    Text("Default")
                        .foregroundStyle(.secondary)
                }
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
