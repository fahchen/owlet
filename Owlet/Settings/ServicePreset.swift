import Foundation

/// One HTTP service a user can pick instead of looking up its address and a model name. `provider` says
/// which wire protocol reaches it; the preset says which service it is and carries the one vendor
/// difference worth knowing — whether it accepts a response schema (BDR-0015, BDR-0016).
struct ServicePreset: Sendable, Hashable, Identifiable {
    /// Stable key. It names this service's model-memory slot (`service.model.<id>`) and, except for the
    /// custom entry, its keychain account, so the ids older installs already stored keep their meaning.
    let id: String
    /// The English source key for the name shown in the list.
    let title: String
    /// The wire protocol this service speaks.
    var provider: Provider = .openAICompatible
    /// The vendor's published base URL, or nil for OpenAI Compatible, where the address is the user's to type.
    let baseURL: String?
    /// The model filled in when the preset is chosen; empty means the user names one.
    let defaultModel: String
    /// Whether this vendor accepts `response_format: {type: "json_schema"}`. True only where the
    /// vendor's own documentation shows that shape; everywhere else the response shape travels in the
    /// system prompt as `json_object`, which is the safe failure mode.
    let supportsJSONSchema: Bool
    /// The keychain account this service's key lives under; the custom entry keeps the pre-vendor
    /// "default" so an existing key still resolves.
    let keychainAccount: String
}

extension ServicePreset {
    /// The custom entry's id doubles as the pre-preset provider name, so its model slot and the
    /// remembered DeepSeek slot both resolve to what an older install wrote.
    static let customID = "openAICompatible"
    static let deepSeekID = "deepSeek"

    /// OpenAI Compatible: any OpenAI-compatible endpoint. The whole list is a convenience over this entry, which is
    /// why it stays first and keeps the protocol's own schema-capable default.
    static let custom = ServicePreset(
        id: customID, title: "OpenAI Compatible", baseURL: nil, defaultModel: "",
        supportsJSONSchema: true, keychainAccount: "default")

    /// One entry per further protocol, for any endpoint that speaks it. Each fills in the protocol
    /// owner's own address, because the address field is shared and a vendor's would otherwise linger;
    /// the model is the user's to name, as for the custom entry.
    static let openAIResponses = ServicePreset(
        id: "openAIResponses", title: "OpenAI Responses", provider: .openAIResponses,
        baseURL: "https://api.openai.com/v1", defaultModel: "", supportsJSONSchema: true,
        keychainAccount: "openAIResponses")
    static let anthropic = ServicePreset(
        id: "anthropic", title: "Anthropic", provider: .anthropic,
        baseURL: "https://api.anthropic.com/v1", defaultModel: "", supportsJSONSchema: true,
        keychainAccount: "anthropic")
    static let gemini = ServicePreset(
        id: "gemini", title: "Gemini", provider: .gemini,
        baseURL: "https://generativelanguage.googleapis.com/v1beta", defaultModel: "",
        supportsJSONSchema: true, keychainAccount: "gemini")

    /// The vendors, each with the base URL and default model its documentation publishes. Capabilities
    /// marked true were confirmed against that vendor's own documentation; the rest default to the
    /// safer `json_object` (BDR-0015 §3).
    static let deepSeek = ServicePreset(
        id: deepSeekID, title: "DeepSeek", baseURL: "https://api.deepseek.com",
        defaultModel: "deepseek-chat", supportsJSONSchema: false,
        keychainAccount: deepSeekID)
    static let openRouter = ServicePreset(
        id: "openRouter", title: "OpenRouter", baseURL: "https://openrouter.ai/api/v1",
        defaultModel: "openrouter/auto", supportsJSONSchema: false,
        keychainAccount: "openRouter")
    static let ollama = ServicePreset(
        id: "ollama", title: "Ollama (Local)", baseURL: "http://localhost:11434/v1",
        defaultModel: "llama3.2", supportsJSONSchema: false,
        keychainAccount: "ollama")

    /// The picker's first group: one entry per protocol, OpenAI Compatible first.
    static let protocols: [ServicePreset] = [custom, openAIResponses, anthropic, gemini]

    /// The picker's second group: only the most common services, one of each kind — a direct vendor,
    /// an aggregator and a local runtime. Anything else goes through a protocol entry (BDR-0016 §6).
    static let vendors: [ServicePreset] = [deepSeek, openRouter, ollama]

    static let all = protocols + vendors

    static func preset(id: String) -> ServicePreset? { all.first { $0.id == id } }
}

/// One row of the Service picker: an HTTP vendor preset or a local agent. The picker's selection is this
/// value's `id`; what gets persisted is that id, and `provider` is derived from it.
enum ServiceChoice: Sendable, Hashable {
    case preset(ServicePreset)
    case agent(Provider)

    /// Resolves a persisted id. Presets win over providers because the custom entry's id is also the
    /// pre-preset provider name, and both mean the same HTTP choice.
    static func choice(id: String) -> ServiceChoice? {
        if let preset = ServicePreset.preset(id: id) { return .preset(preset) }
        if let agent = Provider(rawValue: id), agent.isLocalAgent { return .agent(agent) }
        return nil
    }

    /// The local agents the list offers, in the order `Provider` declares them.
    static var agents: [Provider] { Provider.allCases.filter(\.isLocalAgent) }

    var id: String {
        switch self {
        case .preset(let preset): preset.id
        case .agent(let agent): agent.rawValue
        }
    }

    var provider: Provider {
        switch self {
        case .preset(let preset): preset.provider
        case .agent(let agent): agent
        }
    }

    var isLocalAgent: Bool { provider.isLocalAgent }

    /// The vendor preset, or nil for a local agent.
    var preset: ServicePreset? {
        guard case .preset(let preset) = self else { return nil }
        return preset
    }

    /// What the model field starts as the first time this service is chosen: the vendor's default
    /// model, or empty for anything that picks its own.
    var defaultModel: String { preset?.defaultModel ?? "" }

    /// Where this service's API key lives; nil for a local agent, which has none.
    var keychainAccount: String? { preset?.keychainAccount }
}
