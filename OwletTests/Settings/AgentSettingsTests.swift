import Foundation
import Testing

@testable import Owlet

/// Which local agent the app would run, and what counts as a complete configuration: an executable that
/// is really there takes the API key's place, and the model name may be left to the agent (BDR-0013).
///
/// Every test reads a store of its own. An HTTP provider is deliberately not covered here: its key comes
/// from the Keychain, and a test must never touch the developer's own.
struct AgentSettingsTests {
    let suite = "AgentSettingsTests.\(UUID().uuidString)"
    var defaults: UserDefaults { UserDefaults(suiteName: suite)! }

    @Test func aLocalAgentNeedsAnExecutableInsteadOfAKey() throws {
        defaults.set(Provider.claudeCode.rawValue, forKey: SettingsStore.providerKey)
        #expect(SettingsStore.currentConfig(in: defaults) == nil)

        SettingsStore.setAgentPath("/bin/sh", for: .claudeCode, in: defaults)
        let config = try #require(SettingsStore.currentConfig(in: defaults))
        #expect(config.provider == .claudeCode)
        #expect(config.model.isEmpty)
        #expect(config.apiKey.isEmpty)
        #expect(config.agentExecutable?.path == "/bin/sh")
    }

    @Test func aPathThatIsNotThereIsNoConfiguration() {
        defaults.set(Provider.codexCLI.rawValue, forKey: SettingsStore.providerKey)
        SettingsStore.setAgentPath("/nowhere/codex", for: .codexCLI, in: defaults)
        #expect(SettingsStore.currentConfig(in: defaults) == nil)
    }

    @Test func theModelNameIsOptionalForALocalAgent() throws {
        defaults.set(Provider.claudeCode.rawValue, forKey: SettingsStore.providerKey)
        SettingsStore.setAgentPath("/bin/sh", for: .claudeCode, in: defaults)

        defaults.set("   ", forKey: SettingsStore.modelKey)
        let blank = try #require(SettingsStore.currentConfig(in: defaults))
        #expect(blank.model.isEmpty)

        defaults.set("sonnet", forKey: SettingsStore.modelKey)
        let named = try #require(SettingsStore.currentConfig(in: defaults))
        #expect(named.model == "sonnet")
    }

    @Test func eachAgentKeepsItsOwnExecutable() {
        SettingsStore.setAgentPath("/bin/sh", for: .claudeCode, in: defaults)
        SettingsStore.setAgentPath("/bin/ls", for: .codexCLI, in: defaults)
        #expect(SettingsStore.agentPath(for: .claudeCode, in: defaults) == "/bin/sh")
        #expect(SettingsStore.agentPath(for: .codexCLI, in: defaults) == "/bin/ls")

        SettingsStore.setAgentPath(nil, for: .claudeCode, in: defaults)
        #expect(SettingsStore.agentPath(for: .claudeCode, in: defaults) == nil)
        // Clearing one agent must not touch the other's path.
        #expect(SettingsStore.agentPath(for: .codexCLI, in: defaults) == "/bin/ls")
    }

    /// What an agent said a model accepts is kept per provider and per model, so switching either one
    /// cannot carry the other's levels along.
    @Test func theEffortsAnAgentReportedReadBackPerProviderAndModel() {
        SettingsStore.setSupportedEfforts(
            [.low, .high], for: .codexCLI, model: "gpt-6.1-sol", in: defaults)
        #expect(
            SettingsStore.supportedEfforts(for: .codexCLI, model: "gpt-6.1-sol", in: defaults)
                == [.low, .high])
        #expect(SettingsStore.supportedEfforts(for: .codexCLI, model: "gpt-6-sol", in: defaults) == nil)
        #expect(SettingsStore.supportedEfforts(for: .claudeCode, model: "gpt-6.1-sol", in: defaults) == nil)
    }

    /// An empty list is a fact — the model does not reason — and must not read back as "the agent said
    /// nothing", or an effort level the model rejects would be sent to it.
    @Test func aModelThatDoesNotReasonReadsBackAsAnEmptyList() throws {
        SettingsStore.setSupportedEfforts([], for: .codexCLI, model: "gpt-6-sol", in: defaults)
        let levels = try #require(
            SettingsStore.supportedEfforts(for: .codexCLI, model: "gpt-6-sol", in: defaults))
        #expect(levels.isEmpty)
    }

    @Test func removingWhatAnAgentSaidLeavesNoEntry() {
        SettingsStore.setSupportedEfforts([.high], for: .codexCLI, model: "m", in: defaults)
        SettingsStore.setSupportedEfforts(nil, for: .codexCLI, model: "m", in: defaults)
        #expect(SettingsStore.supportedEfforts(for: .codexCLI, model: "m", in: defaults) == nil)
    }

    @Test func twoProvidersKeepTheirOwnEfforts() {
        SettingsStore.setSupportedEfforts([.high], for: .codexCLI, model: "m", in: defaults)
        SettingsStore.setSupportedEfforts([], for: .claudeCode, model: "m", in: defaults)
        #expect(SettingsStore.supportedEfforts(for: .codexCLI, model: "m", in: defaults) == [.high])
        #expect(SettingsStore.supportedEfforts(for: .claudeCode, model: "m", in: defaults) == [])
    }

    @Test func providersCarryTheirOwnCapabilities() {
        #expect(Provider.claudeCode.localAgent == LocalAgentKind.claudeCode)
        #expect(Provider.codexCLI.localAgent == LocalAgentKind.codexCLI)
        #expect(Provider.deepSeek.localAgent == nil)
        #expect(Provider.openAICompatible.localAgent == nil)

        #expect(Provider.claudeCode.isLocalAgent)
        #expect(Provider.openAICompatible.supportsJSONSchema)
        // Both local agents take a schema on the command line.
        #expect(Provider.claudeCode.supportsJSONSchema)
        #expect(Provider.codexCLI.supportsJSONSchema)
        // DeepSeek only takes `json_object`, so its shape travels in the prompt.
        #expect(!Provider.deepSeek.supportsJSONSchema)
        // A local agent has no API key, so no preset URL or model is filled in for it.
        #expect(Provider.claudeCode.preset == nil)
        #expect(Provider.codexCLI.preset == nil)
    }
}
