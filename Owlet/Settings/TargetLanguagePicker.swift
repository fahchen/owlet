import SwiftUI

/// The target-language control shared by the window toolbar, the floating panel and the 文本处理
/// menu: 自动 resolves from the mapping for the current text, and an explicit choice pins that
/// language until the user returns to 自动. All three read the same stored value, so they stay in step.
struct TargetLanguagePicker: View {
    /// The text the 自动 label resolves from.
    let text: String
    @Binding var pinnedTarget: String

    var body: some View {
        Picker("目标语言", selection: $pinnedTarget) {
            Text(autoTitle).tag("")
            ForEach(LanguageCatalog.targets) { Text($0.name).tag($0.tag) }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
    }

    private var autoTitle: String {
        "自动（\(LanguageCatalog.name(for: SettingsStore.autoTarget(for: text)))）"
    }
}
