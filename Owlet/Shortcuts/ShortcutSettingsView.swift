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
        Form {
            Section {
                ForEach(Self.order, id: \.self) { action in
                    LabeledContent(action.title) {
                        GlassEffectContainer {
                            HStack(spacing: 8) {
                                ShortcutRecorder(
                                    title: action.title, shortcut: controller.shortcuts[action],
                                    recording: bindingFor(action)
                                ) { controller.set($0, for: action) }
                                Button("清除") {
                                    recording = nil
                                    controller.set(nil, for: action)
                                }
                                .buttonStyle(.glass)
                                .accessibilityLabel("清除\(action.title)快捷键")
                            }
                        }
                    }
                }
            } header: {
                Text("全局")
            } footer: {
                notice
            }
            Section {
                ForEach(Self.inApp, id: \.0) { name, keys, scope in
                    LabeledContent {
                        Text(keys).monospacedDigit()
                    } label: {
                        Text(name)
                        Text(scope)
                    }
                }
            } header: {
                Text("应用内")
            } footer: {
                Text("录制后立即生效").foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("快捷键")
    }

    @ViewBuilder private var notice: some View {
        Group {
            if let error = controller.registrationError {
                Label(error, systemImage: "exclamationmark.triangle")
            } else if recording != nil {
                Text("按新组合键；Esc 取消，Delete 清除。")
            } else {
                Text(" ").accessibilityHidden(true)
            }
        }
        .foregroundStyle(.secondary)
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
        Group {
            if recording {
                Button(action: stop) { label }.buttonStyle(.glassProminent)
            } else {
                Button(action: start) { label }.buttonStyle(.glass)
            }
        }
        .accessibilityLabel("录制\(title)快捷键")
        .accessibilityValue(shortcut?.displayString ?? "未设置")
        .onChange(of: recording) { _, now in if !now { removeMonitor() } }
        .onDisappear(perform: stop)
    }

    private var label: some View {
        Text(recording ? "请按快捷键…" : shortcut?.displayString ?? "未设置")
            .monospacedDigit()
            .frame(minWidth: 70)
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
