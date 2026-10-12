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
        defaults.set(Provider.piCLI.rawValue, forKey: SettingsStore.providerKey)
        #expect(SettingsStore.currentConfig(in: defaults) == nil)

        SettingsStore.setAgentPath("/bin/sh", for: .piCLI, in: defaults)
        let config = try #require(SettingsStore.currentConfig(in: defaults))
        #expect(config.provider == .piCLI)
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
        SettingsStore.setAgentPath("/bin/sh", for: .piCLI, in: defaults)
        SettingsStore.setAgentPath("/bin/ls", for: .codexCLI, in: defaults)
        #expect(SettingsStore.agentPath(for: .piCLI, in: defaults) == "/bin/sh")
        #expect(SettingsStore.agentPath(for: .codexCLI, in: defaults) == "/bin/ls")
        #expect(SettingsStore.agentPath(for: .claudeCode, in: defaults) == nil)

        SettingsStore.setAgentPath(nil, for: .piCLI, in: defaults)
        #expect(SettingsStore.agentPath(for: .piCLI, in: defaults) == nil)
    }

    @Test func providersCarryTheirOwnCapabilities() {
        #expect(Provider.piCLI.localAgent == LocalAgentKind.piCLI)
        #expect(Provider.claudeCode.localAgent == LocalAgentKind.claudeCode)
        #expect(Provider.codexCLI.localAgent == LocalAgentKind.codexCLI)
        #expect(Provider.deepSeek.localAgent == nil)
        #expect(Provider.openAICompatible.localAgent == nil)

        #expect(Provider.claudeCode.isLocalAgent)
        #expect(Provider.openAICompatible.supportsJSONSchema)
        // No local agent has a response-format parameter, so its shape travels in the prompt.
        #expect(!Provider.piCLI.supportsJSONSchema)
        #expect(!Provider.deepSeek.supportsJSONSchema)
        // A local agent has no API key, so no preset URL or model is filled in for it.
        #expect(Provider.piCLI.preset == nil)
    }
}
