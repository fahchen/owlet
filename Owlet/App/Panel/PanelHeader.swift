import SwiftUI

/// Replaces the title bar the frameless panel lacks: logo, operation menu, retry, settings.
struct PanelHeader: View {
    @Binding var operation: Operation
    let retry: (() -> Void)?
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 7) {
                Image("OwletMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Owlet")
                Picker("快捷操作", selection: $operation) {
                    ForEach(Operation.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .buttonStyle(.borderless)
                .fixedSize()
                .font(.system(size: 12, weight: .semibold))
                // Switching runs the same text again at once, so the two results can be compared
                // without pressing 重新处理. `retry` is nil while a request is running or the source
                // is blank, which is exactly when switching should do nothing — and it keeps the old
                // result from being labelled with the operation that did not produce it.
                .onChange(of: operation) { _, _ in retry?() }
                .disabled(retry == nil)
            }
            Spacer(minLength: 0)
            GlassEffectContainer {
                HStack(spacing: 6) {
                    if let retry {
                        ToolButton(title: "重新处理", systemImage: "arrow.clockwise", action: retry)
                    }
                    ToolButton(title: "打开设置", systemImage: "slider.horizontal.3", action: openSettings)
                }
            }
        }
        .padding(.leading, 13)
        .padding(.trailing, 8)
        .frame(height: 42)
        .contentShape(Rectangle())
        .gesture(WindowDragGesture())
    }
}

private struct ToolButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(title, systemImage: systemImage, action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)
            .help(title)
    }
}
