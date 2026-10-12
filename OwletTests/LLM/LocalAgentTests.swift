import Foundation
import Testing

@testable import Owlet

/// The three recipes, the one-shot prompt they receive, and the process plumbing that turns a CLI into
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
        _ kind: LocalAgentKind, model: String = "", effort: EffortLevel = .automatic
    ) -> LocalAgentInvocation {
        LocalAgent.plan(
            kind: kind, executable: executable, request: request(model: model, effort: effort),
            directory: directory, timeout: .seconds(180))
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

    func shell(_ command: String, stdin: String = "", answersToFile: Bool = false) -> LocalAgentInvocation {
        LocalAgentInvocation(
            executable: executable, arguments: ["-c", command], stdin: stdin,
            directory: LocalAgent.temporaryDirectory(), writesSystemPromptFile: false,
            systemPrompt: "", answersToFile: answersToFile, schema: nil, writesSchemaFile: false,
            timeout: .seconds(20))
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
        #expect(!invocation.writesSystemPromptFile)
        #expect(!invocation.answersToFile)
    }

    @Test func piDropsToolsExtensionsAndContextFiles() {
        let invocation = plan(.piCLI)
        for flag in [
            "--print", "--no-tools", "--no-extensions", "--no-mcp", "--no-skills",
            "--no-prompt-templates", "--no-context-files", "--no-session", "--no-approve",
        ] {
            #expect(invocation.arguments.contains(flag))
        }
        // The system prompt goes through a private file instead of the command line.
        #expect(value(after: "--system-prompt", in: invocation.arguments) == invocation.systemPromptFile.path)
        #expect(invocation.writesSystemPromptFile)
        #expect(invocation.stdin == "原文")
        #expect(invocation.arguments.last == LocalAgent.stdinInstruction)
    }

    /// Codex has no system-prompt switch and reads its prompt from stdin only when it gets no prompt
    /// argument, which is why the recipe ends with `-`.
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
        #expect(invocation.stdin == "SYSTEM\n\n原文")
    }

    /// A provider that takes a response schema gets this contract's, and the way it takes it differs:
    /// Codex reads a file, Claude Code an argument, pi has no such switch.
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

        let pi = LocalAgent.plan(
            kind: .piCLI, executable: executable, request: request, directory: directory,
            timeout: .seconds(20))
        #expect(!pi.arguments.contains("--output-schema"))
        #expect(!pi.arguments.contains("--json-schema"))
        #expect(pi.schema == nil)
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
    @Test func codexGetsItsApprovalPolicyAndNoHooks() {
        let invocation = plan(.codexCLI)
        #expect(!invocation.arguments.contains("--ask-for-approval"))
        #expect(value(after: "--config", in: invocation.arguments) == "approval_policy=\"never\"")
        #expect(hasPair("--disable", "hooks", in: invocation.arguments))
    }

    @Test func aModelNameIsPassedOnlyWhenTheUserSetOne() {
        #expect(value(after: "--model", in: plan(.piCLI).arguments) == nil)
        #expect(value(after: "--model", in: plan(.piCLI, model: "sonnet").arguments) == "sonnet")
        #expect(value(after: "--model", in: plan(.codexCLI, model: "gpt-5").arguments) == "gpt-5")
    }

    /// The same rule as every other provider: 自动 sends nothing, and a level the agent does not offer
    /// becomes the nearest lower one — Claude Code has no 关闭, so 关闭 is its lowest.
    @Test func effortMapsToEachAgentsOwnSwitch() {
        for kind in LocalAgentKind.allCases {
            #expect(value(after: "--effort", in: plan(kind).arguments) == nil)
            #expect(value(after: "--thinking", in: plan(kind).arguments) == nil)
            // Codex carries its effort through `-c`, which is also how its approval policy travels.
            #expect(!plan(kind).arguments.contains { $0.hasPrefix("model_reasoning_effort") })
        }
        #expect(value(after: "--thinking", in: plan(.piCLI, effort: .high).arguments) == "high")
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
            kind: .piCLI, executable: executable, request: request, directory: directory,
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
            kind: .piCLI, request: request(model: "m"), config: agentConfig)
        #expect(answer == "  plain answer  ")
    }

    // MARK: - Through the client

    var agentConfig: ServiceConfig {
        ServiceConfig(
            baseURL: LocalAgent.unusedBaseURL, model: "", apiKey: "", provider: .piCLI,
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
            LocalAgent().command(kind: .piCLI, request: request, config: agentConfig))
        #expect(command.contains(executable.path))
        #expect(command.contains("--no-tools"))
        #expect(command.contains("Hello"))
        #expect(command.contains("standard input"))
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

    /// The real shape `codex debug models` prints, trimmed to the fields the picker reads.
    let codexCatalog = """
        {"models":[
          {"slug":"gpt-6.1-sol","display_name":"GPT-6.1-Sol","visibility":"list"},
          {"slug":"gpt-reserve","display_name":"GPT-Reserve","visibility":"hide"},
          {"slug":"gpt-6-sol","display_name":"GPT-6-Sol","visibility":"list"}
        ]}
        """

    @Test func codexModelsComeFromItsCatalogAndSkipHiddenOnes() throws {
        let names = try LocalAgent.parseModels(kind: .codexCLI, output: codexCatalog)
        #expect(names == ["gpt-6.1-sol", "gpt-6-sol"])
    }

    /// The real shape `pi --list-models` prints: a header row, then one row per model. pi takes
    /// `provider/id`, which is the only unambiguous form when two providers share a model name.
    @Test func piModelsPairTheProviderWithTheModel() throws {
        let table = """
            provider  model            context  max-out  thinking  images
            deepseek  deepseek-flash   1M       384K     yes       yes
            deepseek  deepseek-v4-pro  1M       384K     yes       no
            """
        let names = try LocalAgent.parseModels(kind: .piCLI, output: table)
        #expect(names == ["deepseek/deepseek-flash", "deepseek/deepseek-v4-pro"])
    }

    /// Claude Code only takes an alias or a full name, so its model stays free-form rather than being
    /// guessed at from a list this app would have to invent.
    @Test func claudeCodeOffersNoModelList() throws {
        #expect(try LocalAgent.parseModels(kind: .claudeCode, output: "anything").isEmpty)
        #expect(LocalAgentKind.claudeCode.modelListArguments == nil)
        #expect(LocalAgentKind.codexCLI.modelListArguments == ["debug", "models"])
        #expect(LocalAgentKind.piCLI.modelListArguments == ["--list-models"])
    }

    @Test func anUnreadableCatalogIsALocalAgentFailure() {
        #expect(throws: ModelError.localAgent("the model catalog is unreadable")) {
            try LocalAgent.parseModels(kind: .codexCLI, output: "not json")
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

    @Test func theSystemPromptFileIsWrittenForPi() async throws {
        let directory = LocalAgent.temporaryDirectory()
        let invocation = LocalAgentInvocation(
            executable: executable, arguments: ["-c", "cat system.txt"], stdin: "",
            directory: directory, writesSystemPromptFile: true, systemPrompt: "SYSTEM",
            answersToFile: false, schema: nil, writesSchemaFile: false, timeout: .seconds(20))
        let answer = try await LocalAgent.spawn(invocation, environment: shellEnvironment)
        #expect(answer == "SYSTEM")
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
