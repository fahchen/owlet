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
                Picker("界面语言", selection: languageBinding) {
                    // Verbatim: a language's own name must not be looked up in the catalog.
                    ForEach(AppLanguage.selectable) { Text(verbatim: $0.title).tag($0) }
                }
            } footer: {
                Text("改动在下次启动 Owlet 后生效。")
            }
            Section("文本处理") {
                Picker("翻译显示方式", selection: $displayMode) {
                    ForEach(TranslationDisplayMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }
            Section("学习") {
                Toggle("翻译后自动请求学习表达", isOn: $translateLearning)
                Toggle("润色后自动请求学习表达", isOn: $polishLearning)
            }
            Section("浮窗") {
                Picker("玻璃效果", selection: $panelGlassEffect) {
                    ForEach(PanelGlassEffect.allCases, id: \.self) { Text($0.title).tag($0) }
                }

                Picker("浮窗位置", selection: $panelPosition) {
                    ForEach(PanelPosition.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }
            Section {
                Toggle("显示调试页", isOn: debugSwitch)
            } header: {
                Text("调试")
            } footer: {
                Text("在设置里显示「调试」页，记录最近几次模型请求与返回。")
            }
        }
        .formStyle(.grouped)
    }

    /// Applies the pick the moment it changes, so the next launch already speaks it.
    private var languageBinding: Binding<AppLanguage> {
        Binding(
            get: { language },
            set: { AppLanguage.apply($0) })
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
