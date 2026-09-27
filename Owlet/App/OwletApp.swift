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
    @State private var collection = CollectionAction()
    @State private var history = HistoryRecorder()
    @State private var panel = PanelController(
        model: TranslationModel(client: ModelClient(), config: SettingsStore.currentConfig))
    @State private var page: MainView.Page = .processing
    /// One-shot focus request for the prompt editor the panel's format error points at.
    @State private var promptFocus: Operation?

    var body: some Scene {
        Window("Owlet", id: "main") {
            MainView(
                translation: translation, shortcuts: shortcuts, page: $page,
                collection: collection, history: history, promptFocus: $promptFocus
            )
            .modelContainer(collection.store.container)
        }
        .defaultSize(width: 1080, height: 690)
        .commands {
            CommandGroup(replacing: .appSettings) { SettingsButton(page: $page) }
        }
        MenuBarExtra {
            MenuContent(shortcuts: shortcuts, page: $page)
        } label: {
            MenuBarLabel(
                shortcuts: shortcuts, panel: panel, page: $page,
                collection: collection, history: history, promptFocus: $promptFocus)
        }
    }
}

/// Main window (design/screenshots/workspace.png): native collapsible sidebar and page
/// detail; settings is a sidebar page, not a separate window.
private struct MainView: View {
    enum Page: Hashable { case processing, vocabulary, history, shortcuts, settings }

    let translation: TranslationModel
    let shortcuts: ShortcutController
    @Binding var page: Page
    let collection: CollectionAction
    let history: HistoryRecorder
    @Binding var promptFocus: Operation?

    var body: some View {
        NavigationSplitView {
            // A sidebar List allows an empty selection; ignore it so a row stays highlighted.
            List(selection: Binding<Page?>(get: { page }, set: { if let new = $0 { page = new } })) {
                Section("随手处理") {
                    Label("文本处理", systemImage: "translate").tag(Page.processing)
                }
                Section("我的积累") {
                    Label("生词本", systemImage: "book").tag(Page.vocabulary)
                    Label("历史记录", systemImage: "clock").tag(Page.history)
                }
                Section {
                    Label("快捷键", systemImage: "keyboard").tag(Page.shortcuts)
                    Label("设置", systemImage: "gearshape").tag(Page.settings)
                }
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 178, max: 260)
        } detail: {
            switch page {
            case .processing:
                TranslationView(
                    model: translation, openSettings: { page = .settings }, collection: collection,
                    openNotebook: { page = .vocabulary })
            case .vocabulary:
                VocabularyView(collection: collection, openProcessing: { page = .processing })
            case .history:
                HistoryView(store: HistoryStore.shared, openProcessing: { page = .processing })
            case .shortcuts: ShortcutSettingsView(controller: shortcuts)
            case .settings: ServiceSettingsView(promptFocus: $promptFocus)
            }
        }
        .frame(minWidth: 760, minHeight: 500)
        .task { history.observe(translation) }
    }
}

/// Opens the main window on a page; also recreates the window if it was closed.
@MainActor private struct OpenMainWindow {
    let openWindow: OpenWindowAction
    let page: Binding<MainView.Page>

    func callAsFunction(_ target: MainView.Page) {
        page.wrappedValue = target
        NSApp.activate()
        openWindow(id: "main")
    }
}

/// 设置… (⌘,) in the app menu and the menu bar menu.
private struct SettingsButton: View {
    @Binding var page: MainView.Page
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("设置…") {
            OpenMainWindow(openWindow: openWindow, page: $page)(.settings)
        }
        .keyboardShortcut(",", modifiers: .command)
    }
}

/// The menu bar label is always rendered, so it wires the shortcut and the panel's
/// recovery entries to scene actions that also recreate closed windows.
private struct MenuBarLabel: View {
    let shortcuts: ShortcutController
    let panel: PanelController
    @Binding var page: MainView.Page
    let collection: CollectionAction
    let history: HistoryRecorder
    @Binding var promptFocus: Operation?
    @Environment(\.openWindow) private var openWindow

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
                let open = OpenMainWindow(openWindow: openWindow, page: $page)
                panel.openSettings = { open(.settings) }
                panel.openManualInput = { open(.processing) }
                panel.openNotebook = { open(.vocabulary) }
                panel.collection = collection
                history.observe(panel.model)
                // The format error's 提示词设置 entry lands on the failing operation's editor, not on
                // the service fields it used to open.
                panel.openPromptSettings = { operation in
                    promptFocus = operation
                    open(.settings)
                }
            }
    }
}

private struct MenuContent: View {
    let shortcuts: ShortcutController
    @Binding var page: MainView.Page
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let open = OpenMainWindow(openWindow: openWindow, page: $page)
        Button("打开 Owlet") {
            NSApp.activate()
            openWindow(id: "main")
        }
        ForEach(ShortcutAction.allCases, id: \.self) { action in
            if let shortcut = shortcuts.shortcuts[action] {
                Text("\(action.title)：\(shortcut.displayString)")
            } else {
                Button("\(action.title)快捷键未设置，前往快捷键页…") { open(.shortcuts) }
            }
        }
        SettingsButton(page: $page)
        Divider()
        Button("退出 Owlet") { NSApp.terminate(nil) }
    }
}
