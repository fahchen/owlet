import Foundation
import Testing

@testable import Owlet

/// The two recipes, the one-shot prompt they receive, and the process plumbing that turns a CLI into
/// a model service (BDR-0013).
///
/// No test here runs a real agent or reaches a model: the recipes are pure values, and the process tests
/// run `/bin/sh` — a real child process, but one that only echoes what it is given.
struct LocalAgentTests {
    let executable = URL(fileURLWithPath: "/bin/sh")
    let directory = URL(fileURLWithPath: "/tmp/owlet-agent-tests")

    /// The environment a shell needs and nothing more, so a test never depends on the developer's own.
    var shellEnvironment: [String: String] { ["PATH": "/usr/bin:/bin"] }

    /// The one-shot request the recipes are planned from: one behaviour prompt, one turn of data.
    func request(model: String = "", effort: EffortLevel = .automatic) -> ModelRequest {
        ModelRequest(
            model: model, system: "SYSTEM", turns: [.user("原文")], format: .jsonObject,
            effort: effort)
    }

    func plan(
        _ kind: LocalAgentKind, model: String = "", effort: EffortLevel = .automatic,
        features: [String]? = nil, overrides: [String]? = nil
    ) -> LocalAgentInvocation {
        LocalAgent.plan(
            kind: kind, executable: executable, request: request(model: model, effort: effort),
            directory: directory, timeout: .seconds(180), features: features, overrides: overrides)
    }

    /// The argument that follows a flag, which is how every recipe passes a value.
    func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag),
            arguments.indices.contains(index + 1)
        else { return nil }
        return arguments[index + 1]
    }

    /// Whether some occurrence of `flag` is immediately followed by `value`; a repeated flag such as
    /// `--disable` carries a different value each time.
    func hasPair(_ flag: String, _ value: String, in arguments: [String]) -> Bool {
        arguments.indices.contains { index in
            arguments[index] == flag && arguments.indices.contains(index + 1)
                && arguments[index + 1] == value
        }
    }

    func shell(
        _ command: String, stdin: String = "", answersToFile: Bool = false,
        system: String = "", writesInstructionsFile: Bool = false
    ) -> LocalAgentInvocation {
        LocalAgentInvocation(
            executable: executable, arguments: ["-c", command], stdin: stdin,
            directory: LocalAgent.temporaryDirectory(),
            systemPrompt: system, answersToFile: answersToFile, schema: nil, writesSchemaFile: false,
            writesInstructionsFile: writesInstructionsFile, timeout: .seconds(20))
    }

    // MARK: - Recipes

    /// Claude Code is the one agent that can drop every tool, and `--safe-mode` keeps the app from
    /// loading the user's own CLAUDE.md, skills, plugins and hooks into a translation request.
    @Test func claudeRunsWithoutToolsOrCustomizations() {
        let invocation = plan(.claudeCode)
        #expect(invocation.arguments.contains("--print"))
        #expect(invocation.arguments.contains("--safe-mode"))
        #expect(invocation.arguments.contains("--no-session-persistence"))
        #expect(invocation.arguments.contains("--strict-mcp-config"))
        #expect(value(after: "--tools", in: invocation.arguments) == "")
        // The system prompt travels as an argument, so the user's text stays on standard input.
        #expect(value(after: "--system-prompt", in: invocation.arguments) == "SYSTEM")
        #expect(invocation.stdin == "原文")
        // A short positional prompt makes the payload on stdin the thing to answer.
        #expect(invocation.arguments.last == LocalAgent.stdinInstruction)
        #expect(!invocation.answersToFile)
    }

    /// Codex has no system-prompt switch: `model_instructions_file` puts the behavior prompt in the
    /// system position, and standard input then carries the user's turn alone. The prompt is a file
    /// here, so it ends the recipe the way the payload does — with `-`.
    @Test func codexRunsReadOnlyAndAnswersIntoAFile() {
        let invocation = plan(.codexCLI)
        #expect(invocation.arguments.first == "exec")
        #expect(invocation.arguments.contains("--ephemeral"))
        #expect(invocation.arguments.contains("--skip-git-repo-check"))
        // Loading the user's own config would connect their MCP servers on every translation request.
        #expect(invocation.arguments.contains("--ignore-user-config"))
        #expect(value(after: "--sandbox", in: invocation.arguments) == "read-only")
        #expect(value(after: "--cd", in: invocation.arguments) == directory.path)
        #expect(value(after: "--disable", in: invocation.arguments) == "shell_tool")
        #expect(value(after: "--output-last-message", in: invocation.arguments) == invocation.answerFile.path)
        #expect(invocation.arguments.last == "-")
        #expect(invocation.answersToFile)
        // The behavior prompt travels as a file, and standard input is the user's turn alone.
        #expect(invocation.writesInstructionsFile)
        #expect(
            hasPair(
                "--config", "model_instructions_file=\"\(invocation.instructionsFile.path)\"",
                in: invocation.arguments))
        #expect(!invocation.arguments.contains("instructions=\"\""))
        #expect(invocation.stdin == "原文")
    }

    /// A provider that takes a response schema gets this contract's, and the way it takes it differs:
    /// Codex reads a file, Claude Code an argument.
    @Test func aSchemaTravelsTheWayEachAgentTakesIt() throws {
        let schema = try JSONSerialization.data(withJSONObject: ["type": "object"])
        let request = ModelRequest(
            model: "", system: "SYSTEM", turns: [.user("原文")],
            format: .jsonSchema(name: "translation", schema: schema), effort: .automatic)

        let codex = LocalAgent.plan(
            kind: .codexCLI, executable: executable, request: request, directory: directory,
            timeout: .seconds(20))
        #expect(value(after: "--output-schema", in: codex.arguments) == codex.schemaFile.path)
        #expect(codex.writesSchemaFile)
        #expect(codex.schema == schema)

        let claude = LocalAgent.plan(
            kind: .claudeCode, executable: executable, request: request, directory: directory,
            timeout: .seconds(20))
        #expect(value(after: "--json-schema", in: claude.arguments) == String(decoding: schema, as: UTF8.self))
        #expect(!claude.writesSchemaFile)
    }

    /// `json_object` means the shape travels in the prompt, so no agent gets a schema on its command line.
    @Test func noSchemaIsPassedWhenTheProviderCannotBeConstrained() {
        let invocation = plan(.codexCLI)
        #expect(invocation.schema == nil)
        #expect(!invocation.writesSchemaFile)
        #expect(!invocation.arguments.contains("--output-schema"))
    }

    /// `codex exec` rejects `--ask-for-approval` with exit 2 — the option belongs to the top level, not
    /// the subcommand — and the user's own hooks ran on every request until they were switched off. Both
    /// were seen against codex 0.160.1; this is what keeps them from coming back.
    ///
    /// The feature names and the `-c` overrides are what the scan read out of the installed build, so
    /// this pins what a fully scanned 0.160.1 sends: every name in its `codex features list`, and the
    /// five overrides it accepted. An empty `instructions` is deliberately absent — combining it with
    /// `model_instructions_file` makes the model read the instruction text as the source.
    @Test func codexGetsItsApprovalPolicyAndNoToolSurface() {
        let invocation = plan(
            .codexCLI, features: CodexFeatures.desired, overrides: CodexFeatures.overrides)
        #expect(!invocation.arguments.contains("--ask-for-approval"))
        #expect(value(after: "--config", in: invocation.arguments) == "approval_policy=\"never\"")
        for feature in [
            "shell_tool", "hooks", "apps", "auth_elicitation", "browser_use", "browser_use_external",
            "browser_use_full_cdp_access", "computer_use", "image_generation", "in_app_browser",
            "multi_agent", "skill_mcp_dependency_install", "skill_search", "sleep_tool",
            "shell_snapshot", "tool_call_mcp_elicitation", "tool_suggest", "view_image",
        ] {
            #expect(hasPair("--disable", feature, in: invocation.arguments), "\(feature) is not disabled")
        }
        for override in [
            "skills.include_instructions=false", "web_search=\"disabled\"",
            "include_environment_context=false", "include_permissions_instructions=false",
            "include_collaboration_mode_instructions=false",
        ] {
            #expect(hasPair("--config", override, in: invocation.arguments), "\(override) is not sent")
        }
        #expect(!invocation.arguments.contains("instructions=\"\""))
    }

    /// A `--disable` name this build does not have exits 2, so the list is the scan's answer, not ours:
    /// only the names the CLI itself reported are sent, and the unknown one never reaches the command.
    @Test func onlyTheFeatureNamesThisBuildReportsAreDisabled() {
        let cached = CodexFeatures.intersect(
            desired: ["shell_tool", "hooks", "view_image"],
            available: ["shell_tool", "view_image", "some_future_feature"])
        #expect(cached == ["shell_tool", "view_image"])

        let invocation = plan(.codexCLI, features: cached)
        #expect(hasPair("--disable", "shell_tool", in: invocation.arguments))
        #expect(hasPair("--disable", "view_image", in: invocation.arguments))
        #expect(!hasPair("--disable", "hooks", in: invocation.arguments))
        #expect(!invocation.arguments.contains("some_future_feature"))
    }

    /// Before any scan, and with no guessed name, only the two that have been in every recent build are
    /// sent. A build that lacks even those costs flags, not the request.
    @Test func withoutAScanOnlyTheLongLivedNamesAreDisabled() {
        #expect(CodexFeatures.sendable(cached: nil) == ["shell_tool", "hooks"])
        let invocation = plan(.codexCLI)
        #expect(invocation.arguments.filter { $0 == "--disable" }.count == 2)
        #expect(hasPair("--disable", "shell_tool", in: invocation.arguments))
        #expect(hasPair("--disable", "hooks", in: invocation.arguments))
        // Nothing was proven about the overrides either, so none is sent.
        #expect(!invocation.arguments.contains(where: { $0.hasPrefix("skills.") }))
        // An empty cache is a fact — this build has none of the names we want — and sends none.
        #expect(CodexFeatures.sendable(cached: []) == [])
    }

    /// The listing the scan reads, in the real shape (`name  stage  enabled`), and the one override it
    /// can reject: `web_search` takes an enum, so a wrong value is a hard config error rather than a
    /// warning, and a build that does not know it must simply not be asked for it.
    @Test func theFeatureListingIsReadByNameAndNothingIsGuessed() {
        let listing = """
            shell_tool                               stable             true
            code_mode_host                           stable             true
            hooks                                    stable             true
            tool_search_always_defer_mcp_tools       removed            true
            """
        #expect(
            CodexFeatures.parse(listing)
                == ["shell_tool", "code_mode_host", "hooks", "tool_search_always_defer_mcp_tools"])
        #expect(CodexFeatures.parse("") == [])
        #expect(CodexFeatures.desired.contains("web_search") == false)
        #expect(
            CodexFeatures.overrides.contains("skills.include_instructions=false")
                && CodexFeatures.overrides.contains("web_search=\"disabled\""))
    }

    /// The behavior prompt is handed over as a private file for Codex, and not at all for Claude Code,
    /// which takes it as `--system-prompt`.
    @Test func theSystemPromptFileIsPrivateAndOnlyCodexGetsOne() async throws {
        let invocation = shell(
            "stat -f '%Lp' instructions.txt; cat instructions.txt",
            system: "SYSTEM", writesInstructionsFile: true)
        let answer = try await LocalAgent.spawn(invocation, environment: shellEnvironment)
        #expect(answer == "600\nSYSTEM")

        #expect(plan(.codexCLI).writesInstructionsFile)
        #expect(!plan(.claudeCode).writesInstructionsFile)
        #expect(!FileManager.default.fileExists(atPath: plan(.claudeCode).instructionsFile.path))
    }

    @Test func aModelNameIsPassedOnlyWhenTheUserSetOne() {
        #expect(value(after: "--model", in: plan(.claudeCode).arguments) == nil)
        #expect(value(after: "--model", in: plan(.claudeCode, model: "sonnet").arguments) == "sonnet")
        #expect(value(after: "--model", in: plan(.codexCLI, model: "gpt-5").arguments) == "gpt-5")
    }

    /// The same rule as every other provider: 自动 sends nothing, and a level the agent does not offer
    /// becomes the nearest lower one — Claude Code has no 关闭, so 关闭 is its lowest.
    @Test func effortMapsToEachAgentsOwnSwitch() {
        for kind in LocalAgentKind.allCases {
            #expect(value(after: "--effort", in: plan(kind).arguments) == nil)
            // Codex carries its effort through `-c`, which is also how its approval policy travels.
            #expect(!plan(kind).arguments.contains { $0.hasPrefix("model_reasoning_effort") })
        }
        #expect(value(after: "--effort", in: plan(.claudeCode, effort: .medium).arguments) == "medium")
        // 关闭 is the untouched install's level. Codex's own enum accepts `none`, but its models do not:
        // `gpt-6.1-sol` answered HTTP 400 and listed low／medium／high／xhigh／max, so 关闭 is its lowest.
        #expect(plan(.codexCLI, effort: .off).arguments.contains("model_reasoning_effort=\"low\""))
        #expect(!plan(.codexCLI, effort: .off).arguments.contains("model_reasoning_effort=\"none\""))
        #expect(value(after: "--effort", in: plan(.claudeCode, effort: .off).arguments) == "low")
        #expect(value(after: "--effort", in: plan(.claudeCode, effort: .max).arguments) == "max")
    }

    // MARK: - The one prompt a one-shot process reads

    /// A corrective round is one call to a one-shot process, so the rejected reply and the correction
    /// request have to stay in order inside the single prompt.
    @Test func aRejectedReplyAndItsCorrectionKeepTheirOrder() {
        let request = ModelRequest(
            model: "m", system: "SYSTEM",
            turns: [.user("DATA"), .assistant("BAD"), .user("TRY AGAIN")],
            format: .jsonObject, effort: .automatic)
        let invocation = LocalAgent.plan(
            kind: .claudeCode, executable: executable, request: request, directory: directory,
            timeout: .seconds(180))
        #expect(invocation.stdin.contains("Previous reply (rejected):\nBAD"))
        let positions = ["DATA", "BAD", "TRY AGAIN"].compactMap {
            invocation.stdin.range(of: $0)?.lowerBound
        }
        #expect(positions.count == 3)
        #expect(positions == positions.sorted())
    }

    /// An agent has no provider envelope, so its answer reaches the caller exactly as the CLI wrote it
    /// — including the whitespace, which only `spawn` trims.
    @Test func theAgentsAnswerIsReturnedAsPlainText() async throws {
        let agent = LocalAgent(run: { _ in "  plain answer  " })
        let answer = try await agent.complete(
            kind: .claudeCode, request: request(model: "m"), config: agentConfig)
        #expect(answer == "  plain answer  ")
    }

    // MARK: - Through the client

    var agentConfig: ServiceConfig {
        ServiceConfig(
            baseURL: LocalAgent.unusedBaseURL, model: "", apiKey: "", provider: .claudeCode,
            effort: .high, agentExecutable: executable)
    }

    /// A local-agent provider must not touch the HTTP transport, and its reply must still be validated:
    /// the answer here is a well-formed translation, so a contract regression would fail this test.
    @Test func aLocalAgentProviderSkipsHTTPAndKeepsTheContract() async throws {
        let seen = Captured()
        var client = ModelClient(transport: { request in
            seen.request = request
            throw URLError(.badServerResponse)
        })
        client.capture = .off
        let invocations = Invocations()
        let reply =
            #"{"source_language":"en","target_language":"zh-Hans","segments":[{"source":"Hello","target":"你好"}]}"#
        client.localAgent = LocalAgent(run: { invocation in
            invocations.add(invocation)
            return reply
        })
        let result = try await client.translate("Hello", to: "zh-Hans", config: agentConfig)
        #expect(result == "你好")
        #expect(seen.request == nil)

        let invocation = try #require(invocations.all.first)
        #expect(invocation.stdin.contains("Hello"))
        #expect(invocation.arguments.contains("--print"))
    }

    /// The OpenAI-style effort field belongs to the HTTP body; a local agent gets the level through its
    /// own switch instead, so the body must not carry a stray key.
    @Test func aLocalAgentGetsNoOpenAIStyleEffortField() throws {
        var client = ModelClient()
        client.promptForOperation = { $0.prompt }
        let request = try client.translationRequest(
            text: "Hello", to: "zh-Hans", config: agentConfig)
        #expect(try wireBody(request, config: agentConfig)["reasoning_effort"] == nil)
    }

    @Test func theDebugPageShowsTheCommandInsteadOfTheBody() throws {
        var client = ModelClient()
        client.promptForOperation = { $0.prompt }
        let request = try client.translationRequest(
            text: "Hello", to: "zh-Hans", config: agentConfig)
        let command = try #require(
            LocalAgent().command(kind: .claudeCode, request: request, config: agentConfig))
        #expect(command.contains(executable.path))
        #expect(command.contains("--safe-mode"))
        #expect(command.contains("Hello"))
        #expect(command.contains("standard input"))
    }

    /// Codex's behavior prompt is in neither the argument list nor standard input, so the debug page has
    /// to name the file it went into; otherwise the recorded request reads as if it had no instructions.
    @Test func theDebugPageShowsWhereCodexReadsItsInstructions() throws {
        var client = ModelClient()
        client.promptForOperation = { $0.prompt }
        let config = ServiceConfig(
            baseURL: LocalAgent.unusedBaseURL, model: "", apiKey: "", provider: .codexCLI,
            effort: .high, agentExecutable: executable, agentFeatures: CodexFeatures.desired,
            agentOverrides: CodexFeatures.overrides)
        let request = try client.translationRequest(text: "Hello", to: "zh-Hans", config: config)
        let command = try #require(
            LocalAgent().command(kind: .codexCLI, request: request, config: config))
        #expect(command.contains("model_instructions_file="))
        #expect(command.contains("instructions.txt"))
        #expect(command.contains("--disable shell_tool"))
        #expect(command.contains("skills.include_instructions=false"))
        #expect(command.contains("Hello"))
    }

    /// An empty answer must fail as an empty reply, not as a broken contract: `.format` is correctable,
    /// so the app would start a second process to fix an answer the model never gave.
    @Test func anEmptyAnswerFailsAsAnEmptyReply() async {
        var client = ModelClient()
        client.capture = .off
        client.localAgent = LocalAgent(run: { _ in "   \n" })
        await #expect(throws: ModelError.emptyResponse) {
            try await client.translate("Hello", to: "zh-Hans", config: agentConfig)
        }
    }

    @Test func aLocalAgentFailureIsAConnectionProblemThatIsNotCorrectable() {
        let error = ModelError.localAgent("exit 1: boom")
        #expect(error.kind == .connection)
        #expect(error.message.contains("exit 1: boom"))
        #expect(!ModelClient.isCorrectable(error))
    }

    // MARK: - Model lists

    /// The real shape `codex debug models` prints, trimmed to the fields the picker reads: one entry
    /// with the levels it accepts, one with a present but empty list, and one that says nothing at all.
    let codexCatalog = """
        {"models":[
          {"slug":"gpt-6.1-sol","display_name":"GPT-6.1-Sol","visibility":"list",
           "supported_reasoning_levels":[
             {"effort":"minimal"},{"effort":"low"},{"effort":"high"},{"effort":"ultra"}
           ]},
          {"slug":"gpt-reserve","display_name":"GPT-Reserve","visibility":"hide"},
          {"slug":"gpt-6-sol","display_name":"GPT-6-Sol","visibility":"list",
           "supported_reasoning_levels":[]},
          {"slug":"gpt-6-codex","visibility":"list"}
        ]}
        """

    @Test func codexModelsComeFromItsCatalogAndSkipHiddenOnes() throws {
        let models = try LocalAgent.parseModels(kind: .codexCLI, payload: Data(codexCatalog.utf8))
        #expect(
            models == [
                // `minimal` is the app's lowest reasoning level, `ultra` its highest, in app order.
                ModelOption(id: "gpt-6.1-sol", label: "GPT-6.1-Sol", efforts: [.low, .high, .max]),
                // A list that is there but empty is the catalogue saying the model does not reason.
                ModelOption(id: "gpt-6-sol", label: "GPT-6-Sol", efforts: []),
                // No key at all: the catalogue said nothing, and the label falls back to the slug.
                ModelOption(id: "gpt-6-codex"),
            ])
    }

    /// The real shape one per-account file in `~/.claude/cache/model-catalog` has, trimmed to the fields
    /// the picker reads: one entry with the whole range, one that stops lower, one that does not reason,
    /// and one that says nothing about effort.
    let claudeCatalog = """
        {"version":2,"fetchedAt":1,"staleAt":2,
         "catalog":{"surface":"cc",
          "config":{"id":"cc","models":[
           {"id":"claude-opus-5-5","name":"Opus 5.5","short_name":"Opus","section":"main",
            "description":"…","capabilities":{"web_search":true},
            "thinking":{"type":"effort","description":"…","effort_options":[
              {"id":"low","name":"Low"},{"id":"medium","name":"Medium"},
              {"id":"high","name":"High"},{"id":"xhigh","name":"Extra"},
              {"id":"max","name":"Max"}]}},
           {"id":"claude-opus-4-6","name":"Opus 4.6","short_name":"Opus","section":"overflow",
            "thinking":{"type":"effort","effort_options":[
              {"id":"low","name":"Low"},{"id":"high","name":"High"},{"id":"max","name":"Max"}]}},
           {"id":"claude-haiku-4-5-20251001","name":"Haiku 4.5","short_name":"Haiku",
            "section":"overflow","thinking":{"type":"none"}},
           {"id":"claude-mystery","short_name":"Mystery","section":"overflow"}
          ],"settings_vocabulary":{"effort_level":{"low":1,"medium":2,"high":3,"xhigh":4,"max":5}}},
          "state":{"model":"claude-opus-5-5",
                   "thinking_by_model":[{"id":"claude-fable-5-1","thinking":{"type":"effort","effort":"high"}}]}}}
        """

    /// Claude Code has no listing command: its list is a catalog file it cached for its own model menu.
    /// `xhigh` is the app's highest level, a model without `xhigh` still reaches `max`, `type: "none"` is
    /// a model that does not reason, and a missing `name` falls back to the short name.
    @Test func claudeModelsComeFromItsCachedCatalog() throws {
        let models = try LocalAgent.parseModels(
            kind: .claudeCode, payload: Data(claudeCatalog.utf8))
        #expect(
            models == [
                ModelOption(
                    id: "claude-opus-5-5", label: "Opus 5.5",
                    efforts: [.low, .medium, .high, .max]),
                ModelOption(id: "claude-opus-4-6", label: "Opus 4.6", efforts: [.low, .high, .max]),
                ModelOption(id: "claude-haiku-4-5-20251001", label: "Haiku 4.5", efforts: []),
                ModelOption(id: "claude-mystery", label: "Mystery"),
            ])
    }

    /// Each agent names its own kind of source, and only the cached one may read nothing as "no list".
    @Test func eachAgentNamesItsOwnModelSource() {
        #expect(LocalAgentKind.claudeCode.modelSource == .catalogFile)
        #expect(LocalAgentKind.codexCLI.modelSource == .command(["debug", "models"]))
        #expect(LocalAgentKind.claudeCode.modelSource.emptyAnswerIsFinal == false)
        #expect(LocalAgentKind.codexCLI.modelSource.emptyAnswerIsFinal == true)
    }

    @Test func anUnreadableCatalogIsALocalAgentFailure() {
        #expect(throws: ModelError.localAgent("the model catalog is unreadable")) {
            try LocalAgent.parseModels(kind: .codexCLI, payload: Data("not json".utf8))
        }
    }

    // MARK: - The cached Claude Code catalog

    /// A directory of its own, so no test reads the developer's real cache.
    func catalogDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "owlet-catalog-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// One per-account catalog file holding just the models a test names, in the real nested shape.
    func catalogData(_ models: [(id: String, name: String?)]) throws -> Data {
        let entries: [[String: Any]] = models.map { model in
            var entry: [String: Any] = ["id": model.id]
            if let name = model.name { entry["name"] = name }
            return entry
        }
        let object: [String: Any] = [
            "version": 2, "fetchedAt": 1, "staleAt": 2,
            "catalog": ["surface": "cc", "config": ["id": "cc", "models": entries]],
        ]
        return try JSONSerialization.data(withJSONObject: object)
    }

    func write(_ payload: Data, named name: String, at date: Date, in directory: URL) throws {
        let url = directory.appending(path: name)
        try payload.write(to: url)
        // The modification date is what "newest" means, so the fixture states it instead of letting it
        // depend on how fast the test wrote its files.
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    /// A cache that is not there, or is not a catalog, is no list — not an error and not a crash. This is
    /// the row Claude Code had before the cache existed.
    @Test func anUnreadableClaudeCatalogIsJustNoList() throws {
        #expect(LocalAgent.claudeCatalog(in: URL(fileURLWithPath: "/nowhere/owlet-cache")).isEmpty)
        #expect(LocalAgent.claudeModels(Data("not json".utf8)) == nil)
        #expect(LocalAgent.claudeModels(Data(#"{"version":2}"#.utf8)) == nil)
        #expect(LocalAgent.claudeModels(Data(#"{"catalog":{"config":{}}}"#.utf8)) == nil)
        #expect(try LocalAgent.claudeModels(catalogData([])) == nil)
        // The same, through the reader the pane uses: no list, and never a failure it has to show.
        #expect(try LocalAgent.parseModels(kind: .claudeCode, payload: Data("not json".utf8)).isEmpty)
        #expect(try LocalAgent.parseModels(kind: .claudeCode, payload: catalogData([])).isEmpty)
    }

    /// Newest first, but only among the files that can actually be read: a corrupt newest file must not
    /// hide the one behind it.
    @Test func theNewestReadableClaudeCatalogWins() throws {
        let directory = try catalogDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date()
        try write(
            catalogData([("older-model", "Older")]), named: "a-cc.json",
            at: now.addingTimeInterval(-600), in: directory)
        try write(
            Data("not json".utf8), named: "b-cc.json", at: now, in: directory)
        #expect(
            LocalAgent.claudeCatalog(in: directory)
                == [ModelOption(id: "older-model", label: "Older")])

        try write(
            catalogData([("newer-model", "Newer")]), named: "c-cc.json",
            at: now.addingTimeInterval(600), in: directory)
        #expect(
            LocalAgent.claudeCatalog(in: directory)
                == [ModelOption(id: "newer-model", label: "Newer")])
    }

    /// The directory also holds published documents with a different shape. Only the per-account
    /// `*-cc.json` files describe this account's models, so one of those wins even when it is older.
    @Test func thePerAccountCatalogIsPreferred() throws {
        let directory = try catalogDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date()
        try write(
            catalogData([("account-model", "Account")]), named: "a-cc.json", at: now, in: directory)
        try write(
            catalogData([("published-model", "Published")]), named: "published-zz.json",
            at: now.addingTimeInterval(600), in: directory)
        #expect(
            LocalAgent.claudeCatalog(in: directory)
                == [ModelOption(id: "account-model", label: "Account")])
    }

    /// Every file is the wrong shape or names no model: the row stays free-form rather than showing an
    /// empty list.
    @Test func aDirectoryOfUnusableCatalogsIsNoList() throws {
        let directory = try catalogDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date()
        try write(catalogData([]), named: "empty-cc.json", at: now, in: directory)
        try write(
            Data(#"{"version":1,"sources":[]}"#.utf8), named: "published-floor.json", at: now,
            in: directory)
        try write(Data("not json".utf8), named: "notes.txt", at: now, in: directory)
        #expect(LocalAgent.claudeCatalog(in: directory).isEmpty)
    }

    // MARK: - Looking an agent up

    /// The `PATH` a Finder-launched app has: no package manager, no per-user bin.
    let minimalPATH = "/usr/bin:/bin:/usr/sbin:/sbin"

    /// The environment a lookup runs with keeps what the app already had and appends the standard
    /// directories, once each. This is the single list the login shell, the agent process and the
    /// shell-free fallback all read (BDR-0013 §10).
    @Test func theLookupEnvironmentAddsTheStandardDirectories() throws {
        let base = ["PATH": minimalPATH, "HOME": "/Users/test"]
        let directories = AgentEnvironment.fallbackDirectories(home: "/Users/test")
        let environment = AgentEnvironment.lookupEnvironment(base: base, directories: directories)
        let path = try #require(environment["PATH"])

        #expect(path.hasPrefix(minimalPATH + ":"))
        let entries = path.split(separator: ":").map(String.init)
        for directory in [
            "/Users/test/.local/bin", "/Users/test/.claude/local", "/Users/test/.local/share/mise/shims",
            "/Users/test/.asdf/shims", "/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin",
            "/usr/local/sbin",
        ] {
            #expect(entries.contains(directory), "missing \(directory)")
        }
        // The app's own entry is kept, even though the standard list names `/usr/bin` and `/bin` too.
        #expect(entries.first == "/usr/bin")
        #expect(Set(entries).count == entries.count)
    }

    /// nvm keeps each Node version under its own directory, so the `bin` of every installed version is
    /// enumerated from that one root — never the home directory as a whole.
    @Test func theDirectLookupEnumeratesNvmVersionBins() throws {
        let home = FileManager.default.temporaryDirectory
            .appending(path: "owlet-nvm-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let root = home.appending(path: ".nvm/versions/node")
        for version in ["v22.1.0", "v20.3.0"] {
            try FileManager.default.createDirectory(
                at: root.appending(path: version).appending(path: "bin"),
                withIntermediateDirectories: true)
        }
        let directories = AgentEnvironment.directLookupDirectories(home: home.path)
        #expect(directories.contains(root.appending(path: "v20.3.0").appending(path: "bin").path))
        #expect(directories.contains(root.appending(path: "v22.1.0").appending(path: "bin").path))
        // A home with no nvm is just the standard list, not a failure.
        #expect(
            AgentEnvironment.directLookupDirectories(home: "/nowhere/owlet-home")
                == AgentEnvironment.fallbackDirectories(home: "/nowhere/owlet-home"))
    }

    /// The first well-known location that has the executable wins, whatever later ones hold.
    @Test func theDirectLookupTakesTheFirstExecutableInOrder() {
        let directories = ["/a/bin", "/b/bin", "/c/bin"]
        #expect(
            LocalAgent.directExecutable(
                named: "claude", directories: directories,
                isExecutable: { $0 == "/b/bin/claude" || $0 == "/c/bin/claude" })?
                .path == "/b/bin/claude")
        #expect(
            LocalAgent.directExecutable(
                named: "claude", directories: directories, isExecutable: { _ in false }) == nil)
    }

    /// The measured failure: the app's own minimal `PATH` cannot see a per-user install, and the login
    /// shell run with it answers nothing. Given the lookup environment, the same probe succeeds.
    @Test func aProbeThatFailsOnTheAppsOwnPathSucceedsWithTheLookupEnvironment() async throws {
        let lookup = AgentLookup(
            baseEnvironment: { ["PATH": minimalPATH] },
            directories: { ["/opt/homebrew/bin", "/Users/test/.local/bin"] },
            isExecutable: { $0 == "/Users/test/.local/bin/claude" },
            run: { _, environment in
                let path = environment["PATH"] ?? ""
                let entries = path.split(separator: ":").map(String.init)
                guard entries.contains("/Users/test/.local/bin") else {
                    return (status: 1, stdout: "", stderr: "")
                }
                return (status: 0, stdout: "/Users/test/.local/bin/claude\n", stderr: "")
            })
        let found = try #require(await LocalAgent.locate(.claudeCode, lookup: lookup))
        #expect(found.path == "/Users/test/.local/bin/claude")
    }

    /// A machine that answers with `zsh -lc` must not pay for the interactive shell, which is slower and
    /// can print a banner.
    @Test func theInteractiveShellIsOnlyAskedWhenTheLoginShellFails() async {
        let seen = Invocations()
        let lookup = AgentLookup(
            baseEnvironment: { ["PATH": minimalPATH] },
            directories: { [] },
            isExecutable: { $0 == "/pkg/bin/claude" },
            run: { invocation, _ in
                seen.add(invocation)
                return (status: 0, stdout: "/pkg/bin/claude\n", stderr: "")
            })
        #expect(await LocalAgent.locate(.claudeCode, lookup: lookup)?.path == "/pkg/bin/claude")
        #expect(seen.all.map(\.arguments.first) == ["-lc"])
    }

    /// `~/.local/bin` added only in `~/.zshrc` is invisible to `zsh -lc`, which reads `.zprofile` but
    /// never `.zshrc`. The interactive login shell is the second ask, and its output is read from the
    /// last non-empty line because an rc file may print a banner first (BDR-0013 §10).
    @Test func theInteractiveShellFindsWhatOnlyZshrcAdds() async {
        let seen = Invocations()
        let lookup = AgentLookup(
            baseEnvironment: { ["PATH": minimalPATH] },
            directories: { [] },
            isExecutable: { $0 == "/Users/test/.local/bin/claude" },
            run: { invocation, _ in
                seen.add(invocation)
                guard invocation.arguments.first == "-ilc" else {
                    return (status: 1, stdout: "", stderr: "")
                }
                return (status: 0, stdout: "welcome back\n/Users/test/.local/bin/claude\n", stderr: "")
            })
        let found = await LocalAgent.locate(.claudeCode, lookup: lookup)
        #expect(found?.path == "/Users/test/.local/bin/claude")
        #expect(seen.all.map(\.arguments.first) == ["-lc", "-ilc"])
        #expect(LocalAgent.lastNonEmptyLine("  \n a \n /b/c \n") == "/b/c")
        #expect(LocalAgent.lastNonEmptyLine(" \n ") == nil)
    }

    /// Both shells failing is not the end: the well-known locations are checked directly, so detection
    /// no longer depends on the user's shell configuration at all.
    @Test func theDirectLookupFindsWhatBothShellsMiss() async {
        let lookup = AgentLookup(
            baseEnvironment: { ["PATH": minimalPATH] },
            directories: { ["/opt/homebrew/bin", "/Users/test/.local/bin"] },
            isExecutable: { $0 == "/Users/test/.local/bin/codex" },
            run: { _, _ in (status: 1, stdout: "", stderr: "") })
        #expect(
            await LocalAgent.locate(.codexCLI, lookup: lookup)?.path == "/Users/test/.local/bin/codex")
    }

    /// The version probe is an agent process too, so it gets the lookup environment: a CLI that is a
    /// `#!/usr/bin/env node` script cannot start without the directory its interpreter lives in.
    @Test func theVersionProbeRunsWithTheLookupEnvironment() async {
        let lookup = AgentLookup(
            baseEnvironment: { ["PATH": minimalPATH] },
            directories: { ["/Users/test/.local/bin"] },
            isExecutable: { $0 == "/Users/test/.local/bin/claude" },
            run: { invocation, environment in
                guard invocation.arguments.first != "-lc" else {
                    return (status: 0, stdout: "/Users/test/.local/bin/claude\n", stderr: "")
                }
                let path = environment["PATH"] ?? ""
                return path.contains("/Users/test/.local/bin")
                    ? (status: 0, stdout: "2.1.299 (Claude Code)\n", stderr: "")
                    : (status: 1, stdout: "", stderr: "no node")
            })
        let detection = await LocalAgent.detect(.claudeCode, lookup: lookup)
        #expect(
            detection
                == .found(
                    executable: URL(fileURLWithPath: "/Users/test/.local/bin/claude"),
                    version: "2.1.299 (Claude Code)"))
    }

    /// A machine with no trace of the CLI still gets a detection result, and that result tells the user
    /// the executable can be chosen by hand — the escape hatch the pane offers next to it. The expected
    /// text is the same lookup the app does, so the assertion does not depend on the run's language.
    @Test func aMissingAgentSaysItCanBeChosenByHand() async {
        let lookup = AgentLookup(
            baseEnvironment: { ["PATH": minimalPATH] },
            directories: { [] },
            isExecutable: { _ in false },
            run: { _, _ in (status: 1, stdout: "", stderr: "") })
        guard case .failed(let message) = await LocalAgent.detect(.claudeCode, lookup: lookup) else {
            Issue.record("a machine without the CLI must fail the detection")
            return
        }
        #expect(
            message
                == L10n.shared.string(
                    "%@ was not found. Choose its executable by hand, or install it and press Detect.",
                    "claude"))
    }

    // MARK: - Effort

    /// The names the CLIs use for a level, mapped to the app's own; a name no CLI uses is rejected
    /// rather than guessed at.
    @Test func anAgentEffortNameMapsToAnAppLevel() {
        #expect(LocalAgent.effortLevel("none") == .off)
        #expect(LocalAgent.effortLevel("minimal") == .low)
        #expect(LocalAgent.effortLevel("low") == .low)
        #expect(LocalAgent.effortLevel("medium") == .medium)
        #expect(LocalAgent.effortLevel("high") == .high)
        #expect(LocalAgent.effortLevel("xhigh") == .max)
        #expect(LocalAgent.effortLevel("max") == .max)
        #expect(LocalAgent.effortLevel("ultra") == .max)
        #expect(LocalAgent.effortLevel("turbo") == nil)
    }

    /// When the agent said nothing about the model, the static per-CLI table decides, exactly as it did
    /// before there was a catalogue: Claude Code has no `none`, so 关闭 becomes its lowest level.
    @Test func aModelWithNoWordFromTheAgentKeepsTheStaticTable() {
        #expect(LocalAgentKind.claudeCode.effortValue(.off) == "low")
        #expect(LocalAgentKind.codexCLI.effortValue(.off) == "low")
        #expect(LocalAgentKind.codexCLI.effortValue(.max) == "max")
    }

    /// An empty list is the agent saying the model does not reason: no effort switch is passed at all.
    @Test func aModelThatDoesNotReasonGetsNoEffortSwitch() {
        for level in EffortLevel.allCases where level != .automatic {
            #expect(LocalAgentKind.claudeCode.effortValue(level, supported: []) == nil)
            #expect(LocalAgentKind.codexCLI.effortValue(level, supported: []) == nil)
        }
    }

    /// A level above what the model takes walks down to the nearest one it does; below all of them, the
    /// lowest is sent. Either way the string is the CLI's own word for that level.
    @Test func aSupportedSubsetClampsToItsOwnRange() {
        let supported: [EffortLevel] = [.low, .medium, .high]
        #expect(LocalAgentKind.codexCLI.effortValue(.max, supported: supported) == "high")
        #expect(LocalAgentKind.codexCLI.effortValue(.high, supported: supported) == "high")
        #expect(LocalAgentKind.codexCLI.effortValue(.medium, supported: supported) == "medium")
        #expect(LocalAgentKind.codexCLI.effortValue(.off, supported: supported) == "low")
    }

    @Test func automaticNeverSendsAnEffortSwitch() {
        for kind in LocalAgentKind.allCases {
            #expect(kind.effortValue(.automatic) == nil)
            #expect(kind.effortValue(.automatic, supported: []) == nil)
            #expect(kind.effortValue(.automatic, supported: [.low, .high]) == nil)
        }
    }

    // MARK: - The process

    @Test func thePromptArrivesOnStandardInput() async throws {
        let invocation = shell("cat", stdin: "原文")
        let answer = try await LocalAgent.spawn(invocation, environment: shellEnvironment)
        #expect(answer == "原文")
        // The temporary directory goes with the answer, so nothing of the user's text is left behind.
        #expect(!FileManager.default.fileExists(atPath: invocation.directory.path))
    }

    @Test func anAnswerThatArrivesInAFileIsRead() async throws {
        let invocation = shell("printf 'from the file' > answer.txt", answersToFile: true)
        let answer = try await LocalAgent.spawn(invocation, environment: shellEnvironment)
        #expect(answer == "from the file")
    }

    @Test func anAgentThatExitsNonZeroReportsItsOwnError() async throws {
        let invocation = shell("echo boom >&2; exit 3")
        await #expect(throws: ModelError.localAgent("exit 3: boom")) {
            try await LocalAgent.spawn(invocation, environment: shellEnvironment)
        }
    }

    /// Claude Code prints a quota message on standard *output* and exits 1, so reading only the error
    /// stream turned a real explanation into "exit 1: " with nothing after it.
    @Test func anAgentThatExplainsItselfOnStandardOutputIsStillRead() async throws {
        let invocation = shell("echo 'You have hit your weekly limit'; exit 1")
        await #expect(throws: ModelError.localAgent("exit 1: You have hit your weekly limit")) {
            try await LocalAgent.spawn(invocation, environment: shellEnvironment)
        }
    }

    @Test func anAgentThatNeverAnswersIsStopped() async throws {
        var invocation = shell("sleep 30")
        invocation.timeout = .milliseconds(200)
        let start = ContinuousClock.now
        do {
            let answer = try await LocalAgent.spawn(invocation, environment: shellEnvironment)
            Issue.record("a hung agent must not answer: \(answer)")
        } catch let error as ModelError {
            guard case .localAgent(let detail) = error else {
                Issue.record("unexpected failure: \(error)")
                return
            }
            #expect(detail.hasPrefix("no answer within"))
        }
        #expect(ContinuousClock.now - start < .seconds(10))
    }

    @Test func cancellingTheRequestEndsTheProcess() async throws {
        var invocation = shell("sleep 30")
        invocation.timeout = .seconds(60)
        let task = Task { try await LocalAgent.spawn(invocation, environment: shellEnvironment) }
        try await Task.sleep(for: .milliseconds(200))
        task.cancel()
        switch await task.result {
        case .success(let answer): Issue.record("a cancelled request must not answer: \(answer)")
        case .failure(let error): #expect(error is CancellationError)
        }
    }

    /// One translation plus its learning request plus a lookup would otherwise start three CLIs.
    @Test func noMoreThanTheLimitRunsAtOnce() async {
        let gate = AgentGate(limit: 2)
        let tracker = ConcurrencyTracker()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<6 {
                group.addTask {
                    try? await gate.withSlot {
                        await tracker.enter()
                        try? await Task.sleep(for: .milliseconds(30))
                        await tracker.exit()
                    }
                }
            }
        }
        let peak = await tracker.peak
        #expect(peak <= 2)
    }
}

/// The invocations a fake runner saw, so a `@Sendable` closure can record without capturing a `var`.
final class Invocations: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [LocalAgentInvocation] = []

    func add(_ invocation: LocalAgentInvocation) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(invocation)
    }

    var all: [LocalAgentInvocation] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

/// How many slots were in use at the busiest moment.
actor ConcurrencyTracker {
    private var current = 0
    private(set) var peak = 0

    func enter() {
        current += 1
        peak = max(peak, current)
    }

    func exit() { current -= 1 }
}
