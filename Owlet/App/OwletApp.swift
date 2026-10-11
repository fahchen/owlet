import AppKit
import SwiftUI

@main
struct OwletApp: App {
    /// Keeps a Dock click able to rebuild the main window SwiftUI releases when it is closed.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var translation = TextProcessingModel(
        client: ModelClient(), config: SettingsStore.currentConfig)
    @State private var shortcuts: ShortcutController = {
        let controller = ShortcutController()
        controller.start()
        return controller
    }()
    @State private var collection = CollectionAction()
    @State private var history = HistoryRecorder()
    /// One launch's lookups, shared by the panel and the main window so either reuses the other's.
    private static let lookupStore = LookupStore()
    @State private var panel = PanelController(
        model: TextProcessingModel(client: ModelClient(), config: SettingsStore.currentConfig),
        lookups: LookupPresenter(store: lookupStore))
    @State private var mainLookups = LookupPresenter(store: lookupStore)
    @State private var page: MainView.Page = .processing
    /// One-shot focus request for the prompt editor the panel's format error points at.
    @State private var promptFocus: Operation?

    var body: some Scene {
        Window("Owlet", id: "main") {
            MainView(
                translation: translation, page: $page,
                collection: collection, history: history, promptFocus: $promptFocus
            )
            .modelContainer(collection.store.container)
            .environment(\.lookups, mainLookups)
            .background { EndEditingOnBackgroundClick().frame(width: 0, height: 0) }
        }
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1080, height: 690)
        .commands {
            CommandGroup(replacing: .saveItem) { CloseWindowButton() }
            // A toolbar item is not the only place a command may live: the toolbar can be hidden or
            // customized away, so the page's two actions are menu commands as well, and the menu items
            // are what own the shortcuts.
            CommandGroup(after: .newItem) {
                SubmitTextButton(translation: translation)
                OperationButtons(translation: translation, page: $page)
            }
            CommandGroup(replacing: .pasteboard) { PasteboardButtons() }
            SidebarCommands()
        }
        // A real settings window: the scene is what puts 设置… and ⌘, in the App menu, and SwiftUI
        // manages showing it. Nothing else in the app carries a settings entry.
        Settings {
            SettingsView(shortcuts: shortcuts, promptFocus: $promptFocus)
                .background { EndEditingOnBackgroundClick().frame(width: 0, height: 0) }
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
    enum Page: Hashable { case processing, vocabulary, history }

    let translation: TextProcessingModel
    @Binding var page: Page
    let collection: CollectionAction
    let history: HistoryRecorder
    @Binding var promptFocus: Operation?
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        NavigationSplitView {
            // A sidebar List allows an empty selection; ignore it so a row stays highlighted.
            List(selection: Binding<Page?>(get: { page }, set: { if let new = $0 { page = new } })) {
                // The main page needs no group title: it is what the app is for.
                Label("翻译与润色", systemImage: "translate").tag(Page.processing)
                Section("我的积累") {
                    Label("生词本", systemImage: "books.vertical").tag(Page.vocabulary)
                    Label("历史记录", systemImage: "clock").tag(Page.history)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 160, ideal: 178, max: 260)
        } detail: {
            switch page {
            case .processing:
                TextProcessingView(
                    model: translation, openSettings: openModelSettings, collection: collection)
            case .vocabulary:
                VocabularyView(collection: collection, openProcessing: { page = .processing })
            case .history:
                HistoryView(
                    store: HistoryStore.shared, collection: collection,
                    openProcessing: { page = .processing })
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

/// 翻译文本／润色文本 (⌘↩) in the File menu: the main page's submit action, named for the operation
/// the page is on.
private struct SubmitTextButton: View {
    let translation: TextProcessingModel

    var body: some View {
        Button("\(translation.operation.title)文本") {
            translation.process(to: SettingsStore.resolvedTarget(for: translation.input))
        }
        .keyboardShortcut(.return, modifiers: .command)
        .disabled(translation.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}

/// 翻译 (⌘1) and 润色 (⌘2): switch the main page's operation, bringing the page up if another is showing.
private struct OperationButtons: View {
    let translation: TextProcessingModel
    @Binding var page: MainView.Page

    var body: some View {
        ForEach([(Operation.translate, KeyHint.translateMode), (.polish, .polishMode)], id: \.0) { operation, key in
            Button("\(operation.title)模式") {
                page = .processing
                translation.operation = operation
            }
            .keyboardShortcut(key.shortcut)
            .disabled(translation.state == .loading)
        }
    }
}

/// The Edit menu's pasteboard commands. 拷贝 (⌘C) copies selected text as always; with nothing
/// selected it copies what the page offers — the result, a record's result, an expression — so the
/// one key does both, and the page's copy button only has to name it.
private struct PasteboardButtons: View {
    @FocusedValue(\.copyText) private var copyText

    var body: some View {
        Button("剪切") { NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil) }
            .keyboardShortcut("x")
        Button("拷贝") {
            if hasTextSelection {
                NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
            } else if let copyText {
                Clipboard.copy(copyText)
            }
        }
        .keyboardShortcut(KeyHint.copy.shortcut)
        Button("粘贴") { NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil) }
            .keyboardShortcut("v")
        Button("全选") { NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil) }
            .keyboardShortcut("a")
    }

    // ponytail: only an AppKit text view's selection counts; a selection in SwiftUI selectable Text
    // (逐句对照) is not seen, so ⌘C there copies the whole result. Route through the responder chain's
    // validation if that matters.
    private var hasTextSelection: Bool {
        (NSApp.keyWindow?.firstResponder as? NSTextView).map { $0.selectedRange().length > 0 } ?? false
    }
}

/// Runs a processing shortcut action on the panel; the menu bar extra uses it so its items stay
/// identical to the global shortcut instead of naming a second, drifting code path.
@MainActor
private struct ProcessingAction {
    let panel: PanelController

    func callAsFunction(_ action: ShortcutAction) {
        switch action {
        case .translate: panel.processSelection()
        case .translateReplace: panel.processSelection(replace: true)
        case .polish: panel.processSelection(.polish)
        case .polishReplace: panel.processSelection(.polish, replace: true)
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
        // The recorded combination is the item's key equivalent, so the menu right-aligns it in its
        // own column; the hot key still does the work, the menu only shows it.
        ForEach(ShortcutAction.allCases, id: \.self) { action in
            Button(title(for: action)) { perform(action) }
                .keyboardShortcut(shortcuts.shortcuts[action]?.menuShortcut)
        }
        // The settings window manages itself, so this only has to open it; ⌘, lives in the App menu.
        Button("设置…") { openSettings() }
        Divider()
        Button("退出 Owlet") { NSApp.terminate(nil) }
    }

    /// The action's name; a combination the menu cannot show as a key equivalent is written after it,
    /// and an unset one adds nothing, so the menu never shows a hollow "not set" prompt.
    private func title(for action: ShortcutAction) -> String {
        guard let shortcut = shortcuts.shortcuts[action], shortcut.menuShortcut == nil else { return action.title }
        return "\(action.title)：\(shortcut.displayString)"
    }
}
