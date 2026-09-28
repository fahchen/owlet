import SwiftUI

/// 通用 pane: the preferences that are neither about languages nor about the model.
struct GeneralSettingsPane: View {
    @AppStorage(SettingsStore.translateLearningKey) private var translateLearning = false
    @AppStorage(SettingsStore.polishLearningKey) private var polishLearning = false
    @AppStorage(SettingsStore.panelPositionKey) private var panelPosition = PanelPosition.fixed
    @AppStorage(SettingsStore.debugEnabledKey) private var debugEnabled = false

    var body: some View {
        Form {
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
                Text("在设置里多出一个「调试」页：保留最近若干次模型请求与返回（含原文），只存在内存里，重启即清空。文本会发送到配置的模型服务，请自行斟酌。")
            }
        }
        .formStyle(.grouped)
    }
}
