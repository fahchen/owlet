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

/// Registers the translation global shortcut via Carbon hot keys.
@MainActor @Observable
final class ShortcutController {
    private(set) var translate: Shortcut?
    private(set) var registrationError: String?
    var onTranslate: () -> Void = {}

    private let defaults: UserDefaults
    private var hotKeyRef: EventHotKeyRef?
    private static weak var active: ShortcutController?
    private static var handlerInstalled = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        translate = SettingsStore.shortcut(forKey: SettingsStore.translateShortcutKey, in: defaults)
    }

    /// Registers the persisted shortcut; call once at launch.
    func start() {
        Self.active = self
        installHandler()
        register()
    }

    /// Saves (or clears with nil) and re-registers. On failure the shortcut is not saved.
    func setTranslate(_ shortcut: Shortcut?) {
        let previous = translate
        translate = shortcut
        guard register() || shortcut == nil else {
            translate = previous
            register()
            registrationError = "该组合已被系统或其他应用占用，请换一个。"
            return
        }
        SettingsStore.setShortcut(shortcut, forKey: SettingsStore.translateShortcutKey, in: defaults)
    }

    @discardableResult
    private func register() -> Bool {
        registrationError = nil
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        guard let translate else { return true }
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x4F57_4C54), id: 1)
        let status = RegisterEventHotKey(
            translate.keyCode, translate.modifiers, id, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            registrationError = "快捷键注册失败（\(status)）。"
            return false
        }
        hotKeyRef = ref
        return true
    }

    private func installHandler() {
        guard !Self.handlerInstalled else { return }
        Self.handlerInstalled = true
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, _ in
                MainActor.assumeIsolated { ShortcutController.active?.onTranslate() }
                return noErr
            }, 1, &spec, nil, nil)
    }
}
