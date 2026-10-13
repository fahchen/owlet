# BDR-0013：本机 agent CLI 作为模型服务

状态：已实现（T61，2026-10-12）。来源：用户要求「支持本地的 agent CLI 作为 llm provider」，随后确定只支持 Claude Code 与 Codex CLI。

范围只涉及「一次模型请求怎么到达模型」。JSON 契约、本地校验、纠正重试、写回、学习与查词的行为都不变，见 [LLM 契约](../../llm/contract.md)。

## 用户价值与动机

已经为本机 agent 付过费的用户（订阅登录或自己的 provider 配置）不必再申请一把 API Key，也不必把同一份额度买两次。译文与原文不出本机去配置第二家服务，只需要信任用户自己已经登录的那个 agent。

价值只在「用户本机已经装好并登录了某个 agent」时成立：没装的人多出一个选了就报配置缺失的选项，不构成回退——两个新服务商都是额外选项，默认仍是 OpenAI 兼容。

## 决定

### 1. 本地 agent 是「一次性的纯补全后端」，不是编码 agent

应用每次请求起一个进程、要一次回答、然后结束它。**工具、技能、MCP、项目上下文与会话落盘一律关闭**，工作目录是一次性的空目录，沙箱只读（Codex）。理由：本应用每次要的是「一个 JSON 对象」，而编码 agent 会读用户仓库、跑命令、写文件——那既不是用户要的，延迟与不确定性也不可接受。

### 2. 两条配方

| | Claude Code | Codex CLI |
| --- | --- | --- |
| 可执行文件 | `claude` | `codex` |
| 关工具与上下文 | `--tools "" --safe-mode --strict-mcp-config` | `--ignore-user-config -s read-only --disable shell_tool --disable hooks -c instructions="" --disable <精选的工具／应用特性>` |
| 用户级配置 | 由 `--safe-mode` 全部跳过，**保留登录态** | `--ignore-user-config` 不读 `config.toml`（因此没有用户的 MCP 服务器与 hooks），**登录态仍从 `auth.json` 读** |
| 系统提示词通道 | `--system-prompt` 参数 | 与原文合成一条，走标准输入 |
| 原文通道 | 标准输入 | 标准输入 |
| 结果读取 | 标准输出 | `--output-last-message <文件>` |
| 响应 Schema | `--json-schema <json>` | `--output-schema <文件>` |
| 思考强度 | `--effort` | `-c model_reasoning_effort=` |
| 不落盘会话 | `--no-session-persistence` | `--ephemeral` |

Codex 额外需要 `--skip-git-repo-check`（空目录不是仓库）与 `-C <空目录>`；两者的工作目录都设成同一个一次性空目录。

Claude Code 还拿一句**应用自己的**短指令作为位置参数（`Answer the request provided on standard input…`），真正的负载仍走标准输入：它的文档只说「管道输入会附加到提示词」，没有承诺没有提示词时把标准输入当成提示词；这句话不含用户内容，`ps` 里看到它没有关系。Codex 用 `-` 明确要求从标准输入读提示词。

真实调用暴露过四处 Codex 细节（2026-10-13 实测 codex 0.160.1）：`codex exec` 不接受 `--ask-for-approval`（那是顶层选项，子命令直接以 exit 2 拒绝），审批策略改用 `-c approval_policy="never"`；`--ephemeral` 并不阻止用户自己配置的 hooks 在每次请求里执行，所以要显式 `--disable hooks`；思考强度的枚举里有 `none`，但模型不认——`gpt-6.1-sol` 对 `none` 返回 HTTP 400 并列出 `low／medium／high／xhigh／max`，而「关闭」正是未改动安装的默认档，所以 Codex 的关闭取最低档 `low`；`--ignore-user-config` 之外还会加载用户配置里的 **MCP 服务器**并在每次请求时连接、把它们的工具定义注入提示词——加上这个开关后实测 MCP 连接 0 次、hooks 0 次，同一条请求的 tokens 从约 3 万降到约 1.5 万。代价是**用户 `config.toml` 里的自定义 provider／模型不再生效**（登录态不受影响）。

提示词面还要再削一刀（2026-10-13 同一版本实测，单行提示词）：一条极小的请求也要预填 21,724 input tokens，其中最大的一块是 Codex 自己的编码 agent 基础指令，`-c instructions=""` 把它换成空串后降到 15,952；再关掉 18 个只增加提示词或工具／应用面的默认特性后是 13,300（只关特性为 17,518）。一次纯补全用不到它的工具、应用与浏览器面，形状又由 `--output-schema` 与应用自己的本地校验保证，所以这一刀不损失什么。清单保持精选而不是把 53 个默认特性全关：特性名随 CLI 版本变化，`--disable` 一个该版本没有的名字会让 CLI 直接 exit 2，这 18 个名字都对照过 codex 0.160.1 的 `codex features list`；`code_mode_host` 故意不关——只省两个 token，却让每条请求多一行 fail-closed 错误。

思考强度沿用「档位按模型映射、不支持时取最近的较低档」：Claude Code 的档位是 `low／medium／high／xhigh／max`，没有关闭档，`关闭` 取最低档；Codex 的开关值域相同（见上），`关闭` 也取 `low`。`自动` 一律不发送该参数。
能反查档位的 provider 用**它自己的清单**：Codex 的 `codex debug models` 每个模型都带 `supported_reasoning_levels`，应用据此按模型映射（不支持的档位取该模型内最近的较低档；模型完全不支持推理时不发送该参数）。Claude Code 没有任何清单，所以「按模型」在 Codex 上是真数据，在 Claude Code 上是静态表。

### 3. 统一抽象：一个请求值，每个服务商各自投递

请求与投递分成两层（用户 2026-10-13 评审要求「统一抽象，然后每个 provider 分别实现」）：

- `ModelRequest` 是应用**唯一的请求值**：模型名、系统提示词、若干轮 `ModelTurn`（user／assistant）、响应格式、思考强度。
- `ModelBackend` 是投递方式，每个服务商各自实现：`OpenAICompatibleBackend` 把它组建成 OpenAI 风格 body 并 POST；`LocalAgentBackend` 把它翻译成命令行参数与标准输入。
- 请求构造（`translationRequest`／`learningRequest`／`lookupRequest`／`fillMeaning`）只产出 `ModelRequest`，因此它可以直接被断言，不必再经过一个假的 `URLRequest`。

本地 agent 的答案就是进程输出的文本：它没有供应商外壳，所以**不再伪造一层 chat envelope 再解码**（这是评审 D2 的结论）。截断、拒绝与空内容由 HTTP backend 在自己的外壳里判定；本地 agent 的空输出就是空内容。

`ServiceConfig` 仍带一个 `baseURL`，而本地 agent 从不请求它：它只是 HTTP backend 的输入，不是请求值的一部分。

### 4. 结构化输出用能用的那一个

能约束响应形状的 agent 就用它的开关（评审 D11 的结论）：Codex 写一份 schema 文件并传 `--output-schema`，Claude Code 传 `--json-schema <json>`；只支持 `json_object` 的 DeepSeek 没有这类开关，所以它与其他不接受 Schema 的 provider 走同一条路——形状写在提示词里。这两个本地 agent 都接受 Schema。

未支持的 provider 上，本地校验一点都不放松：`ModelRequest.format` 只是「这个服务商能不能被约束」，校验、纠正与写回判断都与它无关。实测 codex 0.160.1 + `--output-schema`：同一份 `$defs.result` schema 下直接返回契约形状的 JSON，逐句配对连 `source` 末尾空格都对。

### 5. 不需要 API Key

配置完整性从「Keychain 里有 Key」改成「可执行文件存在且可执行」；模型名可以留空，表示用该 agent 自己的默认模型。Keychain 对本地 agent 不参与，也不会因此多写一条记录。

### 6. 有界的资源与时间

默认超时 180 秒（HTTP 服务没有这个上限，本地 agent 的进程必须能被回收）；同时在跑的 agent 进程最多 2 个，其余排队——一次翻译加一次学习加一次查词会各起一个进程，而一个 Node 版 CLI 就是上百 MB。用户取消时结束子进程。

### 7. 隐私边界

用户原文一律走标准输入，**不进命令行参数**（`ps` 对同机其他进程可见）；需要落盘的临时文件（标准输入与 Codex 的 schema／答案）都以 0600 写入一次性目录，用完连目录一起删除；调试页记下实际命令行与提示词，命令行里本来就没有原文，记录里也没有任何密钥。非零退出、超时与不可执行都归为连接类失败 `ModelError.localAgent`，提示里带上该 agent 自己的错误输出——先取标准错误，为空时退回标准输出，因为 Claude Code 把配额提示写在标准输出上、只读标准错误会得到一句「exit 1: 」。

### 8. 可执行文件路径

按服务商分别保存绝对路径（GUI 应用从 Finder 启动时 `PATH` 只有 `/usr/bin:/bin:/usr/sbin:/sbin`，而这两个 CLI 通常由包管理器装在别的目录，不补 `PATH` 根本跑不起来）。设置的「检测」走一次登录 shell 的 `command -v`，再用 `--version` 验证并显示版本号——CLI 参数属于版本行为，失败时要能一眼看出装的是哪一版。

设置页每次打开都主动扫一遍登录 shell 的 `PATH`：**没装的 agent 不出现在服务商列表里**，远程服务与本地 agent 之间用一条分隔线分成两组。选中某个 agent 时立刻找它——找得到就填好路径并显示版本，不需要先点「检测」；「检测」只是手动重来一次。用户手选的路径不会被扫描覆盖，只有在其不可执行时才改用扫描结果；有手选路径的 agent 即使不在 `PATH` 里也仍然列出，已选但已被删除的 agent 也保留在列表里，让人看到问题而不是一个空行。

### 9. 能反查的能力按 provider 各自给出

每个 provider 给出它能给出的（评审 D4 的结论），应用不替它编：

| | 模型清单 | 强度清单 | 结构化输出 |
| --- | --- | --- | --- |
| Codex CLI | `codex debug models`（跳过 `visibility: "hide"`，值取 `slug`） | 同一份目录的 `supported_reasoning_levels`，**按模型** | `--output-schema <文件>` |
| Claude Code | 无列举命令 | 无 | `--json-schema <json>` |

模型名做成下拉，第一项是「该 agent 自己的默认模型」——对 CLI 来说留空是一个真实选择，不是漏填。所有清单命令都是本地命令、不经过模型，所以打开设置页读一次很便宜；读取失败就在该行下就地提示并可重试，不改动已保存的值。Claude Code 只有别名（`sonnet` 之类）而没有列举命令；静态写死一份别名清单会随 CLI 版本过期，比自由填写更糟，所以它保持文本框。

应用侧把这份能力吃到请求里（评审 E2）：设置页扫描时记住每个模型声明的值域（`service.agentEfforts`），请求时读回放进 `ModelRequest.supportedEfforts`——强度只在该模型接受的集合里就近取较低档，**模型完全不支持推理时一个参数都不发**；Claude Code 没有这份数据，沿用静态值域。设置页在强度行下就地显示「该模型支持：…」或「该模型不使用思考强度」。实测（2026-10-13）codex 0.160.1 的 7 个可见模型都给出 `low,medium,high,max`。

图片与流式是后续需求（评审 E3），本轮不预建抽象：`ModelTurn` 将来加内容分片（文本今天、图片以后），由各 backend 各自映射；`ModelBackend` 在 `complete` 旁边加一个带默认实现的流式方法。两处都是局部改动。

## 备选与不采纳
- **HTTP shim**：本地起一个常驻小服务，把 CLI 包成 `/v1/chat/completions`，应用零改动。不采纳：多一个要用户自己管的常驻进程，超时、取消与调试页都退化，而且「谁在用」变得不清楚。
- **保留「OpenAI 风格 body 即请求 IR」**：改动更小，但请求值只能通过一个假的 `URLRequest` 断言，且本地 agent 必须伪造一层响应外壳；评审要求统一抽象后改为 §3 的两层结构。
- **Claude Code 的 `--bare`**：看着更干净，但它规定 auth 只能是 `ANTHROPIC_API_KEY` 或 apiKeyHelper，**不读 OAuth 与 keychain**——正好废掉「用订阅登录」这个前提，因此用 `--safe-mode` 加显式开关代替。
- **让 agent 带着工具跑**：会读写用户文件，延迟与不确定性不可接受。
- **长驻 RPC**（`codex app-server`）：省启动开销、能流式输出，但要处理进程生命周期与协议版本漂移；留作后续。
- **一个可自由编辑的命令行模板**：最灵活，但没有可校验的能力开关，用户写错只能得到「运行失败」；两个具名服务商各自配好参数更符合既有 `Provider` 的写法。

## 后果与已知风险

- CLI 参数是各 agent 的版本行为，升级后可能变化；缓解手段是探测版本号、把 agent 的 stderr 带进失败提示，并保留人工验收。
- 延迟高于 HTTP 服务，但没有想象中严重：两三句翻译实测 codex 6.7 秒，查词 7.5 秒（本机 2026-10-13）。学习与查词会各自再起一个进程，同时在跑的进程限 2 个。加上 `--ignore-user-config` 后 codex 的同一请求从约 3 万 tokens 降到约 1.5 万（不再注入用户 MCP 服务器的工具定义）；再削掉 Codex 自己的基础指令与工具面后约 1.3 万（见 §2）。
- **Codex 的 `--ignore-user-config` 有代价**：用户 `config.toml` 里配置的自定义 provider 与模型不再生效，应用只用它的内置默认（登录态照旧）。用自定义网关的用户会遇到这一条。
- **不启用 App Sandbox 才能用**：受沙箱约束的应用无法执行用户本机的 CLI。这与 [规范范围边界](../../README.md) 里「本机签名自用，不启用 App Sandbox」一致；若将来上架并启用沙箱，这两个服务商要么移除，要么改走用户显式授权的路径。
- 未验证：Claude Code 的真实返回（周配额用尽）、它的 `--json-schema` 是否接受这份 schema、各 CLI 后续版本对上述参数的兼容性。
