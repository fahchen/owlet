import AppKit
import Carbon.HIToolbox
import SwiftUI

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

    /// The same combination as a menu key equivalent, so a menu prints it in its own right-aligned
    /// column; nil when the recorded key is not a single character a menu can show.
    var menuShortcut: KeyboardShortcut? {
        guard let label = keyLabel, label.count == 1, let character = label.lowercased().first else { return nil }
        var flags: SwiftUI.EventModifiers = []
        if modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        return KeyboardShortcut(KeyEquivalent(character), modifiers: flags)
    }
}

/// Global shortcut actions; the raw value doubles as the Carbon hot key id.
enum ShortcutAction: UInt32, CaseIterable, Sendable {
    case translate = 1
    case translateReplace = 2
    case polish = 3
    case polishReplace = 4
    case translateRegion = 5

    var title: LocalizedStringResource {
        switch self {
        case .translate: "Translate"
        case .translateReplace: "Translate and Replace"
        case .polish: "Polish"
        case .polishReplace: "Polish and Replace"
        case .translateRegion: "Translate Screen Region"
        }
    }

    /// The action's name in the chosen language, resolved when it is shown.
    var name: String { L10n.shared.string(title.key) }

    var defaultsKey: String {
        switch self {
        case .translate: SettingsStore.translateShortcutKey
        case .translateReplace: SettingsStore.translateReplaceShortcutKey
        case .polish: SettingsStore.polishShortcutKey
        case .polishReplace: SettingsStore.polishReplaceShortcutKey
        case .translateRegion: SettingsStore.translateRegionShortcutKey
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
            registrationError = L10n.shared.string(
                "That combination is already used for “%@”; choose another.", other.name)
            return
        }
        let previous = shortcuts[action]
        shortcuts[action] = shortcut
        guard register() || shortcut == nil else {
            shortcuts[action] = previous
            register()
            registrationError = L10n.shared.string(
                "The system or another app already uses that combination; choose another.")
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
                registrationError = L10n.shared.string("Registering the shortcut failed (%lld).", status)
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
