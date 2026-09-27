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

private struct MainView: View {
    enum Page: Hashable { case processing, shortcuts }

    let translation: TranslationModel
    let shortcuts: ShortcutController
    @Binding var page: Page?

    var body: some View {
        NavigationSplitView {
            List(selection: $page) {
                Label("文本处理", systemImage: "text.bubble").tag(Page.processing)
                Label("快捷键", systemImage: "keyboard").tag(Page.shortcuts)
            }
        } detail: {
            switch page {
            case .shortcuts: ShortcutSettingsView(controller: shortcuts)
            default: TranslationView(model: translation)
            }
        }
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
        Image(systemName: "character.bubble")
            .onAppear {
                shortcuts.onTranslate = { panel.trigger() }
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
        if let shortcut = shortcuts.translate {
            Text("翻译：\(shortcut.displayString)")
        } else {
            Button("翻译快捷键未设置，前往快捷键页…") {
                page = .shortcuts
                NSApp.activate()
                openWindow(id: "main")
            }
        }
        SettingsLink { Text("Settings…") }
        Divider()
        Button("Quit") { NSApp.terminate(nil) }
    }
}
