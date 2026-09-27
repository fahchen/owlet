import AppKit
import Carbon.HIToolbox
import SwiftUI

/// 快捷键 page body (design/screenshots/shortcuts.png): global recorders, then fixed in-app keys.
struct ShortcutSettingsView: View {
    let controller: ShortcutController
    @State private var recording: ShortcutAction?

    /// Prototype order: 翻译, 润色, 翻译并替换.
    private static let order: [ShortcutAction] = [.translate, .polish, .translateReplace]
    private static let inApp = [
        ("提交文本", "⌘ ↩", "应用内"), ("替换结果", "⌘ ↩", "浮动工具栏"), ("关闭 / 取消", "Esc", "浮动工具栏"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    GroupTitle("全局")
                    ForEach(Self.order, id: \.self) { action in
                        FormRow(title: action.title) {
                            HStack(spacing: 8) {
                                ShortcutRecorder(
                                    title: action.title, shortcut: controller.shortcuts[action],
                                    recording: bindingFor(action)
                                ) { controller.set($0, for: action) }
                                Button("清除") {
                                    recording = nil
                                    controller.set(nil, for: action)
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 10))
                                .foregroundStyle(RoseGlass.muted)
                                .padding(5)
                                .contentShape(Rectangle())
                                .accessibilityLabel("清除\(action.title)快捷键")
                            }
                        }
                    }
                    notice
                        .padding(.bottom, 18)
                    GroupTitle("应用内")
                    ForEach(Self.inApp, id: \.0) { name, keys, scope in
                        FormRow(title: name, detail: scope) { KbdChip(keys: keys) }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 28)
            }
            .scrollBounceBehavior(.basedOnSize)
            PageFooter {
                Text("录制后立即生效")
            } trailing: {
                EmptyView()
            }
        }
        .foregroundStyle(RoseGlass.ink)
        .tint(RoseGlass.accent)
    }

    @ViewBuilder private var notice: some View {
        Group {
            if let error = controller.registrationError {
                Text(error).foregroundStyle(RoseGlass.errorText)
            } else if recording != nil {
                Text("按新组合键；Esc 取消，Delete 清除。").foregroundStyle(RoseGlass.muted)
            } else {
                Text(" ").accessibilityHidden(true)
            }
        }
        .font(.system(size: 11))
        .lineSpacing(4)
        .frame(minHeight: 20, alignment: .top)
        .padding(.top, 11)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private func bindingFor(_ action: ShortcutAction) -> Binding<Bool> {
        Binding(
            get: { recording == action },
            set: { recording = $0 ? action : (recording == action ? nil : recording) })
    }
}

private struct ShortcutRecorder: View {
    let title: String
    let shortcut: Shortcut?
    @Binding var recording: Bool
    let onChange: (Shortcut?) -> Void
    @State private var monitor: Any?

    var body: some View {
        Button {
            recording ? stop() : start()
        } label: {
            Text(recording ? "请按快捷键…" : shortcut?.displayString ?? "未设置")
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(recording ? RoseGlass.accent : RoseGlass.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .frame(minWidth: 91, minHeight: 32)
                .background(
                    recording ? RoseGlass.tint : RoseGlass.paper,
                    in: .rect(cornerRadius: 8, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(recording ? RoseGlass.accent : RoseGlass.line)
                }
                .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("录制\(title)快捷键")
        .accessibilityValue(shortcut?.displayString ?? "未设置")
        .onChange(of: recording) { _, now in if !now { removeMonitor() } }
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        removeMonitor()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch Int(event.keyCode) {
            case kVK_Escape:
                stop()
            case kVK_Delete, kVK_ForwardDelete:
                onChange(nil)
                stop()
            default:
                guard let new = Shortcut(event: event) else { return nil }
                onChange(new)
                stop()
            }
            return nil
        }
    }

    private func stop() {
        recording = false
        removeMonitor()
    }

    private func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
