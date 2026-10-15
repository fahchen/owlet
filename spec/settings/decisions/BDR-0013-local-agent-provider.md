[English](BDR-0013-local-agent-provider.md) · [简体中文](BDR-0013-local-agent-provider.zh-CN.md)

# BDR-0013: Local agent CLIs as model services

Status: Implemented (T61, 2026-10-12). Origin: user request to "support local agent CLIs as an LLM provider", later narrowed to Claude Code and Codex CLI only.

The scope is only "how a single model request reaches the model". The JSON contract, local validation, correction retry, write-back, and the behavior of learning and lookup are all unchanged; see the [LLM contract](../../llm/contract.md).

## User value and motivation

Users who already pay for a local agent (subscription login or their own provider configuration) do not need to obtain an API Key or buy the same quota twice. Source text and translations do not leave the machine for a second service; the user only has to trust the agent they are already logged in to.

The value only holds when "the user already has an agent installed and logged in on this machine". For people without one, it adds an option that reports missing configuration when chosen, which is not a regression: both new providers are extra options, and the default is still OpenAI Compatible.

## Decision

### 1. A local agent is a "one-shot plain completion backend", not a coding agent

For each request the app starts a process, asks for one answer, then ends it. **Tools, skills, MCP, project context, and session persistence are all off**; the working directory is a throwaway empty directory, and the sandbox is read-only (Codex). Reason: each time the app wants "one JSON object", whereas a coding agent reads the user's repository, runs commands, and writes files. That is not what the user wants, and the latency and unpredictability are unacceptable.

### 2. Two recipes

| | Claude Code | Codex CLI |
| --- | --- | --- |
| Executable | `claude` | `codex` |
| Disable tools and context | `--tools "" --safe-mode --strict-mcp-config` | `--ignore-user-config -s read-only --disable <features this version actually has> -c skills.include_instructions=false -c 'web_search="disabled"' -c include_environment_context=false -c include_permissions_instructions=false -c include_collaboration_mode_instructions=false` |
| User-level config | All skipped by `--safe-mode`, **login is kept** | `--ignore-user-config` does not read `config.toml` (so no user MCP servers or hooks); **login is still read from `auth.json`** |
| System prompt channel | `--system-prompt` argument | `-c model_instructions_file=<0600 file>`, separate from the source text |
| Source text channel | Standard input | Standard input |
| Reading the result | Standard output | `--output-last-message <file>` |
| Response schema | `--json-schema <json>` | `--output-schema <file>` |
| Reasoning effort | `--effort` | `-c model_reasoning_effort=` |
| No session persistence | `--no-session-persistence` | `--ephemeral` |

Codex additionally needs `--skip-git-repo-check` (the empty directory is not a repository) and `-C <empty directory>`; both agents use the same throwaway empty directory as working directory.

Claude Code also receives a short instruction **of the app's own** as a positional argument (`Answer the request provided on standard input…`), while the real payload still goes through standard input. Its documentation only says "piped input is appended to the prompt" and does not promise that standard input becomes the prompt when no prompt is given. That sentence contains no user content, so seeing it in `ps` is harmless. Codex uses `-` to explicitly read the prompt from standard input.

Real calls exposed four Codex details (measured 2026-10-13, codex 0.160.1): `codex exec` does not accept `--ask-for-approval` (that is a top-level option; the subcommand rejects it with exit 2), so the approval policy uses `-c approval_policy="never"` instead. `--ephemeral` does not stop the user's own configured hooks from running on every request, so `--disable hooks` is explicit. The reasoning effort enum includes `none`, but the model does not accept it: `gpt-6.1-sol` returns HTTP 400 for `none` and lists `low / medium / high / xhigh / max`, and "off" is exactly the default level of an unmodified install, so Codex's "off" takes the lowest level `low`. Without `--ignore-user-config`, the **MCP servers** in the user config are loaded, connected on every request, and their tool definitions injected into the prompt. With this flag, measurements showed 0 MCP connections and 0 hooks, and tokens for the same request dropped from about 30k to about 15k. The cost: **custom providers / models in the user's `config.toml` no longer apply** (login is unaffected).

The prompt surface needed another cut (measured 2026-10-13, same version, a one-line prompt): even a tiny request prefilled 21,724 input tokens. The largest block was Codex's own coding agent base instructions; `-c instructions=""` replaced them with an empty string and brought it to 15,952. Turning off 18 more default features that only add prompt text or tool / app surface brought it to 13,300 (turning off only the features gave 17,518). A plain completion needs none of its tools, apps, or browser surface, and the shape is guaranteed by `--output-schema` and the app's own local validation, so nothing is lost. `code_mode_host` is deliberately left on: it saves only two tokens but adds a fail-closed error line to every request.

**Second round (T65, 2026-10-13, same Mac, codex 0.160.1, same composite system prompt + translation `--output-schema` + one English sentence, reading `usage.input_tokens` from `codex exec --json`; unless noted otherwise, exit 0, empty stderr, and the answer passed contract validation):**

| Variant | input tokens | Wall clock |
| --- | --- | --- |
| Previous recipe (`instructions=""` + 18 × `--disable`) | 13,576 / 13,578 / 13,578 (identical token for token) | 12.2 / 12.5 / 12.4 s |
| `model_instructions_file` instead of `instructions=""` | 13,581 | 9.5 s |
| Both **stacked** | 13,585 | 7.6 s, **wrong answer**: an extra trailing newline in `source`, concatenation check failed |
| + `skills.include_instructions=false` | 8,479 (−5,099) | 11.5 s |
| + `web_search="disabled"` | 11,124 (−2,452) | 12.9 s |
| + `include_collaboration_mode_instructions=false` | 13,402 (−174) | 6.2 s |
| + `include_environment_context=false` | 13,457 (−119) | 10.5 s |
| + `include_permissions_instructions=false` | 13,517 (−59) | 11.0 s |
| + `include_apps_instructions=false` | 13,580 (**Δ0, not adopted**) | 10.9 s |
| + `project_doc_max_bytes=0` | 13,586 (**Δ0, not adopted**) | 11.8 s |
| + `--disable plugins / memories / tool_search_always_defer_mcp_tools` | 13,586 (**Δ0, not adopted**) | 9.8 s |
| All five overrides on (`instructions=""` channel) | 5,652 / 5,652 / 5,652 | 10.8 / 10.6 / 9.0 s |
| **Final recipe** (five overrides + `model_instructions_file`) | 5,655 / 5,655 / 5,655 | 10.9 / 8.9 / 15.4 s |

- **The five overrides fix a spec violation, not just token cost**: `spec/llm/contract.md` requires "tools, skills, MCP, and project context are all off", yet the skills directories in `~/.codex/skills` and the plugin cache were injected wholesale (local rendering with `codex debug prompt-input` confirmed those 5,097 came from `<skills_instructions>`). `--disable skill_search` only turned off the skill **tool**, not the skill **instructions**. `web_search="disabled"` is the same: it removes a tool the contract never allowed. With a clean `CODEX_HOME` (only `auth.json`), the same recipe gives 11,765 (4 identical runs); the difference is exactly these surfaces in the user's `~/.codex`.
- **The jitter is gone**: the same recipe used to flip between two states, 13,586 and 15,782, a gap the size of the `web_search` tool description. After `web_search="disabled"`, three runs gave 5,652 / 5,655 identical token for token. **Determinism is itself the gain**, at zero cost.
- **`model_instructions_file` is recorded honestly as token-neutral**: 13,581 vs 13,578 on this machine; an earlier 15,164 vs 15,780 on another machine could not be reproduced, and the gap belongs to the jitter above. It is adopted for two reasons only: it is the officially documented entry (`instructions` is marked reserved), and it puts our prompt in the system position, leaving standard input for the user's source text only. **Never stack it with `instructions=""`**.
- Wall clock stays within the same noise range (final recipe 8.9 to 15.4 s, previous round 12.2 to 12.5 s; the slowest run, over a minute, was queueing on the vendor side), so **no speedup is claimed**. `service_tier="fast"` (described by the CLI as 2× speed with higher quota use) was measured 3 times on the final recipe: 5.60 / 5.33 / 5.97 s, versus 10.86 / 8.93 / 15.42 s without it, with identical input tokens (5,655). The sample is small and the two sets were not interleaved, so **it is not part of the recipe**; on 2026-10-13 the user decided it is off by default.

**The flag list is adaptive (T65):** feature names and `-c` keys are **behavior of a given CLI version**, and hardcoding them turns a CLI upgrade into "every request fails". Measured on codex 0.160.1: `--disable <a name this version lacks>` is a hard error (`Error: Unknown feature flag`, exit 2), while `--disable` with a name whose stage is `removed` is still accepted. **Unknown keys** in `-c` are silently ignored (exit 0), but **a bad value for a known key** is a hard error (`web_search="nonsense"` → `unknown variant ... expected one of disabled, cached, indexed, live`). Therefore:

- When the settings page scans (after `LocalAgent.detect`, in the same "detect / switch provider" pass), it runs two **local commands** and never calls the model: `codex features list` gives the feature names this version has, intersected with the 18 we want; the five `-c` overrides are first probed together in one `codex features list -c …`, and only if that is rejected is each probed individually, keeping only the accepted ones.
- Results are cached in `UserDefaults` as `service.agentFeatures` / `service.agentOverrides` (following the `service.agent*` naming, one table per provider); requests only read the cache and start no extra process.
- **Without a cache, only the two long-lived names `shell_tool` / `hooks` are sent, and no `-c` override at all**. Never guess. A failed scan keeps the previous result, so the failure mode is always "fewer things turned off this time", never "the request fails".
- Residual risk: `model_instructions_file` is not probed for existence (it is the official entry, and probing requires the file to actually exist). If a future version removes the key, `-c` will silently ignore it and the system prompt will be lost; then we would need to go back to the "merge into standard input" channel. This is listed under "Unverified".

Reasoning effort follows "levels map per model; an unsupported level takes the nearest lower one": Claude Code's levels are `low / medium / high / xhigh / max` with no off level, so "Off" takes the lowest level; Codex's value range is the same (see above), so "Off" also takes `low`. "Automatic" never sends the parameter.
Providers whose levels can be queried use **their own list**: every model in Codex's `codex debug models` carries `supported_reasoning_levels`, and the app maps per model from it (an unsupported level takes the nearest lower level within that model; when the model does not support reasoning at all the parameter is not sent). Claude Code has no list at all, so "per model" is real data on Codex and a static table on Claude Code.

### 3. Unified abstraction: one request value, delivered by each provider

Request and delivery are split into two layers (the user's 2026-10-13 review asked to "unify the abstraction, then implement each provider separately"):

- `ModelRequest` is the app's **only request value**: model name, system prompt, a number of `ModelTurn`s (user / assistant), response format, reasoning effort.
- `ModelBackend` is the delivery, implemented per provider: `OpenAICompatibleBackend` builds an OpenAI-style body and POSTs it; `LocalAgentBackend` translates it into command-line arguments and standard input.
- Request construction (`translationRequest` / `learningRequest` / `lookupRequest` / `fillMeaning`) only produces a `ModelRequest`, so it can be asserted directly without going through a fake `URLRequest`.

A local agent's answer is the text the process outputs. It has no vendor envelope, so **we no longer fake a chat envelope and then decode it** (the conclusion of review D2). Truncation, refusal, and empty content are judged by the HTTP backend in its own envelope; empty output from a local agent is simply empty content.

`ServiceConfig` still carries a `baseURL`, which a local agent never requests: it is only an input to the HTTP backend, not part of the request value.

### 4. Structured output uses whatever is available

An agent that can constrain the response shape uses its flag (the conclusion of review D11): Codex writes a schema file and passes `--output-schema`, Claude Code passes `--json-schema <json>`. DeepSeek, which only supports `json_object`, has no such flag, so it takes the same path as other providers that do not accept a schema: the shape is written in the prompt. Both local agents accept a schema.

On unsupported providers, local validation is not relaxed at all: `ModelRequest.format` only says "can this provider be constrained"; validation, correction, and the write-back decision are independent of it. Measured on codex 0.160.1 + `--output-schema`: with the same `$defs.result` schema it returned JSON in the contract shape directly, with sentence pairs correct down to trailing spaces in `source`.

**Update 2026-10-15 (T75)**: for HTTP vendors this capability is now carried by `ServicePreset` from [BDR-0015](BDR-0015-provider-presets.md) and reaches the request through `ServiceConfig.supportsJSONSchema`. Local agents still take the protocol default from `Provider` (both accept a schema), so this section's conclusions for them are unchanged.

### 5. No API Key needed

Configuration completeness changes from "a Key is in Keychain" to "the executable exists and is executable". The model name may be left empty, meaning the agent's own default model. Keychain is not involved for local agents and gets no extra entry because of them.

### 6. Bounded resources and time

Default timeout is 180 seconds (HTTP services have no such limit, but a local agent process must be reclaimable). At most 2 agent processes run at once; the rest queue, because one translation plus one learning request plus one lookup each start a process, and a Node-based CLI alone takes hundreds of MB. When the user cancels, the child process is terminated.

### 7. Privacy boundary

User source text always goes through standard input and **never into command-line arguments** (`ps` is visible to other processes on the same machine). Temporary files that must be written (standard input and Codex's schema / answer) are written with 0600 into a throwaway directory and deleted with the directory after use. The debug page records the actual command line and prompt; the command line never contained the source text, and the record contains no keys. Non-zero exit, timeout, and not executable are all classified as the connection failure `ModelError.localAgent`, and the message includes the agent's own error output: standard error first, falling back to standard output when that is empty, because Claude Code writes quota messages to standard output and reading only standard error would give just "exit 1: ".

### 8. Executable path

An absolute path is stored per provider (a GUI app launched from Finder has a `PATH` of only `/usr/bin:/bin:/usr/sbin:/sbin`, while these two CLIs are usually installed elsewhere by a package manager and do not run at all without extending `PATH`). The "Detect" button in settings searches using the user's own shell (the three fallback layers are in §10), then verifies with `--version` and shows the version number. CLI flags are version behavior, so on failure it must be obvious which version is installed.

The settings page actively scans every time it opens: **local agents always appear in the provider list**. One that cannot be found is labeled "not detected" and stays selectable, and a separator splits remote services and local agents into two groups. Selecting an agent searches for it right away: if found, the path is filled in and the version shown, without first clicking "Detect"; "Detect" is just a manual retry. A path the user picked by hand is not overwritten by a scan, except when it is no longer executable, in which case the scan result is used. Agents that cannot be found stay in the list because users can only choose what they can see: manually choosing the executable is the only way out when the app cannot guess (see §10).

### 9. Queryable capabilities are provided per provider

Each provider provides what it can (the conclusion of review D4), and the app does not invent anything for it:

| | Model list | Effort list | Structured output |
| --- | --- | --- | --- |
| Codex CLI | Run the listing command `codex debug models` (skip `visibility: "hide"`, value from `slug`) | `supported_reasoning_levels` from the same catalog, **per model** | `--output-schema <file>` |
| Claude Code | Read its own cached catalog file `~/.claude/cache/model-catalog/*-cc.json` (take the newest one that parses; ignore it if `catalog.config.models` is missing or empty; value from `id`, row label from `name`, falling back to `short_name`) | `thinking.effort_options` of each model in the same cache, **per model** (`type: "none"` means no reasoning at all) | `--json-schema <json>` |

The model name is a dropdown whose first item is "the agent's own default model": for a CLI, leaving it empty is a real choice, not an omission. Both list sources are local and do not go through the model, so reading once when settings open is cheap. **Their failure shapes differ, and the app distinguishes them honestly**: Codex's listing command answers on the spot, so a failed read is a failure that can be shown in place and retried. Claude Code reads a cache written by another program, so failing to read it only means "no list right now": that row falls back to a free-form text field, the saved value stays untouched, and no error is ever shown. A saved model name that is not in the list remains selectable.

**Claude Code's list is not an official interface**: `~/.claude/cache/model-catalog/` is a cache the CLI fetches and writes for its own model menu, and no documentation promises its path, file name, or fields. So the **only contract of this parsing is "unreadable means absent"**: a missing directory, an empty file, a changed shape, or empty `models` all return an empty list and use free-form entry. `--model` still sends the cache entry's own `id`, the same path as a typed model name. Residual risk: when the cache format changes across versions or the cache is cleared, the per-model capability data disappears and falls back to free-form entry and the static value range; the feature keeps working. (Rechecked 2026-10-14: the same cache still yields the same 12 models; whether these `id`s are actually accepted by `--model` is not yet verified because the weekly quota had not reset; see "Unverified" at the end.)

The app feeds these capabilities into requests (review E2): when settings scan, the value range each model declares is remembered (`service.agentEfforts`) and read back into `ModelRequest.supportedEfforts` at request time. Effort picks the nearest lower level only within the set the model accepts, and **when the model does not support reasoning at all, no parameter is sent**. The settings page shows "This model supports: …" or "This model does not use reasoning effort" right under the effort row. Measured (2026-10-13): the 7 visible models of codex 0.160.1 all give `low,medium,high,max`; Claude Code's newest cache (`86008f99-…-cc.json`, same day) lists 12 models, 11 of them with `thinking.type: "effort"` (some up to `xhigh`, some only up to `high`), and `claude-haiku-4-5-20251001` is `type: "none"`. So both agents now have per-model data.

Images and streaming are later needs (review E3), and no abstraction is pre-built this round: `ModelTurn` will later gain content parts (text today, images later), mapped by each backend; `ModelBackend` will gain a streaming method with a default implementation next to `complete`. Both are local changes.

### 10. Lookup environment and three fallback layers (why keep the login shell, why fall back to an interactive shell, why keep undetected rows)

**Measured (2026-10-14, a second machine, user `philc`, claude 2.1.299 at `~/.local/bin/claude` → `~/.local/share/claude/versions/2.1.299`):** an app launched from Finder inherits the minimal `PATH` `/usr/bin:/bin:/usr/sbin:/sbin`; `env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin /bin/zsh -lc 'command -v claude'` gives **exit 1, empty stdout, empty stderr**; the same command in an ssh session on the same machine gives exit 0 and 30 bytes of stdout. The root cause is confirmed, not guessed: `export PATH="$HOME/.local/bin:$PATH"` is written only in `~/.zshrc:5`, and `zsh -lc` (login + non-interactive) **reads only `.zprofile` / `.zlogin`, not `.zshrc`**. The ssh session succeeds only because its `PATH` already contains `~/.local/bin`, which `zsh -l` inherits as is. Adding `/opt/homebrew/bin` and `/usr/local/bin` to `PATH` **does not help** either (`minimal+brew` still exits 1), so this cannot be fully solved by "adding a few more directories".

So lookup has three layers, each falling back to the next:

1. **Give the lookup a usable environment**: `PATH` starts from the app's current value and appends the standard install directories, then runs `command -v` in a login shell. This layer lets `zsh`'s own profile use Homebrew tools, and lets `command -v` at least see CLIs in those directories.
2. **Interactive login shell**: when `zsh -lc` fails, fall back to `zsh -ilc`. `.zshrc` is read only by interactive shells, and this machine's `PATH` happens to be set only there. When `-lc` succeeds this layer is skipped, so normal machines do not pay for a slower probe that may print a banner. An interactive rc may print banners, warnings, or prompts, so parsing takes the **last non-empty line**, trimmed, and **does not assume the whole stdout is the path**.
3. **Direct check without a shell**: after both shells fail, check in order `~/.local/bin`, `~/.claude/local`, `~/.local/share/mise/shims`, `~/.asdf/shims`, `/opt/homebrew/bin` and `sbin`, `/usr/local/bin` and `sbin`, `/usr/bin`, `/bin`, `/usr/sbin`, `/sbin`, and `~/.nvm/versions/node/*/bin` (only this one known root is enumerated, never the whole home directory), taking the first executable.

**Single source of truth**: this directory list is written once in `AgentEnvironment.fallbackDirectories(home:)` (the nvm enumeration sits next to it). The login shell's `PATH`, the agent process's `PATH`, and the direct-check fallback all read it. The lookup itself goes through an injectable `AgentLookup` seam, so tests run no real shell and do not walk the developer's real directories.

Costs and trade-offs:

- **Why keep the login shell lookup**: users may install a CLI in a custom directory and expose it only through their own shell configuration; guessing only fixed locations would miss those installs. The first two layers are exactly "follow the user's own shell".
- **Why fall back to an interactive shell, and its cost**: it is slower than `-lc` and runs rc code meant only for interactive use. So it **only runs after the first layer fails**, with a 20-second timeout; normal machines are not affected at all.
- **Why the direct check lists only known directories**: recursing the home directory has unbounded cost; the price is that very unusual custom installs are still not found, and then the next layer is the fallback.
- **Why undetected agents no longer vanish from the list**: users can only choose what they can see. When not found, the row is labeled "not detected", with the existing `Choose…` file picker next to it, and a hand-picked path is not overwritten by later scans (§8). This is the only way out when the app cannot guess.

## Alternatives rejected
- **HTTP shim**: run a resident local service that wraps the CLI as `/v1/chat/completions`, with zero app changes. Rejected: one more resident process for the user to manage, timeouts, cancellation, and the debug page all degrade, and "who is using it" becomes unclear.
- **Keep "OpenAI-style body as the request IR"**: a smaller change, but the request value could only be asserted through a fake `URLRequest`, and local agents would have to fake a response envelope. After the review asked for a unified abstraction it became the two-layer structure in §3.
- **Claude Code's `--bare`**: looks cleaner, but it restricts auth to `ANTHROPIC_API_KEY` or apiKeyHelper and **does not read OAuth or the keychain**, which kills the premise of "log in with a subscription". So `--safe-mode` plus explicit flags is used instead.
- **Let the agent run with tools**: it would read and write user files; the latency and unpredictability are unacceptable.
- **Long-lived RPC** (`codex app-server`): saves startup cost and can stream, but requires handling process lifecycle and protocol version drift; left for later.
- **A freely editable command-line template**: the most flexible, but with no verifiable capability flags a user mistake can only produce "run failed"; two named providers, each with its own configured flags, fit the existing `Provider` approach better.

## Consequences and known risks

- CLI flags are each agent's version behavior and may change after an upgrade. Mitigations: probe the version number, include the agent's stderr in failure messages, **scan and cache feature names and `-c` overrides per version** (see §2), and keep manual acceptance.
- **Claude Code's model list comes from its own cache file, not an interface** (see §9): path, file name, and fields have no documented promise. If the format changes or the cache is cleared, the model dropdown and per-model effort fall back to free-form entry and the static value range. The failure mode is "one list fewer", never a failed request.
- Latency is higher than HTTP services, but not as bad as feared: translating two or three sentences measured 6.7 seconds with codex, lookup 7.5 seconds (this machine, 2026-10-13). Learning and lookup each start another process, with at most 2 running at once. After adding `--ignore-user-config`, the same codex request dropped from about 30k tokens to about 15k (user MCP server tool definitions are no longer injected); after also cutting Codex's own base instructions, skill instructions, and the web_search surface, it is about 5.7k (see §2). Claude Code's latency is still unmeasured: both rechecks were blocked by the weekly quota before the model call (see "Unverified" at the end).
- **Codex's `--ignore-user-config` has a cost**: custom providers and models configured in the user's `config.toml` no longer apply; the app only uses its built-in defaults (login unchanged). Users of a custom gateway will hit this.
- **Only usable without App Sandbox**: a sandboxed app cannot run CLIs on the user's machine. This matches "signed locally for personal use, App Sandbox not enabled" in the [spec scope boundary](../../README.md). If the app is ever distributed with the sandbox on, these two providers must either be removed or go through a path the user explicitly authorizes.
- Unverified: **Claude Code's real responses**. Both human rechecks on 2026-10-13 and 2026-10-14 hit a weekly quota that had not reset. The latest (`claude 2.1.296`, 2026-10-14 21:18 JST) reported `The local agent failed: exit 1: You've hit your weekly limit · resets 5am (Asia/Tokyo)` (the message is on standard output, standard error empty; the text lacks the date that the 10-13 record had). So there is neither a real translation nor confirmation that the cached ids and `--effort low` are accepted on the model side. The command line itself was accepted by 2.1.296 (rejected flags would give exit 2), **so `--json-schema` is only verified as "flag accepted"; whether it actually constrains output is still unknown**. Claude Code's model cache (§9) read the same `86008f99-…-cc.json` on both 2026-10-13 and 10-14: 12 models, 11 with `thinking.type: "effort"`, but how the fields relate to its own menu is not officially confirmed. Also unverified: compatibility of later CLI versions with the flags above; `service_tier="fast"` was measured only 3 times each (see §2, small sample; the user decided it is off by default); `model_instructions_file` would silently stop working if a future version removes it (see the residual risk at the end of §2).
