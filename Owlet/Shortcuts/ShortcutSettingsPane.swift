import AppKit
import Carbon.HIToolbox
import SwiftUI

/// 快捷键 pane of the settings window: the global recorders, then the panel's fixed keys. Keyboard
/// bindings are a preference, so they belong with the other preferences rather than in the sidebar.
struct ShortcutSettingsPane: View {
    let controller: ShortcutController
    @State private var recording: ShortcutAction?

    /// Each operation, then the same operation written straight back.
    private static let order: [ShortcutAction] = [.translate, .polish, .translateReplace, .polishReplace]

    var body: some View {
        Form {
            Section {
                ForEach(Self.order, id: \.self) { action in
                    LabeledContent(L10n.shared.string(action.title.key)) {
                        HStack(spacing: 4) {
                            ShortcutRecorder(
                                title: L10n.shared.string(action.title.key), shortcut: controller.shortcuts[action],
                                recording: bindingFor(action)
                            ) { controller.set($0, for: action) }
                            // Only a set shortcut has something to clear.
                            if controller.shortcuts[action] != nil {
                                Button("Clear", systemImage: "xmark.circle.fill") {
                                    recording = nil
                                    controller.set(nil, for: action)
                                }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.borderless)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel(L10n.shared.string("Clear the \(action.title) shortcut"))
                            }
                        }
                    }
                }
            } header: {
                Text(L10n.shared.string("Global"))
            } footer: {
                notice
            }
            ForEach(KeyHint.groups, id: \.title) { group in
                fixedKeys(L10n.shared.string("\(group.title)"), group.keys)
            }
        }
        .formStyle(.grouped)
    }

    /// The keys the app claims itself, three to a row: listed to be learned, not recorded.
    private func fixedKeys(_ title: String, _ keys: [KeyHint]) -> some View {
        Section {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 24, alignment: .leading), count: 3),
                alignment: .leading, spacing: 10
            ) {
                ForEach(keys, id: \.title) { key in
                    HStack(spacing: 8) {
                        Text(LocalizedStringKey(key.title)).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(key.keys).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.vertical, 2)
        } header: {
            Text(title)
        } footer: {
            if title == KeyHint.groups.last?.title {
                Text(
                    L10n.shared.string("Fixed keys that cannot be changed; ⌘C copies the selection when there is one.")
                ).foregroundStyle(
                    .secondary)
            }
        }
    }

    @ViewBuilder private var notice: some View {
        Group {
            if let error = controller.registrationError {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
            } else if recording != nil {
                Text(L10n.shared.string("Press the new combination; Esc cancels, Delete clears.")).foregroundStyle(
                    .secondary)
            } else {
                Text(L10n.shared.string("Click the combination on the right to record it again.")).foregroundStyle(
                    .secondary)
            }
        }
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
        // A value, not a bezel: it reads like the form's other values, and only recording is marked.
        Button {
            if recording { stop() } else { start() }
        } label: {
            label
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.shared.string("Record the \(title) shortcut"))
        .accessibilityValue(shortcut?.displayString ?? "Not set")
        .onChange(of: recording) { _, now in if !now { removeMonitor() } }
        .onDisappear(perform: stop)
    }

    private var label: some View {
        Text(recording ? "Press the shortcut…" : shortcut?.displayString ?? "Record")
            .monospacedDigit()
            .foregroundStyle(recording || shortcut == nil ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.accentColor.opacity(recording ? 0.12 : 0), in: Capsule())
            .contentShape(Capsule())
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
