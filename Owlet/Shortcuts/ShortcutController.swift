import AppKit
import Carbon.HIToolbox

/// A key combination stored as a Carbon key code plus Carbon modifier flags.
struct Shortcut: Codable, Equatable, Sendable {
    var keyCode: UInt32
    var modifiers: UInt32

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Returns nil when the event carries no command/option/control modifier.
    init?(event: NSEvent) {
        let flags = event.modifierFlags
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        guard mods != 0 else { return nil }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        self.init(keyCode: UInt32(event.keyCode), modifiers: mods)
        keyLabel = event.charactersIgnoringModifiers?.uppercased()
    }

    /// Display character captured at record time.
    var keyLabel: String?

    var displayString: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + (keyLabel ?? "#\(keyCode)")
    }
}

/// Global shortcut actions; the raw value doubles as the Carbon hot key id.
enum ShortcutAction: UInt32, CaseIterable, Sendable {
    case translate = 1
    case translateReplace = 2

    var title: String {
        switch self {
        case .translate: "翻译"
        case .translateReplace: "翻译并替换"
        }
    }

    var defaultsKey: String {
        switch self {
        case .translate: SettingsStore.translateShortcutKey
        case .translateReplace: SettingsStore.translateReplaceShortcutKey
        }
    }
}

/// Registers the global shortcuts via Carbon hot keys.
@MainActor @Observable
final class ShortcutController {
    private(set) var shortcuts: [ShortcutAction: Shortcut] = [:]
    private(set) var registrationError: String?
    var onAction: (ShortcutAction) -> Void = { _ in }

    var translate: Shortcut? { shortcuts[.translate] }

    private let defaults: UserDefaults
    private var hotKeyRefs: [EventHotKeyRef] = []
    private static weak var active: ShortcutController?
    private static var handlerInstalled = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        for action in ShortcutAction.allCases {
            shortcuts[action] = SettingsStore.shortcut(forKey: action.defaultsKey, in: defaults)
        }
    }

    /// Registers the persisted shortcuts; call once at launch.
    func start() {
        Self.active = self
        installHandler()
        register()
    }

    /// Saves (or clears with nil) and re-registers. On conflict or failure nothing is saved.
    func set(_ shortcut: Shortcut?, for action: ShortcutAction) {
        if let shortcut, let other = conflict(shortcut, for: action) {
            registrationError = "该组合已用于“\(other.title)”，请换一个。"
            return
        }
        let previous = shortcuts[action]
        shortcuts[action] = shortcut
        guard register() || shortcut == nil else {
            shortcuts[action] = previous
            register()
            registrationError = "该组合已被系统或其他应用占用，请换一个。"
            return
        }
        SettingsStore.setShortcut(shortcut, forKey: action.defaultsKey, in: defaults)
    }

    func conflict(_ shortcut: Shortcut, for action: ShortcutAction) -> ShortcutAction? {
        shortcuts.first {
            $0.key != action && $0.value.keyCode == shortcut.keyCode
                && $0.value.modifiers == shortcut.modifiers
        }?.key
    }

    @discardableResult
    private func register() -> Bool {
        registrationError = nil
        hotKeyRefs.forEach { UnregisterEventHotKey($0) }
        hotKeyRefs = []
        var ok = true
        for (action, shortcut) in shortcuts {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: OSType(0x4F57_4C54), id: action.rawValue)
            let status = RegisterEventHotKey(
                shortcut.keyCode, shortcut.modifiers, id, GetApplicationEventTarget(), 0, &ref)
            guard status == noErr, let ref else {
                registrationError = "快捷键注册失败（\(status)）。"
                ok = false
                continue
            }
            hotKeyRefs.append(ref)
        }
        return ok
    }

    private func installHandler() {
        guard !Self.handlerInstalled else { return }
        Self.handlerInstalled = true
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ in
                var id = EventHotKeyID()
                GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
                guard let action = ShortcutAction(rawValue: id.id) else { return noErr }
                MainActor.assumeIsolated { ShortcutController.active?.onAction(action) }
                return noErr
            }, 1, &spec, nil, nil)
    }
}
