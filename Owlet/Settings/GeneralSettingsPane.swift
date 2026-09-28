import SwiftUI

/// 通用 pane: the preferences that are neither about languages nor about the model.
struct GeneralSettingsPane: View {
    @AppStorage(SettingsStore.translateLearningKey) private var translateLearning = false
    @AppStorage(SettingsStore.polishLearningKey) private var polishLearning = false
    @AppStorage(SettingsStore.displayModeKey) private var displayMode =
        TranslationDisplayMode.sectioned
    @AppStorage(SettingsStore.panelPositionKey) private var panelPosition = PanelPosition.fixed
    @AppStorage(SettingsStore.debugEnabledKey) private var debugEnabled = false

    var body: some View {
        Form {
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
                Picker("浮窗位置", selection: $panelPosition) {
                    ForEach(PanelPosition.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }
            Section {
                Toggle("显示调试页", isOn: $debugEnabled)
            } header: {
                Text("调试")
            } footer: {
                Text("在设置里显示「调试」页，记录最近几次模型请求与返回。")
            }
        }
        .formStyle(.grouped)
    }
}
