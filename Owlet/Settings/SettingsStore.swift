import Foundation
import Security

enum Provider: String, CaseIterable, Sendable {
    case openAICompatible, deepSeek

    var title: String {
        switch self {
        case .openAICompatible: "OpenAI Compatible"
        case .deepSeek: "DeepSeek"
        }
    }

    /// Base URL and default model filled in on selection; nil keeps free-form values.
    var preset: (baseURL: String, model: String)? {
        switch self {
        case .openAICompatible: nil
        case .deepSeek: ("https://api.deepseek.com", "deepseek-chat")
        }
    }

    /// DeepSeek rejects `json_schema` and only accepts `json_object`.
    var supportsJSONSchema: Bool { self != .deepSeek }

    /// OpenAI compatible keeps the pre-provider "default" account so existing keys still resolve.
    var keychainAccount: String { self == .openAICompatible ? "default" : rawValue }
}

struct ServiceConfig: Sendable, Equatable {
    var baseURL: URL
    var model: String
    var apiKey: String
    var provider: Provider = .openAICompatible
}

enum SettingsStore {
    static let providerKey = "service.provider"
    static let baseURLKey = "service.baseURL"
    static let modelKey = "service.model"
    static let targetLanguageKey = "translation.targetLanguage"
    static let defaultTargetLanguage = "zh-Hans"
    private static let keychainService = "dev.fahchen.owlet.apiKey"

    /// Returns nil when any required setting is missing.
    static func currentConfig() -> ServiceConfig? {
        let defaults = UserDefaults.standard
        let provider = defaults.string(forKey: providerKey).flatMap(Provider.init) ?? .openAICompatible
        guard
            let base = defaults.string(forKey: baseURLKey)?.trimmingCharacters(in: .whitespaces),
            let url = URL(string: base), url.scheme != nil,
            let model = defaults.string(forKey: modelKey)?.trimmingCharacters(in: .whitespaces),
            !model.isEmpty,
            let key = apiKey(for: provider), !key.isEmpty
        else { return nil }
        return ServiceConfig(baseURL: url, model: model, apiKey: key, provider: provider)
    }

    static func apiKey(for provider: Provider) -> String? {
        var query = baseQuery(provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
            let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func setAPIKey(_ key: String, for provider: Provider) -> Bool {
        SecItemDelete(baseQuery(provider) as CFDictionary)
        guard !key.isEmpty else { return true }
        var query = baseQuery(provider)
        query[kSecValueData as String] = Data(key.utf8)
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    private static func baseQuery(_ provider: Provider) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: provider.keychainAccount,
        ]
    }
}

extension SettingsStore {
    static let translateShortcutKey = "shortcut.translate"
    static let translateReplaceShortcutKey = "shortcut.translateReplace"
    static let polishShortcutKey = "shortcut.polish"

    static func shortcut(forKey key: String, in defaults: UserDefaults = .standard) -> Shortcut? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) }
    }

    static func setShortcut(
        _ shortcut: Shortcut?, forKey key: String, in defaults: UserDefaults = .standard
    ) {
        if let shortcut, let data = try? JSONEncoder().encode(shortcut) {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}

/// Where the floating panel opens.
enum PanelPosition: String, CaseIterable, Sendable {
    case fixed, followSelection

    var title: String {
        switch self {
        case .fixed: "固定位置"
        case .followSelection: "跟随选区"
        }
    }
}

extension SettingsStore {
    static let panelPositionKey = "panel.position"
    /// Top-center of the panel after the user drags it, in AppKit screen coordinates.
    static let panelFixedAnchorKey = "panel.fixedAnchor"

    static func panelPosition(in defaults: UserDefaults = .standard) -> PanelPosition {
        defaults.string(forKey: panelPositionKey).flatMap(PanelPosition.init) ?? .fixed
    }

    static func panelFixedAnchor(in defaults: UserDefaults = .standard) -> CGPoint? {
        guard let values = defaults.array(forKey: panelFixedAnchorKey) as? [Double], values.count == 2
        else { return nil }
        return CGPoint(x: values[0], y: values[1])
    }

    static func setPanelFixedAnchor(_ point: CGPoint, in defaults: UserDefaults = .standard) {
        defaults.set([Double(point.x), Double(point.y)], forKey: panelFixedAnchorKey)
    }
}
