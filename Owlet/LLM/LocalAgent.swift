import Darwin
import Foundation

/// A local agent CLI the app can drive as its model service (BDR-0013). Its tools, skills, MCP servers
/// and project context are all switched off: the app wants one answer to one prompt, not a session.
enum LocalAgentKind: String, CaseIterable, Sendable {
    case claudeCode, codexCLI, piCLI

    /// The executable a normal install provides; the settings pane looks this name up on `PATH`.
    var executableName: String {
        switch self {
        case .claudeCode: "claude"
        case .codexCLI: "codex"
        case .piCLI: "pi"
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
        switch self {
        case .claudeCode, .codexCLI:
            [.off: "low", .low: "low", .medium: "medium", .high: "high", .max: "max"]
        // pi clamps the level to the model's own range itself, and does have `off`.
        case .piCLI: [.off: "off", .low: "low", .medium: "medium", .high: "high", .max: "max"]
        }
    }

    /// The command that lists the model names this agent can reach, or nil when it has none. Claude
    /// Code only takes an alias (`sonnet`) or a full name and offers no way to enumerate them, so its
    /// model stays free-form rather than guessed at from a list this app would have to invent.
    var modelListArguments: [String]? {
        switch self {
        case .claudeCode: nil
        // The catalog as JSON, which is where the slugs and the visibility of each model live.
        case .codexCLI: ["debug", "models"]
        // A table with one row per model, `provider  model  context  max-out  thinking  images`.
        case .piCLI: ["--list-models"]
        }
    }

    /// How this agent takes a response schema, or nil when it takes none: `pi` can only be told the
    /// shape in the prompt, and it says so itself (`--mode json` is an event stream, not a constraint).
    enum SchemaDelivery: Sendable {
        case file
        case argument
    }

    var schemaDelivery: SchemaDelivery? {
        switch self {
        case .codexCLI: .file
        case .claudeCode: .argument
        case .piCLI: nil
        }
    }

    func effortValue(_ level: EffortLevel) -> String? {
        guard level != .automatic, let start = EffortLevel.ordered.firstIndex(of: level) else {
            return nil
        }
        let table = effortValues
        for index in stride(from: start, through: 0, by: -1) {
            if let value = table[EffortLevel.ordered[index]] { return value }
        }
        return nil
    }
}

/// One planned CLI call: what to run, with which arguments, and what to write to its stdin. Every path
/// is inside `directory`, and nothing here touches the file system, so each recipe is directly testable.
struct LocalAgentInvocation: Sendable, Equatable {
    var executable: URL
    var arguments: [String]
    var stdin: String
    var directory: URL
    /// `pi` reads its system prompt from a file; the others take it as an argument or on stdin.
    var writesSystemPromptFile: Bool
    var systemPrompt: String
    /// `codex` writes its final message where `--output-last-message` points instead of to stdout.
    var answersToFile: Bool
    /// The response schema, when this agent takes one.
    var schema: Data?
    /// `codex` reads the schema from a file; `claude` takes it as an argument.
    var writesSchemaFile: Bool
    var timeout: Duration

    var stdinFile: URL { directory.appending(path: "stdin.txt") }
    var schemaFile: URL { directory.appending(path: "schema.json") }
    var systemPromptFile: URL { directory.appending(path: "system.txt") }
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
/// The three agents differ only in how a prompt is handed over and how the answer comes back, so those
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
                directory: Self.temporaryDirectory(), timeout: timeout))
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
            directory: Self.temporaryDirectory(), timeout: timeout)
        return """
            $ \(invocation.executable.path) \(invocation.arguments.joined(separator: " "))
            --- the prompt below is written to the process's standard input ---
            \(invocation.stdin)
            """
    }

    /// The recipe for one kind: the switches that turn an agent into a plain completion service, how the
    /// behavior prompt travels, and where the answer appears.
    ///
    /// The user's text never reaches the command line — arguments are visible to every process on the
    /// machine through `ps` — so it is always written to the process's standard input; `pi` gets the
    /// system prompt through a 0600 file for the same reason.
    static func plan(
        kind: LocalAgentKind, executable: URL, request: ModelRequest, directory: URL, timeout: Duration
    ) -> LocalAgentInvocation {
        let prompt = request.turns.map(\.content).joined(separator: "\n\n")
        // Only an agent that takes a schema carries one: an invocation describes what this agent will
        // actually be given, and pi can only be told the shape in the prompt.
        let schema = kind.schemaDelivery == nil ? nil : schemaData(request.format)
        let invocation = LocalAgentInvocation(
            executable: executable, arguments: [], stdin: prompt, directory: directory,
            writesSystemPromptFile: kind == .piCLI, systemPrompt: request.system,
            answersToFile: kind == .codexCLI, schema: schema,
            writesSchemaFile: schema != nil && kind.schemaDelivery == .file, timeout: timeout)
        var arguments = arguments(
            kind: kind, model: request.model, effort: request.effort, invocation: invocation)
        // Codex reads its prompt from stdin only when it is given no prompt argument, and `-` says so
        // explicitly; the other two take the payload as context, so they need a short positional prompt
        // to make it the thing to answer. That sentence is the app's own words, so `ps` may show it.
        arguments.append(kind == .codexCLI ? "-" : Self.stdinInstruction)
        return LocalAgentInvocation(
            executable: executable, arguments: arguments,
            stdin: stdin(kind: kind, system: request.system, prompt: prompt), directory: directory,
            writesSystemPromptFile: invocation.writesSystemPromptFile, systemPrompt: request.system,
            answersToFile: invocation.answersToFile, schema: schema,
            writesSchemaFile: invocation.writesSchemaFile, timeout: timeout)
    }

    /// The response schema this provider can accept, if any. `json_object` means the shape travels in
    /// the prompt, so there is nothing to pass on the command line.
    private static func schemaData(_ format: ModelResponseFormat) -> Data? {
        guard case .jsonSchema(_, let schema) = format else { return nil }
        return schema
    }

    private static func arguments(
        kind: LocalAgentKind, model: String, effort: EffortLevel, invocation: LocalAgentInvocation
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
            arguments = [
                "exec", "--ephemeral", "--skip-git-repo-check", "--sandbox", "read-only",
                "--ignore-user-config", "--config", "approval_policy=\"never\"",
                "--disable", "shell_tool", "--disable", "hooks",
                "--cd", invocation.directory.path,
                "--output-last-message", invocation.answerFile.path,
            ]
            if invocation.schema != nil { arguments += ["--output-schema", invocation.schemaFile.path] }
        case .piCLI:
            arguments = [
                "--print", "--no-tools", "--no-extensions", "--no-mcp", "--no-skills",
                "--no-prompt-templates", "--no-context-files", "--no-session", "--no-approve",
                "--system-prompt", invocation.systemPromptFile.path,
            ]
        }
        if !model.isEmpty { arguments += ["--model", model] }
        if let value = kind.effortValue(effort) {
            switch kind {
            case .claudeCode: arguments += ["--effort", value]
            // Quoted, because `-c` parses the value as TOML; the quotes make it a string for certain.
            case .codexCLI: arguments += ["--config", "model_reasoning_effort=\"\(value)\""]
            case .piCLI: arguments += ["--thinking", value]
            }
        }
        return arguments
    }

    /// Codex has no system-prompt switch, so it gets the two composed into one prompt.
    private static func stdin(kind: LocalAgentKind, system: String, prompt: String) -> String {
        kind == .codexCLI && !system.isEmpty ? system + "\n\n" + prompt : prompt
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
    /// prompt and — when this agent wants them — the system prompt file and the response schema, then
    /// removed however it ends.
    static func withPreparedDirectory<T: Sendable>(
        _ invocation: LocalAgentInvocation, _ body: (LocalAgentInvocation) async throws -> T
    ) async throws -> T {
        try FileManager.default.createDirectory(
            at: invocation.directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: invocation.directory) }
        try write(invocation.stdin, to: invocation.stdinFile, permissions: 0o600)
        if invocation.writesSystemPromptFile {
            try write(invocation.systemPrompt, to: invocation.systemPromptFile, permissions: 0o600)
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
    /// The model names this agent offers, in its own order, for the settings pane's picker. A listing
    /// command is local — it never reaches a model — so opening the pane stays cheap.
    static func models(_ kind: LocalAgentKind, executable: URL) async throws -> [String] {
        guard let arguments = kind.modelListArguments else { return [] }
        let invocation = LocalAgentInvocation(
            executable: executable, arguments: arguments, stdin: "",
            directory: temporaryDirectory(), writesSystemPromptFile: false, systemPrompt: "",
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

    /// Reads each agent's own listing format. Pure, so the fixtures in the tests are the real shapes
    /// these two commands print.
    static func parseModels(kind: LocalAgentKind, output: String) throws -> [String] {
        switch kind {
        case .claudeCode: []
        case .codexCLI: try codexModels(output)
        case .piCLI: piModels(output)
        }
    }

    /// `codex debug models` prints the catalog as JSON. A model the picker should not offer is marked
    /// `visibility: "hide"`; `--model` takes the slug.
    private static func codexModels(_ output: String) throws -> [String] {
        guard let data = output.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let models = object["models"] as? [[String: Any]]
        else { throw ModelError.localAgent("the model catalog is unreadable") }
        return models.compactMap { model in
            guard model["visibility"] as? String != "hide", let slug = model["slug"] as? String,
                !slug.isEmpty
            else { return nil }
            return slug
        }
    }

    /// `pi --list-models` prints a table whose first two columns are the provider and the model. pi
    /// takes either the bare id or `provider/id`, and only the paired form is unambiguous when two
    /// providers offer a model of the same name.
    private static func piModels(_ output: String) -> [String] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let columns = line.split(whereSeparator: \.isWhitespace)
            guard columns.count >= 2, columns[0] != "provider" else { return nil }
            return "\(columns[0])/\(columns[1])"
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
            directory: temporaryDirectory(), writesSystemPromptFile: false, systemPrompt: "",
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
            directory: temporaryDirectory(), writesSystemPromptFile: false, systemPrompt: "",
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
/// `/usr/bin:/bin:/usr/sbin:/sbin`, but `pi` is a Node script whose shebang is `/usr/bin/env node`, so
/// the directories a login shell would have must be added or the CLI cannot start at all.
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
            stdin: "", directory: LocalAgent.temporaryDirectory(), writesSystemPromptFile: false,
            systemPrompt: "", answersToFile: false, schema: nil, writesSchemaFile: false, timeout: .seconds(10))
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
