import Foundation
import SwiftUI
import Security

enum Provider: String, CaseIterable, Sendable {
    case openAICompatible, deepSeek

    var title: LocalizedStringResource {
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

/// How hard the provider may think before answering. `.automatic` keeps the provider's own default
/// and sends no parameter, so models that reject the field are never sent it.
enum EffortLevel: String, CaseIterable, Sendable {
    case automatic = "automatic"
    case off = "none"
    case low = "low"
    case medium = "medium"
    case high = "high"
    case max = "max"

    var title: LocalizedStringResource {
        switch self {
        case .automatic: "Automatic (the provider's default)"
        case .off: "Off"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        case .max: "Highest"
        }
    }
}

struct ServiceConfig: Sendable, Equatable {
    var baseURL: URL
    var model: String
    var apiKey: String
    var provider: Provider = .openAICompatible
    var effort: EffortLevel = .off
}

enum SettingsStore {
    static let providerKey = "service.provider"
    static let baseURLKey = "service.baseURL"
    static let modelKey = "service.model"
    static let targetLanguageKey = "translation.targetLanguage"
    /// The language used when the mapping has no row for the detected source. It doubles as the
    /// pre-mapping "target language" setting, so an older install migrates without a write.
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
        return ServiceConfig(
            baseURL: url, model: model, apiKey: key, provider: provider, effort: effort())
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
    static let effortKey = "service.effort"

    /// The saved 思考强度, defaulting to 自动 so an untouched install keeps sending no effort parameter.
    static func effort(in defaults: UserDefaults = .standard) -> EffortLevel {
        defaults.string(forKey: effortKey).flatMap(EffortLevel.init) ?? .off
    }
}

extension SettingsStore {
    static let translateShortcutKey = "shortcut.translate"
    static let translateReplaceShortcutKey = "shortcut.translateReplace"
    static let polishShortcutKey = "shortcut.polish"
    static let polishReplaceShortcutKey = "shortcut.polishReplace"

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

/// How a result is laid out: whole 原文／译文 regions, or the response's paired sentences.
enum TranslationDisplayMode: String, CaseIterable, Sendable {
    case sectioned
    case aligned

    var title: LocalizedStringResource {
        switch self {
        case .sectioned: "Source / Result Sections"
        case .aligned: "Sentence by Sentence"
        }
    }

}

extension SettingsStore {
    static let displayModeKey = "translation.displayMode"

    /// The saved display preference, defaulting to 分区 so an untouched install keeps the old layout.
    static func displayMode(in defaults: UserDefaults = .standard) -> TranslationDisplayMode {
        defaults.string(forKey: displayModeKey).flatMap(TranslationDisplayMode.init) ?? .sectioned
    }
}

/// Source → target mapping (BDR-0003): the target follows the detected source language, an explicit
/// choice pins it, and `translation.targetLanguage` is the fallback.
extension SettingsStore {
    static let targetMappingKey = "translation.targetMapping"
    static let pinnedTargetKey = "translation.pinnedTarget"
    static let pinnedSourceKey = "translation.pinnedSource"

    static func targetMapping(in defaults: UserDefaults = .standard) -> TargetMapping {
        TargetMapping(
            targets: defaults.dictionary(forKey: targetMappingKey) as? [String: String] ?? [:],
            fallback: defaults.string(forKey: targetLanguageKey) ?? defaultTargetLanguage)
    }

    static func setTargetMapping(_ mapping: TargetMapping, in defaults: UserDefaults = .standard) {
        defaults.set(mapping.targets, forKey: targetMappingKey)
        defaults.set(mapping.fallback, forKey: targetLanguageKey)
    }

    /// The language the user pinned; nil (or an empty value) means 自动.
    static func pinnedTarget(in defaults: UserDefaults = .standard) -> String? {
        guard let tag = defaults.string(forKey: pinnedTargetKey), !tag.isEmpty else { return nil }
        return tag
    }

    static func setPinnedTarget(_ tag: String?, in defaults: UserDefaults = .standard) {
        if let tag, !tag.isEmpty {
            defaults.set(tag, forKey: pinnedTargetKey)
        } else {
            defaults.removeObject(forKey: pinnedTargetKey)
        }
    }

    /// The source 自动 uses: the user's choice when they made one, else what the text looks like.
    static func autoSource(for text: String, in defaults: UserDefaults = .standard) -> String? {
        pinnedSource(in: defaults) ?? LanguageDetector.detect(text)
    }

    /// The language the user pinned as the source; nil (or an empty value) means 自动.
    static func pinnedSource(in defaults: UserDefaults = .standard) -> String? {
        guard let tag = defaults.string(forKey: pinnedSourceKey), !tag.isEmpty else { return nil }
        return tag
    }

    static func setPinnedSource(_ tag: String?, in defaults: UserDefaults = .standard) {
        if let tag, !tag.isEmpty {
            defaults.set(tag, forKey: pinnedSourceKey)
        } else {
            defaults.removeObject(forKey: pinnedSourceKey)
        }
    }

    /// What 自动 resolves to for this text: the mapping row for the source, else the fallback.
    /// Detection happens here, once per request.
    static func autoTarget(for text: String, in defaults: UserDefaults = .standard) -> String {
        targetMapping(in: defaults).target(forSource: autoSource(for: text, in: defaults))
    }

    /// The target a newly chosen source carries over: its mapping row, so switching the source moves
    /// the target with it, and 自动 for an automatic source. The user can still change the target after.
    static func target(followingSource source: String, in defaults: UserDefaults = .standard) -> String {
        source.isEmpty ? "" : targetMapping(in: defaults).target(forSource: source)
    }

    /// The target a request should use: an explicit choice wins, otherwise 自动 decides.
    static func resolvedTarget(for text: String, in defaults: UserDefaults = .standard) -> String {
        pinnedTarget(in: defaults) ?? autoTarget(for: text, in: defaults)
    }
}

/// The hidden diagnostics page: off by default, and it keeps model exchanges in memory only.
extension SettingsStore {
    static let debugEnabledKey = "debug.enabled"
    /// The settings pane the window opens on, kept so it returns to the last one people used.
    static let settingsPaneKey = "settings.pane"
    /// Which language the interface speaks; absent means follow the system.
    static let appLanguageKey = "app.language"

    static func isDebugEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: debugEnabledKey)
    }

    static func appLanguage(in defaults: UserDefaults = .standard) -> AppLanguage {
        AppLanguage.resolve(
            saved: defaults.string(forKey: appLanguageKey),
            preferred: Locale.preferredLanguages)
    }
}

/// The languages in play. Every control that picks a language offers this subset, so the system's
/// list of hundreds is only seen while adding one.
extension SettingsStore {
    static let languagesKey = "translation.languages"
    /// What a fresh install starts with: the languages the product targets.
    static let defaultLanguages = ["zh-Hans", "en", "ja"]

    static func languages(in defaults: UserDefaults = .standard) -> [String] {
        let stored = defaults.stringArray(forKey: languagesKey) ?? []
        return stored.isEmpty ? defaultLanguages : stored
    }

    /// Saves the selection and keeps everything else inside it, so a removed language cannot stay
    /// behind as a fallback, a pin or a mapping row that no picker can show any more.
    static func setLanguages(_ tags: [String], in defaults: UserDefaults = .standard) {
        defaults.set(tags, forKey: languagesKey)
        let allowed = Set(languages(in: defaults))
        var mapping = targetMapping(in: defaults)
        mapping.targets = mapping.targets.filter {
            allowed.contains($0.key) && allowed.contains($0.value)
        }
        if !allowed.contains(mapping.fallback) {
            mapping.fallback = languages(in: defaults).first ?? defaultTargetLanguage
        }
        setTargetMapping(mapping, in: defaults)
        if let pinned = pinnedTarget(in: defaults), !allowed.contains(pinned) {
            setPinnedTarget(nil, in: defaults)
        }
        if let pinned = pinnedSource(in: defaults), !allowed.contains(pinned) {
            setPinnedSource(nil, in: defaults)
        }
    }
}

/// Where the floating panel opens.
enum PanelPosition: String, CaseIterable, Sendable {
    case fixed, followSelection

    var title: LocalizedStringResource {
        switch self {
        case .fixed: "Fixed Position"
        case .followSelection: "Follow the Selection"
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

/// Per-operation 学习表达 switches; an absent key reads as off, so learning stays opt-in.
extension SettingsStore {
    static let translateLearningKey = "learning.auto.translate"
    static let polishLearningKey = "learning.auto.polish"

    /// The stored key for one operation, so the two switches can never share a value.
    static func learningKey(for operation: Operation) -> String {
        switch operation {
        case .translate: translateLearningKey
        case .polish: polishLearningKey
        }
    }

    /// Whether a later successful result of this operation should request learning on its own.
    static func autoRequestsLearning(
        for operation: Operation, in defaults: UserDefaults = .standard
    ) -> Bool {
        defaults.bool(forKey: learningKey(for: operation))
    }
}

extension SettingsStore {
    /// The built-in prompt an operation falls back to; a custom prompt never changes it.
    static func defaultPrompt(for operation: Operation) -> String { operation.prompt }

    static func promptKey(for operation: Operation) -> String { "prompt.\(operation.rawValue)" }

    /// The effective prompt for later requests: the saved one, or the built-in default.
    static func prompt(for operation: Operation, in defaults: UserDefaults = .standard) -> String {
        guard let saved = defaults.string(forKey: promptKey(for: operation)),
            !isBlank(saved)
        else { return defaultPrompt(for: operation) }
        return saved
    }

    /// Persists one prompt; blank text is refused so the previous value stays in force.
    @discardableResult
    static func setPrompt(
        _ text: String, for operation: Operation, in defaults: UserDefaults = .standard
    ) -> Bool {
        guard !isBlank(text) else { return false }
        // A prompt equal to the default is stored as "no custom prompt", so the state stays 默认 even
        // if the built-in prompts change in a later version.
        if text == defaultPrompt(for: operation) {
            defaults.removeObject(forKey: promptKey(for: operation))
        } else {
            defaults.set(text, forKey: promptKey(for: operation))
        }
        return true
    }

    /// Whether the saved text differs from the built-in default, which is what the settings badge shows.
    static func isCustomized(_ operation: Operation, in defaults: UserDefaults = .standard) -> Bool {
        guard let saved = defaults.string(forKey: promptKey(for: operation)) else { return false }
        return !isBlank(saved) && saved != defaultPrompt(for: operation)
    }

    private static func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
