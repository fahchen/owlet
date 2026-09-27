import SwiftUI

@main
struct OwletApp: App {
    @State private var translation = TranslationModel(
        client: ModelClient(), config: SettingsStore.currentConfig)
    @State private var shortcuts: ShortcutController = {
        let controller = ShortcutController()
        controller.onTranslate = {
            NSApp.activate()
            NSApp.windows.first { $0.identifier?.rawValue == "main" }?.makeKeyAndOrderFront(nil)
        }
        controller.start()
        return controller
    }()

    var body: some Scene {
        Window("Owlet", id: "main") {
            MainView(translation: translation, shortcuts: shortcuts)
        }
        MenuBarExtra("Owlet", systemImage: "character.bubble") {
            MenuContent(shortcuts: shortcuts)
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
    @State private var page: Page? = .processing

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

private struct MenuContent: View {
    let shortcuts: ShortcutController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Owlet") {
            NSApp.activate()
            openWindow(id: "main")
        }
        Text("翻译：\(shortcuts.translate?.displayString ?? "未设置")")
        SettingsLink { Text("Settings…") }
        Divider()
        Button("Quit") { NSApp.terminate(nil) }
    }
}
