import AppKit
import Carbon.HIToolbox
import SwiftUI

struct ShortcutSettingsView: View {
    let controller: ShortcutController

    var body: some View {
        Form {
            ForEach(ShortcutAction.allCases, id: \.self) { action in
                LabeledContent(action.title) {
                    ShortcutRecorder(shortcut: controller.shortcuts[action]) {
                        controller.set($0, for: action)
                    }
                }
            }
            if let error = controller.registrationError {
                Text(error).foregroundStyle(.red)
            }
            Text("点击组合开始录制；Esc 取消，Delete 清除。")
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

private struct ShortcutRecorder: View {
    let shortcut: Shortcut?
    let onChange: (Shortcut?) -> Void
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(recording ? "请按下组合…" : shortcut?.displayString ?? "未设置") {
            recording ? stop() : start()
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
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
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
