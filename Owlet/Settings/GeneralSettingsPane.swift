import SwiftUI

/// 通用 pane: the preferences that are neither about languages nor about the model.
struct GeneralSettingsPane: View {
    @AppStorage(SettingsStore.translateLearningKey) private var translateLearning = false
    @AppStorage(SettingsStore.polishLearningKey) private var polishLearning = false
    @AppStorage(SettingsStore.displayModeKey) private var displayMode =
        TranslationDisplayMode.sectioned
    @AppStorage(SettingsStore.panelPositionKey) private var panelPosition = PanelPosition.fixed
    @AppStorage(SettingsStore.debugEnabledKey) private var debugEnabled = false

    @AppStorage(SettingsStore.panelGlassEffectKey) private var panelGlassEffect = PanelGlassEffect.contrast
    @AppStorage(SettingsStore.appLanguageKey) private var appLanguage = ""
    /// The chosen language, including the default "follow the system" the key cannot express by itself.
    private var language: AppLanguage {
        AppLanguage(rawValue: appLanguage) ?? .system
    }

    var body: some View {
        Form {
            Section {
                Picker(L10n.shared.string("Interface Language"), selection: languageBinding) {
                    ForEach(AppLanguage.selectable) { Text(verbatim: $0.title).tag($0) }
                }
            }
            Section(L10n.shared.string("Text")) {
                Picker(L10n.shared.string("Translation Display"), selection: $displayMode) {
                    ForEach(TranslationDisplayMode.allCases, id: \.self) {
                        Text(verbatim: L10n.shared.string($0.title.key)).tag($0)
                    }
                }
            }
            Section(L10n.shared.string("Study")) {
                Toggle(L10n.shared.string("Request study expressions after translating"), isOn: $translateLearning)
                Toggle(L10n.shared.string("Request study expressions after polishing"), isOn: $polishLearning)
            }
            Section(L10n.shared.string("Panel")) {
                Picker(L10n.shared.string("Glass Effect"), selection: $panelGlassEffect) {
                    ForEach(PanelGlassEffect.allCases, id: \.self) {
                        Text(verbatim: L10n.shared.string($0.title.key)).tag($0)
                    }
                }

                // The picker above only chooses between the two glass variants; the intensity itself is
                // a system-wide setting, so this points there rather than pretending to own it.
                VStack(alignment: .leading, spacing: 6) {
                    Text(
                        L10n.shared.string(
                            "Liquid Glass and its intensity are adjusted in System Settings › Appearance."
                        )
                    )
                    .foregroundStyle(.secondary)
                    if let url = SettingsStore.appearanceSettingsURL {
                        Link(L10n.shared.string("Open System Settings"), destination: url)
                    }
                }

                Picker(L10n.shared.string("Panel Position"), selection: $panelPosition) {
                    ForEach(PanelPosition.allCases, id: \.self) {
                        Text(verbatim: L10n.shared.string($0.title.key)).tag($0)
                    }
                }
            }
            Section {
                Toggle(L10n.shared.string("Show the Debug Page"), isOn: debugSwitch)
            } header: {
                Text(L10n.shared.string("Debug"))
            } footer: {
                Text(
                    L10n.shared.string(
                        "Show the Debug page in settings, which keeps the last few model requests and replies."))
            }
        }
        .formStyle(.grouped)
    }

    /// Applies the pick the moment it changes, so the next launch already speaks it.
    private var languageBinding: Binding<AppLanguage> {
        Binding(
            get: { language },
            set: {
                // Saved for the next launch and applied now: the interface is rebuilt from `L10n`, so
                // the change shows without restarting.
                AppLanguage.apply($0)
                L10n.shared.use($0)
            })
    }

    /// Recording is already gated on this switch; clearing on the way out also drops what was
    /// captured while it was on, so nothing stays in memory once the page is gone.
    private var debugSwitch: Binding<Bool> {
        Binding(
            get: { debugEnabled },
            set: { on in
                debugEnabled = on
                if !on { DebugLog.shared.clear() }
            })
    }
}
