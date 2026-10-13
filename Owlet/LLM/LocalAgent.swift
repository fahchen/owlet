import Darwin
import Foundation

/// A local agent CLI the app can drive as its model service (BDR-0013). Its tools, skills, MCP servers
/// and project context are all switched off: the app wants one answer to one prompt, not a session.
enum LocalAgentKind: String, CaseIterable, Sendable {
    case claudeCode, codexCLI

    /// The executable a normal install provides; the settings pane looks this name up on `PATH`.
    var executableName: String {
        switch self {
        case .claudeCode: "claude"
        case .codexCLI: "codex"
        }
    }

    /// The value this agent's own effort switch accepts per UI level. `自动` sends nothing at all; a
    /// level the agent does not offer is sent as the nearest lower one, as with every other provider.
    ///
    /// Neither Claude Code nor Codex has a way to switch thinking off, so 关闭 becomes the lowest level
    /// they accept — the same treatment GPT-6 Astra gets. Codex's enum also has `none`, but the models
    /// behind it do not: `gpt-6.1-sol` answers HTTP 400 `Unsupported value: 'none'` and lists
    /// `low／medium／high／xhigh／max`, and 关闭 is what an untouched install asks for.
    var effortValues: [EffortLevel: String] {
        [.off: "low", .low: "low", .medium: "medium", .high: "high", .max: "max"]
    }

    /// The command that lists the model names this agent can reach, or nil when it has none. Claude
    /// Code only takes an alias (`sonnet`) or a full name and offers no way to enumerate them, so its
    /// model stays free-form rather than guessed at from a list this app would have to invent.
    var modelListArguments: [String]? {
        switch self {
        case .claudeCode: nil
        // The catalog as JSON, which is where the slugs and the visibility of each model live.
        case .codexCLI: ["debug", "models"]
        }
    }

    /// How this agent takes a response schema.
    enum SchemaDelivery: Sendable {
        case file
        case argument
    }

    var schemaDelivery: SchemaDelivery {
        switch self {
        case .codexCLI: .file
        case .claudeCode: .argument
        }
    }

    /// The value to send for this level. `supported` is what the agent said this model accepts: nil
    /// means it said nothing (the static table decides), an empty list means the model does not reason
    /// at all, so no parameter is sent.
    func effortValue(_ level: EffortLevel, supported: [EffortLevel]? = nil) -> String? {
        guard level != .automatic, let start = EffortLevel.ordered.firstIndex(of: level) else {
            return nil
        }
        let table = effortValues
        let available = supported ?? EffortLevel.ordered
        // Walk down to the nearest level this model takes; below its lowest, that lowest is sent.
        for index in stride(from: start, through: 0, by: -1) {
            let candidate = EffortLevel.ordered[index]
            if available.contains(candidate), let value = table[candidate] { return value }
        }
        guard let lowest = EffortLevel.ordered.first(where: available.contains) else { return nil }
        return table[lowest]
    }
}

/// The Codex feature switches the app wants off, and how that list survives a CLI upgrade (BDR-0013 §2).
///
/// `--disable` with a name the installed build does not have exits 2 and fails the whole request, while
/// a name whose stage is `removed` is still accepted. So no name is taken on faith: the settings scan
/// reads that build's own `codex features list`, and a request only ever sends what it reported.
enum CodexFeatures {
    /// What one completion never needs, in the order it is sent. A name the installed build does not
    /// report is dropped instead of being sent and rejected.
    static let desired = [
        "shell_tool", "hooks", "apps", "auth_elicitation", "browser_use", "browser_use_external",
        "browser_use_full_cdp_access", "computer_use", "image_generation", "in_app_browser",
        "multi_agent", "skill_mcp_dependency_install", "skill_search", "sleep_tool", "shell_snapshot",
        "tool_call_mcp_elicitation", "tool_suggest", "view_image",
    ]

    /// What a request sends when no scan has run yet: two names every recent build has carried.
    static let fallback = ["shell_tool", "hooks"]

    /// The `-c` overrides that drop prompt sections a one-shot completion never uses, in the order they
    /// are sent. The first two carry the weight: `skills.include_instructions=false` stops this build
    /// from injecting the whole skill catalog of `~/.codex/skills` and its plugin caches, and
    /// `web_search="disabled"` drops a tool the contract forbids anyway. Each is kept only when this
    /// build accepts it — `web_search` takes an enum, and a value it does not know fails the whole
    /// request — so an override is never sent on faith.
    static let overrides = [
        "skills.include_instructions=false",
        "web_search=\"disabled\"",
        "include_environment_context=false",
        "include_permissions_instructions=false",
        "include_collaboration_mode_instructions=false",
    ]

    /// The names a listing reports. `codex features list` prints `name  stage  enabled` per line, so the
    /// first field is the name and the rest is that build's own state, which this app does not read.
    static func parse(_ listing: String) -> [String] {
        listing.split(whereSeparator: \.isNewline).compactMap {
            $0.split(whereSeparator: \.isWhitespace).first.map(String.init)
        }
    }

    /// What this build has of what we want, in the order we want to send it.
    static func intersect(desired: [String] = desired, available: [String]) -> [String] {
        let known = Set(available)
        return desired.filter(known.contains)
    }

    /// What one request sends: the scan's answer once there is one, otherwise the long-lived fallback.
    static func sendable(cached: [String]?) -> [String] { cached ?? fallback }
}

/// One planned CLI call: what to run, with which arguments, and what to write to its stdin. Every path
/// is inside `directory`, and nothing here touches the file system, so each recipe is directly testable.
struct LocalAgentInvocation: Sendable, Equatable {
    var executable: URL
    var arguments: [String]
    var stdin: String
    var directory: URL
    /// The behavior prompt: Claude Code takes it as `--system-prompt`, Codex reads it from a file.
    var systemPrompt: String
    /// `codex` writes its final message where `--output-last-message` points instead of to stdout.
    var answersToFile: Bool
    /// The response schema, when this agent takes one.
    var schema: Data?
    /// `codex` reads the schema from a file; `claude` takes it as an argument.
    var writesSchemaFile: Bool
    /// Whether the behavior prompt goes into `instructionsFile`. Codex reads `model_instructions_file`,
    /// which is what keeps our prompt in the system position instead of concatenated onto the user's
    /// turn; Claude Code takes `--system-prompt` instead, so no file is written for it.
    var writesInstructionsFile: Bool = false
    var timeout: Duration

    var stdinFile: URL { directory.appending(path: "stdin.txt") }
    var schemaFile: URL { directory.appending(path: "schema.json") }
    /// Where `-c model_instructions_file` points; written 0600 beside the prompt, deleted with the rest.
    var instructionsFile: URL { directory.appending(path: "instructions.txt") }
    var stdoutFile: URL { directory.appending(path: "stdout.txt") }
    var stderrFile: URL { directory.appending(path: "stderr.txt") }
    var answerFile: URL { directory.appending(path: "answer.txt") }
}

/// Why a local agent process could not deliver an answer. Kept apart from `ModelError` so the process
/// plumbing stays the only thing that produces them; `LocalAgent` maps them at the boundary.
enum AgentProcessError: Error, Equatable {
    case timedOut
    case notStarted(String)
}

/// What 「检测」 found when it went looking for an agent, or why it found nothing. A plain optional
/// would leave the settings pane with nothing to say about a lookup that failed.
enum AgentDetection: Sendable, Equatable {
    case found(executable: URL, version: String)
    case failed(String)
}

/// The local agent backend: one process per request, the final answer, and nothing else.
///
/// The two agents differ only in how a prompt is handed over and how the answer comes back, so those
/// differences are a recipe here, and everything else — the JSON contract, the corrective round, the
/// debug page, cancellation — is shared with the HTTP providers.
struct LocalAgent: Sendable {
    /// Runs one invocation and returns the agent's final text. Injectable, so the test suite never
    /// spawns a real agent and never reaches a real model.
    var run: @Sendable (LocalAgentInvocation) async throws -> String = LocalAgent.spawn
    /// A CLI is far slower than an HTTP call, but a hung process must not hold a request open forever.
    var timeout: Duration = .seconds(180)

    /// The URL the shared request builders need. A local agent is never reached over HTTP, so nothing
    /// ever requests it; it exists because the OpenAI-style body is the app's one request IR.
    static let unusedBaseURL = URL(string: "http://local-agent.invalid/v1") ?? URL(fileURLWithPath: "/")

    /// The positional prompt the agents that take one are given. It is what makes the payload on standard
    /// input the thing to answer; the user's own text never appears here, so `ps` shows nothing private.
    static let stdinInstruction =
        "Answer the request provided on standard input, following the system instructions exactly."
}

extension LocalAgent {
    /// One request through the agent: run the CLI and return the text it produced. The text is the
    /// answer as it stands — an agent has no provider envelope, so nothing wraps it.
    func complete(kind: LocalAgentKind, request: ModelRequest, config: ServiceConfig) async throws -> String {
        guard let executable = config.agentExecutable else {
            throw ModelError.localAgent("no executable is set")
        }
        let answer = try await run(
            Self.plan(
                kind: kind, executable: executable, request: request,
                directory: Self.temporaryDirectory(), timeout: timeout,
                features: config.agentFeatures, overrides: config.agentOverrides))
        // An agent with nothing to say is an empty reply, not a broken contract. It has to fail here:
        // a `.format` failure is correctable, and the app would spend a second process asking the model
        // to fix an answer it never gave.
        guard !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ModelError.emptyResponse
        }
        return answer
    }

    /// The command that would run, for the debug page: a one-shot agent's request *is* its command
    /// line, and the request value alone would not show which agent was asked or with which switches.
    func command(kind: LocalAgentKind, request: ModelRequest, config: ServiceConfig) -> String? {
        guard let executable = config.agentExecutable else { return nil }
        let invocation = Self.plan(
            kind: kind, executable: executable, request: request,
            directory: Self.temporaryDirectory(), timeout: timeout,
            features: config.agentFeatures, overrides: config.agentOverrides)
        var shown = """
            $ \(invocation.executable.path) \(invocation.arguments.joined(separator: " "))
            --- the prompt below is written to the process's standard input ---
            \(invocation.stdin)
            """
        // Codex never sees the behavior prompt in its argument list or on standard input, so without
        // this the debug page would show the request with its instructions missing.
        if invocation.writesInstructionsFile, !invocation.systemPrompt.isEmpty {
            shown += """
                --- the behavior prompt below is written to \(invocation.instructionsFile.path) ---
                \(invocation.systemPrompt)
                """
        }
        return shown
    }

    /// The recipe for one kind: the switches that turn an agent into a plain completion service, how the
    /// behavior prompt travels, and where the answer appears.
    ///
    /// The user's text never reaches the command line — arguments are visible to every process on the
    /// machine through `ps` — so it is always written to the process's standard input.
    static func plan(
        kind: LocalAgentKind, executable: URL, request: ModelRequest, directory: URL,
        timeout: Duration, features: [String]? = nil, overrides: [String]? = nil
    ) -> LocalAgentInvocation {
        let prompt = request.turns.map(\.content).joined(separator: "\n\n")
        // Only a `json_schema` request carries one: a `json_object` shape travels in the prompt, so
        // there is nothing to put on the command line.
        let schema = schemaData(request.format)
        let invocation = LocalAgentInvocation(
            executable: executable, arguments: [], stdin: prompt, directory: directory,
            systemPrompt: request.system,
            answersToFile: kind == .codexCLI, schema: schema,
            writesSchemaFile: schema != nil && kind.schemaDelivery == .file,
            writesInstructionsFile: kind == .codexCLI, timeout: timeout)
        var arguments = arguments(
            kind: kind, model: request.model, effort: request.effort,
            supported: request.supportedEfforts, features: features, overrides: overrides,
            invocation: invocation)
        // Codex reads its prompt from stdin only when it is given no prompt argument, and `-` says so
        // explicitly; Claude Code takes the payload as context, so it needs a short positional prompt
        // to make it the thing to answer. That sentence is the app's own words, so `ps` may show it.
        arguments.append(kind == .codexCLI ? "-" : Self.stdinInstruction)
        // Standard input is the user's turn alone for both agents: Claude Code takes the behavior
        // prompt as `--system-prompt` and Codex reads it from `model_instructions_file`, so neither
        // has it concatenated onto the text being processed.
        return LocalAgentInvocation(
            executable: executable, arguments: arguments,
            stdin: prompt, directory: directory,
            systemPrompt: request.system,
            answersToFile: invocation.answersToFile, schema: schema,
            writesSchemaFile: invocation.writesSchemaFile,
            writesInstructionsFile: invocation.writesInstructionsFile, timeout: timeout)
    }

    /// The response schema this provider can accept, if any. `json_object` means the shape travels in
    /// the prompt, so there is nothing to pass on the command line.
    private static func schemaData(_ format: ModelResponseFormat) -> Data? {
        guard case .jsonSchema(_, let schema) = format else { return nil }
        return schema
    }

    private static func arguments(
        kind: LocalAgentKind, model: String, effort: EffortLevel, supported: [EffortLevel]?,
        features: [String]?, overrides: [String]?, invocation: LocalAgentInvocation
    ) -> [String] {
        var arguments: [String]
        switch kind {
        case .claudeCode:
            arguments = [
                "--print", "--tools", "", "--safe-mode", "--strict-mcp-config",
                "--no-session-persistence", "--system-prompt", invocation.systemPrompt,
            ]
            if let schema = invocation.schema, kind.schemaDelivery == .argument {
                arguments += ["--json-schema", String(decoding: schema, as: UTF8.self)]
            }
        case .codexCLI:
            // `codex exec` takes no approval switch of its own — `--ask-for-approval` is a top-level
            // option and the subcommand rejects it with exit 2 — so the policy goes through `-c`.
            // `--ignore-user-config` is what keeps the user's own MCP servers out of a translation
            // request: without it codex contacts them on every run and puts their tools in the prompt
            // (measured on codex 0.160.1: about 30k tokens with, about 15k without).
            //
            // Neither the feature names nor the `-c` overrides are hard-coded into the command line:
            // both come from what the settings scan read out of this build (BDR-0013 §2). A
            // `--disable` name this build lacks exits 2, so an old cache or no cache at all costs
            // flags, never the request. `code_mode_host` is deliberately left on: it saves two tokens
            // and makes every run print a fail-closed error.
            arguments = [
                "exec", "--ephemeral", "--skip-git-repo-check", "--sandbox", "read-only",
                "--ignore-user-config", "--config", "approval_policy=\"never\"",
            ]
            for feature in CodexFeatures.sendable(cached: features) {
                arguments += ["--disable", feature]
            }
            for override in overrides ?? [] {
                arguments += ["--config", override]
            }
            // The behavior prompt goes into the system position rather than being concatenated onto
            // the user's turn; `instructions` is a reserved key and is deliberately not combined with
            // this — together they make the model read the instruction text as the source.
            arguments += [
                "--config", "model_instructions_file=\"\(invocation.instructionsFile.path)\"",
                "--cd", invocation.directory.path,
                "--output-last-message", invocation.answerFile.path,
            ]
            if invocation.schema != nil { arguments += ["--output-schema", invocation.schemaFile.path] }
        }
        if !model.isEmpty { arguments += ["--model", model] }
        if let value = kind.effortValue(effort, supported: supported) {
            switch kind {
            case .claudeCode: arguments += ["--effort", value]
            // Quoted, because `-c` parses the value as TOML; the quotes make it a string for certain.
            case .codexCLI: arguments += ["--config", "model_reasoning_effort=\"\(value)\""]
            }
        }
        return arguments
    }

    static func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "owlet-agent-\(UUID().uuidString)")
    }
}

extension LocalAgent {
    /// The live runner: the user's login shell contributes the `PATH`, which a GUI app launched from
    /// Finder does not inherit.
    static func spawn(_ invocation: LocalAgentInvocation) async throws -> String {
        let environment = await AgentEnvironment.shared.value(for: invocation.executable)
        return try await spawn(invocation, environment: environment)
    }

    /// The runner with an explicit environment, so a test can run a real `/bin/sh` without asking the
    /// user's login shell for anything.
    static func spawn(_ invocation: LocalAgentInvocation, environment: [String: String]) async throws -> String {
        try await AgentGate.shared.withSlot {
            try await withPreparedDirectory(invocation) { prepared in
                let output = try await runProcess(prepared, environment: environment)
                guard output.status == 0 else {
                    // Not every CLI explains itself on standard error: Claude Code prints a quota message
                    // on standard output and exits 1, which would otherwise read as "exit 1: " with
                    // nothing after it.
                    let explained = tail(output.stderr).isEmpty ? tail(output.stdout) : tail(output.stderr)
                    throw ModelError.localAgent("exit \(output.status): \(explained)")
                }
                let answer = prepared.answersToFile ? read(prepared.answerFile) : output.stdout
                return answer.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }

    /// The one place that prepares a directory for one call: created empty and private, written with the
    /// prompt and — when this agent takes one — the response schema, then removed however it ends.
    static func withPreparedDirectory<T: Sendable>(
        _ invocation: LocalAgentInvocation, _ body: (LocalAgentInvocation) async throws -> T
    ) async throws -> T {
        try FileManager.default.createDirectory(
            at: invocation.directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: invocation.directory) }
        try write(invocation.stdin, to: invocation.stdinFile, permissions: 0o600)
        if invocation.writesInstructionsFile {
            try write(invocation.systemPrompt, to: invocation.instructionsFile, permissions: 0o600)
        }
        if invocation.writesSchemaFile, let schema = invocation.schema {
            try write(String(decoding: schema, as: UTF8.self), to: invocation.schemaFile, permissions: 0o600)
        }
        return try await body(invocation)
    }

    /// Starts one process and reads back what it produced. Standard output and error go to files rather
    /// than to pipes: nothing can then deadlock on a full pipe, and a killed process still leaves what it
    /// had already written.
    static func runProcess(
        _ invocation: LocalAgentInvocation, environment: [String: String]
    ) async throws -> (status: Int32, stdout: String, stderr: String) {
        try Task.checkCancellation()
        for file in [invocation.stdoutFile, invocation.stderrFile] {
            guard
                FileManager.default.createFile(
                    atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600])
            else { throw ModelError.localAgent("the output files could not be created") }
        }
        let process = Process()
        process.executableURL = invocation.executable
        process.arguments = invocation.arguments
        process.currentDirectoryURL = invocation.directory
        process.environment = environment
        let stdin = try FileHandle(forReadingFrom: invocation.stdinFile)
        let stdout = try FileHandle(forWritingTo: invocation.stdoutFile)
        let stderr = try FileHandle(forWritingTo: invocation.stderrFile)
        defer {
            try? stdin.close()
            try? stdout.close()
            try? stderr.close()
        }
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        let child = AgentProcess(process)
        let status: Int32
        do {
            status = try await child.wait(timeout: invocation.timeout)
        } catch let error as AgentProcessError {
            switch error {
            case .timedOut:
                throw ModelError.localAgent(
                    "no answer within \(invocation.timeout.components.seconds) seconds")
            case .notStarted(let detail):
                throw ModelError.localAgent(detail)
            }
        }
        return (status, read(invocation.stdoutFile), read(invocation.stderrFile))
    }

    private static func write(_ text: String, to url: URL, permissions: Int) throws {
        guard
            FileManager.default.createFile(
                atPath: url.path, contents: Data(text.utf8),
                attributes: [.posixPermissions: permissions])
        else { throw ModelError.localAgent("\(url.lastPathComponent) could not be written") }
    }

    private static func read(_ url: URL) -> String {
        guard let data = try? Data(contentsOf: url) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    /// The end of an agent's error output, on one line, for a failure message a person has to read.
    static func tail(_ text: String, limit: Int = 400) -> String {
        let collapsed = text.split(whereSeparator: \.isNewline).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return collapsed.count <= limit ? collapsed : "…" + String(collapsed.suffix(limit))
    }
}

extension LocalAgent {
    /// What the installed Codex has and accepts, read where the settings pane already looks the CLI up
    /// (BDR-0013 §2): the feature names it reports, and the `-c` overrides it does not reject. Only
    /// local commands — no model is ever called — so one request never pays for this. nil means the
    /// listing itself could not be read; a caller then keeps whatever it already had.
    static func codexScan(executable: URL) async -> (features: [String], overrides: [String])? {
        guard let listing = try? await scanOutput(executable, arguments: ["features", "list"]),
            listing.status == 0
        else { return nil }
        // One combined probe settles the common case; only a build that rejects something pays for
        // asking about the overrides one at a time, and a rejected one is simply not sent.
        let combined = ["features", "list"] + CodexFeatures.overrides.flatMap { ["-c", $0] }
        var accepted: [String]
        if let probe = try? await scanOutput(executable, arguments: combined), probe.status == 0 {
            accepted = CodexFeatures.overrides
        } else {
            accepted = []
            for override in CodexFeatures.overrides {
                let arguments = ["features", "list", "-c", override]
                guard let probe = try? await scanOutput(executable, arguments: arguments),
                    probe.status == 0
                else { continue }
                accepted.append(override)
            }
        }
        return (CodexFeatures.intersect(available: CodexFeatures.parse(listing.stdout)), accepted)
    }

    /// One scan command and what it printed. The prepared directory and the login-shell environment are
    /// the same ones a real request uses, so the scan sees the CLI the request will run.
    private static func scanOutput(
        _ executable: URL, arguments: [String]
    ) async throws -> (status: Int32, stdout: String) {
        let invocation = LocalAgentInvocation(
            executable: executable, arguments: arguments, stdin: "",
            directory: temporaryDirectory(), systemPrompt: "",
            answersToFile: false, schema: nil, writesSchemaFile: false, timeout: .seconds(20))
        let environment = await AgentEnvironment.shared.value(for: executable)
        let output = try await withPreparedDirectory(invocation) {
            try await runProcess($0, environment: environment)
        }
        return (status: output.status, stdout: output.stdout)
    }

    /// The models this agent offers, in its own order, with what the agent says each one accepts. A
    /// listing command is local — it never reaches a model — so opening the pane stays cheap.
    static func models(_ kind: LocalAgentKind, executable: URL) async throws -> [ModelOption] {
        guard let arguments = kind.modelListArguments else { return [] }
        let invocation = LocalAgentInvocation(
            executable: executable, arguments: arguments, stdin: "",
            directory: temporaryDirectory(), systemPrompt: "",
            answersToFile: false, schema: nil, writesSchemaFile: false, timeout: .seconds(60))
        let environment = await AgentEnvironment.shared.value(for: executable)
        let output = try await withPreparedDirectory(invocation) {
            try await runProcess($0, environment: environment)
        }
        guard output.status == 0 else {
            throw ModelError.localAgent("exit \(output.status): \(tail(output.stderr))")
        }
        return try parseModels(kind: kind, output: output.stdout)
    }

    /// Reads each agent's own listing format. Pure, so the fixture in the tests is the real shape this
    /// command prints.
    static func parseModels(kind: LocalAgentKind, output: String) throws -> [ModelOption] {
        switch kind {
        case .claudeCode: []
        case .codexCLI: try codexModels(output)
        }
    }

    /// `codex debug models` prints the catalog as JSON. A model the picker should not offer is marked
    /// `visibility: "hide"`; `--model` takes the slug, and the same entry carries the levels the model
    /// accepts.
    private static func codexModels(_ output: String) throws -> [ModelOption] {
        guard let data = output.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let models = object["models"] as? [[String: Any]]
        else { throw ModelError.localAgent("the model catalog is unreadable") }
        return models.compactMap { model in
            guard model["visibility"] as? String != "hide", let slug = model["slug"] as? String,
                !slug.isEmpty
            else { return nil }
            return ModelOption(
                id: slug, label: model["display_name"] as? String,
                efforts: codexEfforts(model["supported_reasoning_levels"]))
        }
    }

    /// The levels one catalogue entry accepts, in the app's own levels. An entry without the key says
    /// nothing, so the static table stays in charge; a present but empty list means the model does not
    /// reason at all, and then no effort parameter may be sent.
    private static func codexEfforts(_ raw: Any?) -> [EffortLevel]? {
        guard let levels = raw as? [[String: Any]] else { return nil }
        let named = levels.compactMap { $0["effort"] as? String }.compactMap(effortLevel)
        return EffortLevel.allCases.filter { named.contains($0) }
    }

    /// The app level a CLI effort name stands for. `none` is the only real off, and a level weaker than
    /// `low` is the app's lowest reasoning level.
    static func effortLevel(_ name: String) -> EffortLevel? {
        switch name {
        case "none": .off
        case "minimal", "low": .low
        case "medium": .medium
        case "high": .high
        case "xhigh", "max", "ultra": .max
        default: nil
        }
    }
}

extension LocalAgent {
    /// The executable the user's login shell would run for this agent, or nil when this machine has
    /// none. It asks the CLI nothing, because the settings pane scans with it every time it opens.
    static func locate(_ kind: LocalAgentKind) async -> URL? {
        let invocation = LocalAgentInvocation(
            executable: URL(fileURLWithPath: "/bin/zsh"),
            arguments: ["-lc", "command -v \(kind.executableName)"], stdin: "",
            directory: temporaryDirectory(), systemPrompt: "",
            answersToFile: false, schema: nil, writesSchemaFile: false, timeout: .seconds(20))
        let output = try? await withPreparedDirectory(invocation) {
            try await runProcess($0, environment: ProcessInfo.processInfo.environment)
        }
        guard let output, output.status == 0 else { return nil }
        let path = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// Looks the agent up the way the user's login shell would, then asks it for its version. A GUI app
    /// cannot find these CLIs by itself, and the version is what tells a later failure apart from a
    /// parameter this release of the CLI no longer accepts.
    static func detect(_ kind: LocalAgentKind) async -> AgentDetection {
        let environment = ProcessInfo.processInfo.environment
        guard let executable = await locate(kind) else {
            return .failed(
                L10n.shared.string(
                    "%@ was not found on the login shell's PATH.", kind.executableName))
        }
        let version = LocalAgentInvocation(
            executable: executable, arguments: ["--version"], stdin: "",
            directory: temporaryDirectory(), systemPrompt: "",
            answersToFile: false, schema: nil, writesSchemaFile: false, timeout: .seconds(20))
        do {
            let reported = try await withPreparedDirectory(version) {
                try await runProcess($0, environment: environment)
            }
            guard reported.status == 0 else { return .failed(tail(reported.stderr)) }
            let line = reported.stdout.split(separator: "\n").first.map(String.init) ?? ""
            return .found(executable: executable, version: line)
        } catch {
            return .failed((error as? ModelError)?.message ?? error.localizedDescription)
        }
    }
}

/// At most `limit` agent processes at once: one translation plus its learning request plus a lookup
/// would otherwise start three CLIs, and a Node-based one is over a hundred megabytes.
actor AgentGate {
    static let shared = AgentGate(limit: 2)

    private let limit: Int
    private var running = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) { self.limit = limit }

    func withSlot<T: Sendable>(_ work: @Sendable () async throws -> T) async throws -> T {
        await acquire()
        defer { release() }
        return try await work()
    }

    private func acquire() async {
        if running < limit {
            running += 1
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    /// Hands the slot straight to the next waiter, so the count stays where it is.
    private func release() {
        if waiting.isEmpty {
            running -= 1
        } else {
            waiting.removeFirst().resume()
        }
    }
}

/// The `PATH` a child process needs. An app launched from Finder inherits only
/// `/usr/bin:/bin:/usr/sbin:/sbin`, but these CLIs are usually installed by a package manager and are
/// Node scripts (`#!/usr/bin/env node`), so the directories a login shell would have must be added or
/// the CLI cannot start at all.
actor AgentEnvironment {
    static let shared = AgentEnvironment()

    private var resolved: String?

    func value(for executable: URL) async -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let directories =
            [executable.deletingLastPathComponent().path, await loginShellPATH()]
            + Self.fallbackDirectories
        environment["PATH"] = directories.filter { !$0.isEmpty }.joined(separator: ":")
        // A CLI that decides to draw colour codes would write them into the answer it returns.
        environment["NO_COLOR"] = "1"
        environment["TERM"] = "dumb"
        return environment
    }

    /// What the user's login shell resolves, asked once: the answer cannot change while the app runs,
    /// and asking per request would add a shell spawn to every translation.
    private func loginShellPATH() async -> String {
        if let resolved { return resolved }
        let invocation = LocalAgentInvocation(
            executable: URL(fileURLWithPath: "/bin/zsh"), arguments: ["-lc", "printf %s \"$PATH\""],
            stdin: "", directory: LocalAgent.temporaryDirectory(), systemPrompt: "",
            answersToFile: false, schema: nil, writesSchemaFile: false, timeout: .seconds(10))
        let output = try? await LocalAgent.withPreparedDirectory(invocation) {
            try await LocalAgent.runProcess($0, environment: ProcessInfo.processInfo.environment)
        }
        let path = (output?.stdout ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        resolved = path
        return path
    }

    /// Enough for a standard install when the shell lookup fails: the two Homebrew prefixes and the
    /// per-user bin directory cover the usual ways these CLIs are installed.
    private static let fallbackDirectories = [
        "/opt/homebrew/bin", "/usr/local/bin", NSHomeDirectory() + "/.local/bin", "/usr/bin", "/bin",
        "/usr/sbin", "/sbin",
    ]
}

/// One started process, shared by the waiting task, the timeout and the cancellation handler.
///
/// `Process` is not `Sendable`; every path through this box is either the lock or a Foundation thread,
/// which is what makes it safe to hand to those three at once.
private final class AgentProcess: @unchecked Sendable {
    private enum Outcome { case running, exited, timedOut }

    private let process: Process
    private let lock = NSLock()
    private var outcome: Outcome = .running
    private var watchdog: Task<Void, Never>?

    init(_ process: Process) { self.process = process }

    /// Starts the process and waits for it. The timeout ends it and a cancelled task kills it; whichever
    /// happens first is what this returns, and the process always ends so the wait always finishes.
    func wait(timeout: Duration) async throws -> Int32 {
        let status = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Int32, Error>) in
                // The termination handler is the only resumer: it fires exactly once for a process that
                // started, whichever way the process ended.
                process.terminationHandler = { [self] finished in
                    let pending = recordExit()
                    pending?.cancel()
                    continuation.resume(returning: finished.terminationStatus)
                }
                do {
                    try process.run()
                } catch {
                    process.terminationHandler = nil
                    continuation.resume(
                        throwing: AgentProcessError.notStarted(error.localizedDescription))
                    return
                }
                startWatchdog(timeout: timeout)
            }
        } onCancel: {
            stop(force: true)
        }
        if timedOut { throw AgentProcessError.timedOut }
        try Task.checkCancellation()
        return status
    }

    private func startWatchdog(timeout: Duration) {
        let watchdog = Task { [self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            markTimedOut()
            // An agent that ignores SIGTERM must still not hold the request open forever.
            stop(force: false)
            try? await Task.sleep(for: .seconds(2))
            stop(force: true)
        }
        lock.lock()
        self.watchdog = watchdog
        lock.unlock()
    }

    /// Marks the end and returns the watchdog, so only the caller that saw the process end cancels it.
    private func recordExit() -> Task<Void, Never>? {
        lock.lock()
        defer { lock.unlock() }
        if outcome == .running { outcome = .exited }
        let pending = watchdog
        watchdog = nil
        return pending
    }

    private func markTimedOut() {
        lock.lock()
        defer { lock.unlock() }
        if outcome == .running { outcome = .timedOut }
    }

    private var timedOut: Bool {
        lock.lock()
        defer { lock.unlock() }
        return outcome == .timedOut
    }

    private func stop(force: Bool) {
        // Foundation's own answer, not the outcome: the watchdog records the timeout *before* it
        // signals, so asking the outcome would make the one call that must kill the process refuse.
        let pid = process.processIdentifier
        guard process.isRunning, pid > 0 else { return }
        if force {
            _ = Darwin.kill(pid, SIGKILL)
        } else {
            process.terminate()
        }
    }
}
