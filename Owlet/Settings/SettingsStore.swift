import Foundation
import Security

struct ServiceConfig: Sendable, Equatable {
    var baseURL: URL
    var model: String
    var apiKey: String
}

enum SettingsStore {
    static let baseURLKey = "service.baseURL"
    static let modelKey = "service.model"
    static let targetLanguageKey = "translation.targetLanguage"
    static let defaultTargetLanguage = "zh-Hans"
    private static let keychainService = "dev.fahchen.owlet.apiKey"

    /// Returns nil when any required setting is missing.
    static func currentConfig() -> ServiceConfig? {
        let defaults = UserDefaults.standard
        guard
            let base = defaults.string(forKey: baseURLKey)?.trimmingCharacters(in: .whitespaces),
            let url = URL(string: base), url.scheme != nil,
            let model = defaults.string(forKey: modelKey)?.trimmingCharacters(in: .whitespaces),
            !model.isEmpty,
            let key = apiKey(), !key.isEmpty
        else { return nil }
        return ServiceConfig(baseURL: url, model: model, apiKey: key)
    }

    static func apiKey() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
            let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func setAPIKey(_ key: String) -> Bool {
        SecItemDelete(baseQuery as CFDictionary)
        guard !key.isEmpty else { return true }
        var query = baseQuery
        query[kSecValueData as String] = Data(key.utf8)
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: "default",
        ]
    }
}
