import SwiftUI

/// The app's settings window. The `Settings` scene in `OwletApp` is what puts 设置… and ⌘, in the App
/// menu; this view is its content: one tab per group of settings, each tab a `Form` of sections.
struct SettingsView: View {
    /// The pane to open on, kept so the window returns to the last one people used.
    @AppStorage(SettingsStore.settingsPaneKey) private var pane = SettingsPane.general.rawValue
    /// The app's shortcut registry; its pane records the global bindings.
    let shortcuts: ShortcutController
    /// One-shot request from the panel's contract-error entry: open the 模型 pane, focused.
    @Binding var promptFocus: Operation?
    @AppStorage(SettingsStore.debugEnabledKey) private var debugEnabled = false

    var body: some View {
        TabView(selection: $pane) {
            Tab("General", systemImage: "gearshape", value: SettingsPane.general.rawValue) {
                GeneralSettingsPane()
            }
            Tab("Languages", systemImage: "character.bubble", value: SettingsPane.language.rawValue) {
                LanguageSettingsPane()
            }
            Tab("Model", systemImage: "cloud", value: SettingsPane.model.rawValue) {
                ModelSettingsPane(promptFocus: $promptFocus)
            }
            Tab("Shortcuts", systemImage: "keyboard", value: SettingsPane.shortcuts.rawValue) {
                ShortcutSettingsPane(controller: shortcuts)
            }
            // The diagnostics pane exists only while it is switched on, which is the point of the
            // switch: a fresh install shows four panes and nothing else.
            if debugEnabled {
                Tab("Debug", systemImage: "ladybug", value: SettingsPane.debug.rawValue) {
                    DebugSettingsPane()
                }
            }
        }
        .frame(width: 620, height: 560)
        .onAppear {
            normalisePane()
            applyPromptFocus()
        }
        .onChange(of: promptFocus) { _, _ in applyPromptFocus() }
    }

    /// The failing operation's editor lives on the 模型 pane, so the pane follows the request.
    private func applyPromptFocus() {
        if promptFocus != nil { pane = SettingsPane.model.rawValue }
    }

    /// A pane that no longer exists (the Prompt tab was folded into 模型) or is hidden (调试 showing
    /// while the switch is off) must not leave the window blank.
    private func normalisePane() {
        if pane == "prompt" {
            pane = SettingsPane.model.rawValue
        } else if SettingsPane(rawValue: pane) == nil
            || (pane == SettingsPane.debug.rawValue && !debugEnabled)
        {
            pane = SettingsPane.general.rawValue
        }
    }
}

/// The panes, in toolbar order. The raw value is what gets stored, so reordering cases never
/// invalidates a saved choice.
enum SettingsPane: String, CaseIterable {
    case general, language, model, shortcuts, debug
}
