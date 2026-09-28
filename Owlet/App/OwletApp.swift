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
            ProcessingMenu(panel: panel)
            TextProcessingMenu(translation: translation, page: $page)
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

/// Runs a processing shortcut action on the panel; shared by the 处理 menu and the menu bar extra so
/// both stay identical to the global shortcut instead of naming a second, drifting code path.
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

/// The 文本处理 menu's two decisions, kept apart from the menu so a test can reach them: SwiftUI
/// menu wiring is not unit-testable, and the rest of each item is a direct call into the model.
enum TextProcessingCommands {
    /// The submit item reads like the footer button: the current operation names it.
    static func submitTitle(for operation: Operation) -> String { "\(operation.title)文本" }

    /// Copy is offered only with a result, exactly as the footer's copy button is.
    static func canCopy(_ state: TranslationModel.State) -> Bool {
        if case .success = state { return true }
        return false
    }
}

/// The window's own controls as commands: the toolbar carries the target language and the operation
/// and the footer the submit and copy, so each of them is named once here with the same shortcut the
/// button shows. The submit's ⌘↩ and the copy's ⌘⇧C live on these items rather than on the buttons,
/// so a shortcut has one owner; the panel keeps its own keys through its key monitor.
private struct TextProcessingMenu: Commands {
    let translation: TranslationModel
    @Binding var page: MainView.Page

    var body: some Commands {
        // The menu mirrors the toolbar control: 自动 resolves from the mapping, an explicit language
        // pins the target. The stored value is shared with the window and the panel.
        let language = Binding(
            get: { UserDefaults.standard.string(forKey: SettingsStore.pinnedTargetKey) ?? "" },
            set: { SettingsStore.setPinnedTarget($0.isEmpty ? nil : $0) })
        CommandMenu("文本处理") {
            TargetLanguagePicker(text: translation.input, pinnedTarget: language)
                .disabled(translation.operation != .translate)
            Picker("处理方式", selection: Binding(get: { translation.operation }, set: { translation.operation = $0 })) {
                ForEach(Operation.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Divider()
            Button(TextProcessingCommands.submitTitle(for: translation.operation)) { submit() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(translation.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("复制结果") { copyResult() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(!TextProcessingCommands.canCopy(translation.state))
        }
    }

    /// The same rule the footer button follows: the current operation, at the target this text
    /// resolves to — a pinned language, else the mapping, else the fallback.
    private func submit() {
        page = .processing
        translation.translate(to: SettingsStore.resolvedTarget(for: translation.input))
    }

    private func copyResult() {
        guard let result else { return }
        Clipboard.copy(result)
    }

    private var result: String? {
        if case .success(let text) = translation.state { return text }
        return nil
    }
}

/// 处理 menu exposes the same selection operations the global shortcuts already run, named once so
/// the menu bar teaches what the app can do without inventing an action that has no code path.
private struct ProcessingMenu: Commands {
    let panel: PanelController

    var body: some Commands {
        let perform = ProcessingAction(panel: panel)
        CommandMenu("处理") {
            Button("翻译") { perform(.translate) }
            Button("翻译并替换") { perform(.translateReplace) }
            Button("润色") { perform(.polish) }
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
