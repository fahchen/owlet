import SwiftUI

@main
struct OwletApp: App {
    @State private var translation = TranslationModel(
        client: ModelClient(), config: SettingsStore.currentConfig)

    var body: some Scene {
        Window("Owlet", id: "main") {
            TranslationView(model: translation)
        }
        MenuBarExtra("Owlet", systemImage: "character.bubble") {
            MenuContent()
        }
        Settings {
            ServiceSettingsView()
        }
    }
}

private struct MenuContent: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Owlet") {
            NSApp.activate()
            openWindow(id: "main")
        }
        SettingsLink { Text("Settings…") }
        Divider()
        Button("Quit") { NSApp.terminate(nil) }
    }
}
