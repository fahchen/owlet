import AppKit
import SwiftUI

@main
struct OwletApp: App {
    /// Keeps a Dock click able to rebuild the main window SwiftUI releases when it is closed.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
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
            CommandGroup(replacing: .saveItem) { CloseWindowButton() }
            SidebarCommands()
        }
        // A real settings window: the scene is what puts 设置… and ⌘, in the App menu, and SwiftUI
        // manages showing it. Nothing else in the app carries a settings entry.
        Settings {
            SettingsView(promptFocus: $promptFocus)
        }
        MenuBarExtra {
            MenuContent(shortcuts: shortcuts, panel: panel, page: $page)
        } label: {
            MenuBarLabel(
                shortcuts: shortcuts, panel: panel, page: $page,
                collection: collection, history: history, promptFocus: $promptFocus)
        }
    }
}

/// Main window (design/screenshots/workspace.png): native collapsible sidebar and page detail. The
/// settings live in their own window instead, so no page here is a settings page.
private struct MainView: View {
    enum Page: Hashable { case processing, vocabulary, history, shortcuts }

    let translation: TranslationModel
    let shortcuts: ShortcutController
    @Binding var page: Page
    let collection: CollectionAction
    let history: HistoryRecorder
    @Binding var promptFocus: Operation?
    @Environment(\.openSettings) private var openSettings

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
                }
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 178, max: 260)
        } detail: {
            switch page {
            case .processing:
                TranslationView(
                    model: translation, openSettings: openModelSettings, collection: collection,
                    openNotebook: { page = .vocabulary })
            case .vocabulary:
                VocabularyView(collection: collection, openProcessing: { page = .processing })
            case .history:
                HistoryView(
                    store: HistoryStore.shared, collection: collection,
                    openProcessing: { page = .processing })
            case .shortcuts: ShortcutSettingsView(controller: shortcuts)
            }
        }
        .frame(minWidth: 760, minHeight: 500)
        .task { history.observe(translation) }
    }

    /// The processing page's service errors belong on the 模型 pane, so the pane is chosen before the
    /// window comes up.
    private func openModelSettings() {
        UserDefaults.standard.set(SettingsPane.model.rawValue, forKey: SettingsStore.settingsPaneKey)
        openSettings()
    }
}

/// Owlet is a regular app, so a Dock click with no visible window must reopen the scene SwiftUI
/// released on close, which only a SwiftUI view can do.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Reopens the main window; the always-present menu bar label sets it once its scene is live.
    var openMainWindow: (@MainActor () -> Void)?

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { openMainWindow?() }
        return true
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

    /// Reopens the window on the page it last showed.
    func reopen() {
        callAsFunction(page.wrappedValue)
    }
}

/// 关闭窗口 (⌘W): a single-window app with no documents has nothing to New/Open/Save, and SwiftUI
/// only adds the system Close to a File menu it creates for a document scene, so the command is ours.
private struct CloseWindowButton: View {
    var body: some View {
        Button("关闭窗口") { NSApp.keyWindow?.performClose(nil) }
            .keyboardShortcut("w", modifiers: .command)
    }
}

/// Runs a processing shortcut action on the panel; the menu bar extra uses it so its items stay
/// identical to the global shortcut instead of naming a second, drifting code path.
@MainActor
private struct ProcessingAction {
    let panel: PanelController

    func callAsFunction(_ action: ShortcutAction) {
        switch action {
        case .translate: panel.trigger()
        case .translateReplace: panel.trigger(replace: true)
        case .polish: panel.trigger(.polish)
        }
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
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Image("OwletMark")
            .resizable()
            .scaledToFit()
            .frame(width: 18, height: 18)
            .accessibilityLabel("Owlet")
            .onAppear {
                let perform = ProcessingAction(panel: panel)
                shortcuts.onAction = { perform($0) }
                let open = OpenMainWindow(openWindow: openWindow, page: $page)
                (NSApp.delegate as? AppDelegate)?.openMainWindow = { open.reopen() }
                panel.openSettings = { openSettings() }
                panel.openManualInput = { open(.processing) }
                panel.openNotebook = { open(.vocabulary) }
                panel.collection = collection
                history.observe(panel.model)
                // The contract error's 提示词设置 entry lands on the failing operation's editor, not on
                // the service fields it used to open.
                panel.openPromptSettings = { operation in
                    promptFocus = operation
                    openSettings()
                }
            }
    }
}

/// The menu bar extra's menu: the same processing commands the shortcuts run, plus window, settings
/// and quit, all kept as real commands so the menu never shows an unset-shortcut placeholder.
private struct MenuContent: View {
    let shortcuts: ShortcutController
    let panel: PanelController
    @Binding var page: MainView.Page
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let perform = ProcessingAction(panel: panel)
        Button("打开 Owlet") {
            NSApp.activate()
            openWindow(id: "main")
        }
        ForEach(ShortcutAction.allCases, id: \.self) { action in
            Button(title(for: action)) { perform(action) }
        }
        // The settings window manages itself, so this only has to open it; ⌘, lives in the App menu.
        Button("设置…") { openSettings() }
        Divider()
        Button("退出 Owlet") { NSApp.terminate(nil) }
    }

    /// Shows the recorded shortcut beside the action it already runs, or just the action name when
    /// unset, so the menu bar extra stays a set of commands instead of a hollow "not set" prompt.
    private func title(for action: ShortcutAction) -> String {
        guard let shortcut = shortcuts.shortcuts[action] else { return action.title }
        return "\(action.title)：\(shortcut.displayString)"
    }
}
