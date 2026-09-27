import SwiftUI

@main
struct OwletApp: App {
    @State private var translation = TranslationModel(
        client: ModelClient(), config: SettingsStore.currentConfig)
    @State private var shortcuts: ShortcutController = {
        let controller = ShortcutController()
        controller.start()
        return controller
    }()
    @State private var panel = PanelController(
        model: TranslationModel(client: ModelClient(), config: SettingsStore.currentConfig))
    @State private var page: MainView.Page? = .processing

    var body: some Scene {
        Window("Owlet", id: "main") {
            MainView(translation: translation, shortcuts: shortcuts, page: $page)
        }
        .windowStyle(.hiddenTitleBar)
        .windowBackgroundDragBehavior(.enabled)
        .defaultSize(width: 1080, height: 690)
        MenuBarExtra {
            MenuContent(shortcuts: shortcuts, page: $page)
        } label: {
            MenuBarLabel(shortcuts: shortcuts, panel: panel, page: $page)
        }
        Settings {
            ServiceSettingsView()
        }
    }
}

/// Main window (design/screenshots/workspace.png): custom sidebar under the native
/// traffic lights and a page area with its own title bar, so the system title bar is hidden.
private struct MainView: View {
    enum Page: Hashable { case processing, shortcuts }

    let translation: TranslationModel
    let shortcuts: ShortcutController
    @Binding var page: Page?

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(page: $page)
            RoseGlass.line.frame(width: 1)
            Group {
                switch page {
                case .shortcuts:
                    VStack(spacing: 0) {
                        PageHeader(title: "快捷键")
                        ShortcutSettingsView(controller: shortcuts)
                    }
                default: TranslationView(model: translation)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoseGlass.paper.opacity(0.7))
        }
        .background(RoseGlass.window)
        .ignoresSafeArea(.container, edges: .top)
        .frame(minWidth: 760, minHeight: 500)
    }
}

private struct Sidebar: View {
    @Binding var page: MainView.Page?
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Room for the native traffic lights.
            Color.clear.frame(height: 42)
            SectionLabel("随手处理")
            NavRow("文本处理", systemImage: "translate", selected: page != .shortcuts) {
                page = .processing
            }
            .padding(.bottom, 18)
            NavRow("快捷键", systemImage: "slider.horizontal.3", selected: page == .shortcuts) {
                page = .shortcuts
            }
            Spacer()
            NavRow("设置", systemImage: "slider.horizontal.3", selected: false) {
                openSettings()
            }
            HStack(spacing: 6) {
                Circle().fill(RoseGlass.green).frame(width: 5, height: 5)
                Text("本地")
            }
            .font(.system(size: 10))
            .foregroundStyle(RoseGlass.muted)
            .padding(.horizontal, 12)
            .padding(.top, 15)
            .help("数据保存在此设备")
        }
        .padding(.horizontal, 12)
        .padding(.top, 20)
        .padding(.bottom, 14)
        .frame(width: 178)
        .frame(maxHeight: .infinity)
        .background(RoseGlass.sidebar)
    }
}

private struct SectionLabel: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.system(size: 10))
            .tracking(1.2)
            .foregroundStyle(RoseGlass.muted)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct NavRow: View {
    let title: String
    let systemImage: String
    let selected: Bool
    let action: () -> Void

    init(
        _ title: String, systemImage: String, selected: Bool, action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.selected = selected
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: selected ? .semibold : .regular))
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                Spacer(minLength: 0)
            }
            .foregroundStyle(selected ? RoseGlass.accent : RoseGlass.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(RoseGlass.selectedNav)
                        .shadow(color: RoseGlass.ink.opacity(0.07), radius: 2, y: 1)
                }
            }
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The menu bar label is always rendered, so it wires the shortcut and the panel's
/// recovery entries to scene actions that also recreate closed windows.
private struct MenuBarLabel: View {
    let shortcuts: ShortcutController
    let panel: PanelController
    @Binding var page: MainView.Page?
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Image("OwletMark")
            .resizable()
            .scaledToFit()
            .frame(width: 18, height: 18)
            .accessibilityLabel("Owlet")
            .onAppear {
                shortcuts.onAction = { action in
                    switch action {
                    case .translate: panel.trigger()
                    case .translateReplace: panel.trigger(replace: true)
                    case .polish: panel.trigger(.polish)
                    }
                }
                panel.openSettings = {
                    NSApp.activate()
                    openSettings()
                }
                panel.openManualInput = {
                    page = .processing
                    NSApp.activate()
                    openWindow(id: "main")
                }
            }
    }
}

private struct MenuContent: View {
    let shortcuts: ShortcutController
    @Binding var page: MainView.Page?
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Owlet") {
            NSApp.activate()
            openWindow(id: "main")
        }
        ForEach(ShortcutAction.allCases, id: \.self) { action in
            if let shortcut = shortcuts.shortcuts[action] {
                Text("\(action.title)：\(shortcut.displayString)")
            } else {
                Button("\(action.title)快捷键未设置，前往快捷键页…") {
                    page = .shortcuts
                    NSApp.activate()
                    openWindow(id: "main")
                }
            }
        }
        SettingsLink { Text("Settings…") }
        Divider()
        Button("Quit") { NSApp.terminate(nil) }
    }
}
