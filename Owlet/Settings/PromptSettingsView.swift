import SwiftUI

/// The two prompt editors, as sections of the Model pane: they are about how the model is asked, which
/// is the same concern as which model is asked. There is no save button: an editor commits when it
/// gives up focus, so the settings window behaves like a settings window.
struct PromptSettingsView: View {
    /// One-shot request from the panel's contract-error entry, so the failing operation's editor is
    /// the one that focuses.
    @Binding var promptFocus: Operation?
    @State private var translateDraft = ""
    @State private var polishDraft = ""
    /// Operation whose draft was blank when it last tried to commit.
    @State private var invalid: Operation?
    /// Operation whose restore is waiting to be confirmed; restoring throws away the editor's text, so
    /// it is asked about first.
    @State private var restoring: Operation?
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
        .confirmationDialog(
            L10n.shared.string("Restore the default prompt?"),
            isPresented: Binding(
                get: { restoring != nil }, set: { if !$0 { restoring = nil } }),
            titleVisibility: .visible
        ) {
            Button(L10n.shared.string("Restore Default"), role: .destructive) {
                if let restoring { restore(restoring) }
                restoring = nil
            }
            Button(L10n.shared.string("Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.shared.string("Your edits to this prompt will be lost."))
        }
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
            // The editor is one row of the grouped form, not a surface of its own: the default
            // `TextEditor` chrome paints an inset white block that reads as a hole in the card, so the
            // system styles are asked to leave the form's own background showing through.
            TextEditor(text: text)
                .font(.system(size: 12))
                .lineSpacing(3)
                .frame(minHeight: 120)
                .textEditorStyle(.plain)
                .scrollContentBackground(.hidden)
                .focused($focused, equals: operation)
                .accessibilityLabel(L10n.shared.string("%@ System Prompt", operation.name))
            if invalid == operation {
                Text(L10n.shared.string("The content cannot be empty; this change was not applied."))
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
        } header: {
            HStack(spacing: 8) {
                Text(L10n.shared.string("%@ System Prompt", operation.name))
                Spacer(minLength: 0)
                // The restore action rests in the same spot whether or not it can do anything, so the
                // header does not move as the text changes; it is enabled exactly while the editor
                // holds something other than the built-in default, so it never does nothing.
                Button(L10n.shared.string("Restore Default"), systemImage: "arrow.counterclockwise") {
                    restoring = operation
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(text.wrappedValue == defaultPrompt)
            }
        }
    }

    /// Confirms a restore: the editor gets the built-in default and it is persisted on the spot, because
    /// the dialog took focus and waiting for the editor to lose it again would leave the old text in
    /// force for as long as the pane stays open.
    private func restore(_ operation: Operation) {
        switch operation {
        case .translate: translateDraft = SettingsStore.defaultPrompt(for: operation)
        case .polish: polishDraft = SettingsStore.defaultPrompt(for: operation)
        }
        commit(operation)
    }

    /// Writes one editor's text; a blank draft is refused so the previous text stays in force.
    private func commit(_ operation: Operation) {
        let draft = operation == .translate ? translateDraft : polishDraft
        invalid = SettingsStore.setPrompt(draft, for: operation) ? nil : operation
    }

    /// Loads the effective prompts into the editors.
    private func load() {
        translateDraft = SettingsStore.prompt(for: .translate)
        polishDraft = SettingsStore.prompt(for: .polish)
        invalid = nil
    }

    /// Focuses the editor the panel asked for, then clears the one-shot request.
    private func applyFocus() {
        guard let operation = promptFocus else { return }
        focused = operation
        promptFocus = nil
    }
}
