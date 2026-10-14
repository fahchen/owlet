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
| 关工具与上下文 | `--tools "" --safe-mode --strict-mcp-config` | `--ignore-user-config -s read-only --disable <该版本确实有的特性> -c skills.include_instructions=false -c 'web_search="disabled"' -c include_environment_context=false -c include_permissions_instructions=false -c include_collaboration_mode_instructions=false` |
| 用户级配置 | 由 `--safe-mode` 全部跳过，**保留登录态** | `--ignore-user-config` 不读 `config.toml`（因此没有用户的 MCP 服务器与 hooks），**登录态仍从 `auth.json` 读** |
| 系统提示词通道 | `--system-prompt` 参数 | `-c model_instructions_file=<0600 文件>`，与原文分开 |
| 原文通道 | 标准输入 | 标准输入 |
| 结果读取 | 标准输出 | `--output-last-message <文件>` |
| 响应 Schema | `--json-schema <json>` | `--output-schema <文件>` |
| 思考强度 | `--effort` | `-c model_reasoning_effort=` |
| 不落盘会话 | `--no-session-persistence` | `--ephemeral` |

Codex 额外需要 `--skip-git-repo-check`（空目录不是仓库）与 `-C <空目录>`；两者的工作目录都设成同一个一次性空目录。

Claude Code 还拿一句**应用自己的**短指令作为位置参数（`Answer the request provided on standard input…`），真正的负载仍走标准输入：它的文档只说「管道输入会附加到提示词」，没有承诺没有提示词时把标准输入当成提示词；这句话不含用户内容，`ps` 里看到它没有关系。Codex 用 `-` 明确要求从标准输入读提示词。

真实调用暴露过四处 Codex 细节（2026-10-13 实测 codex 0.160.1）：`codex exec` 不接受 `--ask-for-approval`（那是顶层选项，子命令直接以 exit 2 拒绝），审批策略改用 `-c approval_policy="never"`；`--ephemeral` 并不阻止用户自己配置的 hooks 在每次请求里执行，所以要显式 `--disable hooks`；思考强度的枚举里有 `none`，但模型不认——`gpt-6.1-sol` 对 `none` 返回 HTTP 400 并列出 `low／medium／high／xhigh／max`，而「关闭」正是未改动安装的默认档，所以 Codex 的关闭取最低档 `low`；`--ignore-user-config` 之外还会加载用户配置里的 **MCP 服务器**并在每次请求时连接、把它们的工具定义注入提示词——加上这个开关后实测 MCP 连接 0 次、hooks 0 次，同一条请求的 tokens 从约 3 万降到约 1.5 万。代价是**用户 `config.toml` 里的自定义 provider／模型不再生效**（登录态不受影响）。

提示词面还要再削一刀（2026-10-13 同一版本实测，单行提示词）：一条极小的请求也要预填 21,724 input tokens，其中最大的一块是 Codex 自己的编码 agent 基础指令，`-c instructions=""` 把它换成空串后降到 15,952；再关掉 18 个只增加提示词或工具／应用面的默认特性后是 13,300（只关特性为 17,518）。一次纯补全用不到它的工具、应用与浏览器面，形状又由 `--output-schema` 与应用自己的本地校验保证，所以这一刀不损失什么。`code_mode_host` 故意不关——只省两个 token，却让每条请求多一行 fail-closed 错误。

**第二轮（T65，2026-10-13，同一台 Mac，codex 0.160.1，同一份 composite 系统提示词 + 翻译 `--output-schema` + 一句英文，读 `codex exec --json` 的 `usage.input_tokens`；除非另注，exit 0、stderr 为空、答案通过契约校验）：**

| 变体 | input tokens | 墙钟 |
| --- | --- | --- |
| 上一轮配方（`instructions=""` + 18 个 `--disable`） | 13,576 / 13,578 / 13,578（逐 token 相同） | 12.2 / 12.5 / 12.4 s |
| `model_instructions_file` 取代 `instructions=""` | 13,581 | 9.5 s |
| 两者**叠加** | 13,585 | 7.6 s，**答案错**：`source` 末尾多一个换行，拼接校验失败 |
| + `skills.include_instructions=false` | 8,479（−5,099） | 11.5 s |
| + `web_search="disabled"` | 11,124（−2,452） | 12.9 s |
| + `include_collaboration_mode_instructions=false` | 13,402（−174） | 6.2 s |
| + `include_environment_context=false` | 13,457（−119） | 10.5 s |
| + `include_permissions_instructions=false` | 13,517（−59） | 11.0 s |
| + `include_apps_instructions=false` | 13,580（**Δ0，未采纳**） | 10.9 s |
| + `project_doc_max_bytes=0` | 13,586（**Δ0，未采纳**） | 11.8 s |
| + `--disable plugins／memories／tool_search_always_defer_mcp_tools` | 13,586（**Δ0，未采纳**） | 9.8 s |
| 五个 override 全开（`instructions=""` 通道） | 5,652 / 5,652 / 5,652 | 10.8 / 10.6 / 9.0 s |
| **最终配方**（五个 override + `model_instructions_file`） | 5,655 / 5,655 / 5,655 | 10.9 / 8.9 / 15.4 s |

- **五个 override 修的是一个规格违背，不只是省 token**：`spec/llm/contract.md` 要求「工具、技能、MCP、项目上下文一律关闭」，而此前把 `~/.codex/skills` 与插件缓存里的技能目录整段注入（`codex debug prompt-input` 本地渲染证实那 5,097 来自 `<skills_instructions>`）——`--disable skill_search` 只关了技能的**工具**，没关技能**说明**；`web_search="disabled"` 同理，它去掉的是一个契约本来就不许用的工具。干净 `CODEX_HOME`（只放 `auth.json`）下同一配方是 11,765（4 次相同），差额正是用户 `~/.codex` 里这些面。
- **抖动消失**：同一配方曾在 13,586 与 15,782 两态之间跳，量级与 `web_search` 工具描述相同；`web_search="disabled"` 之后 5,652／5,655 三次逐 token 相同。**确定本身就是收益**，代价为零。
- **`model_instructions_file` 按 token 中立如实记录**：本机 13,581 vs 13,578，另一台早先测到的 15,164 vs 15,780 未能复现，差额属于上面的抖动。采纳理由只有两条：它是官方文档的入口（`instructions` 已标 reserved），且把我们的提示词放进 system 位置、标准输入只留用户原文。**绝不与 `instructions=""` 叠加**。
- 墙钟仍在同一噪声区间（最终配方 8.9–15.4 s，上一轮 12.2–12.5 s，最慢一次超过 1 分钟是服务商侧排队），**不宣称提速**。`service_tier="fast"`（CLI 描述为 2× 速度、更高额度占用）在最终配方上各测 3 次：5.60／5.33／5.97 s，不带它 10.86／8.93／15.42 s，input tokens 完全相同（5,655）；样本小、两次测量未交错，**不写进配方**；用户 2026-10-13 决定默认不开。

**开关名单是自适应的（T65）：** 特性名与 `-c` 键都是**该 CLI 版本的行为**，硬编码就等于把一次 CLI 升级变成「每条请求都失败」。实测 codex 0.160.1：`--disable <该版本没有的名字>` 是硬错误（`Error: Unknown feature flag`，exit 2），`--disable` 一个 stage 为 `removed` 的名字却仍被接受；`-c` 的**未知键**被静默忽略（exit 0），但**已知键的错误取值**是硬错误（`web_search="nonsense"` → `unknown variant ... expected one of disabled, cached, indexed, live`）。因此：

- 设置页扫描时（`LocalAgent.detect` 之后、同一次「检测／切换服务商」里）跑两条**本地命令**、从不调用模型：`codex features list` 给出该版本拥有的特性名，我们想要的 18 个与之取交集；五个 `-c` override 先合并成一次 `codex features list -c …` 探测，被拒才逐个探测，只留下被接受的。
- 结果缓存进 `UserDefaults` 的 `service.agentFeatures`／`service.agentOverrides`（沿用 `service.agent*` 命名，按 provider 分表）；请求时只读缓存、不再起进程。
- **没有缓存时只发 `shell_tool`／`hooks` 两个长期存在的名字，不发任何 `-c` override**——绝不猜。扫描失败保留上一次的结果，所以失败模式永远是「这次少关几个」，而不是「请求失败」。
- 残留风险：`model_instructions_file` 未做存在性探测（它是官方入口，且探测要求文件真实存在），若未来版本移除该键，`-c` 会静默忽略它、系统提示词随之丢失；届时需要回到「合成进标准输入」的通道。这一条列入「未验证」。

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
| Codex CLI | 跑一条列举命令 `codex debug models`（跳过 `visibility: "hide"`，值取 `slug`） | 同一份目录的 `supported_reasoning_levels`，**按模型** | `--output-schema <文件>` |
| Claude Code | 读它自己缓存的目录文件 `~/.claude/cache/model-catalog/*-cc.json`（取最新一份能解析的，`catalog.config.models` 缺失或为空即忽略；值取 `id`，行文字取 `name`、退回 `short_name`） | 同一份缓存里每个模型的 `thinking.effort_options`，**按模型**（`type: "none"` 视为完全不推理） | `--json-schema <json>` |

模型名做成下拉，第一项是「该 agent 自己的默认模型」——对 CLI 来说留空是一个真实选择，不是漏填。两条清单来源都是本地的、不经过模型，所以打开设置页读一次很便宜。**两者的失败形状不同，应用也如实区分**：Codex 的列举命令会当场回答，读不成是一次可以就地提示并重试的失败；Claude Code 读的是一份别的程序写的缓存，读不到只说明「现在没有清单」，该行退回自由填写的文本框、已保存的值一动不动，从不弹出错误。已保存但清单里没有的模型名仍然可选。

**Claude Code 的清单不是官方接口**：`~/.claude/cache/model-catalog/` 是 CLI 为自己的模型菜单抓取后落盘的缓存，没有文档承诺它的路径、文件名或字段。所以这份解析的**唯一契约是「读不出来就等于没有」**——目录不存在、文件为空、形状变了、`models` 为空，全部返回空清单并走自由填写；`--model` 送出的仍是缓存条目自己的 `id`，与手输模型名走同一条路。残留风险：缓存格式随版本变化或被清掉时，按模型的能力数据消失，退回自由填写与静态值域，功能不中断。（2026-10-14 复核：同一份缓存仍读出同样的 12 个模型；这些 `id` 是否会被 `--model` 真实接受尚未验证——周配额未恢复，见文末「未验证」。）

应用侧把这份能力吃到请求里（评审 E2）：设置页扫描时记住每个模型声明的值域（`service.agentEfforts`），请求时读回放进 `ModelRequest.supportedEfforts`——强度只在该模型接受的集合里就近取较低档，**模型完全不支持推理时一个参数都不发**。设置页在强度行下就地显示「该模型支持：…」或「该模型不使用思考强度」。实测（2026-10-13）codex 0.160.1 的 7 个可见模型都给出 `low,medium,high,max`；Claude Code 的最新缓存（`86008f99-…-cc.json`，同日）列出 12 个模型，其中 11 个带 `thinking.type: "effort"`（有的到 `xhigh`、有的只到 `high`），`claude-haiku-4-5-20251001` 是 `type: "none"`，所以两个 agent 现在都有按模型的数据。

图片与流式是后续需求（评审 E3），本轮不预建抽象：`ModelTurn` 将来加内容分片（文本今天、图片以后），由各 backend 各自映射；`ModelBackend` 在 `complete` 旁边加一个带默认实现的流式方法。两处都是局部改动。

## 备选与不采纳
- **HTTP shim**：本地起一个常驻小服务，把 CLI 包成 `/v1/chat/completions`，应用零改动。不采纳：多一个要用户自己管的常驻进程，超时、取消与调试页都退化，而且「谁在用」变得不清楚。
- **保留「OpenAI 风格 body 即请求 IR」**：改动更小，但请求值只能通过一个假的 `URLRequest` 断言，且本地 agent 必须伪造一层响应外壳；评审要求统一抽象后改为 §3 的两层结构。
- **Claude Code 的 `--bare`**：看着更干净，但它规定 auth 只能是 `ANTHROPIC_API_KEY` 或 apiKeyHelper，**不读 OAuth 与 keychain**——正好废掉「用订阅登录」这个前提，因此用 `--safe-mode` 加显式开关代替。
- **让 agent 带着工具跑**：会读写用户文件，延迟与不确定性不可接受。
- **长驻 RPC**（`codex app-server`）：省启动开销、能流式输出，但要处理进程生命周期与协议版本漂移；留作后续。
- **一个可自由编辑的命令行模板**：最灵活，但没有可校验的能力开关，用户写错只能得到「运行失败」；两个具名服务商各自配好参数更符合既有 `Provider` 的写法。

## 后果与已知风险

- CLI 参数是各 agent 的版本行为，升级后可能变化；缓解手段是探测版本号、把 agent 的 stderr 带进失败提示、**特性名与 `-c` override 逐版本扫描后缓存**（见 §2），并保留人工验收。
- **Claude Code 的模型清单来自它自己的缓存文件，不是接口**（见 §9）：路径、文件名与字段都没有文档承诺，格式一变或缓存被清掉，模型下拉与按模型强度就退回自由填写与静态值域。失败模式是「少一份清单」，不会让请求失败。
- 延迟高于 HTTP 服务，但没有想象中严重：两三句翻译实测 codex 6.7 秒，查词 7.5 秒（本机 2026-10-13）。学习与查词会各自再起一个进程，同时在跑的进程限 2 个。加上 `--ignore-user-config` 后 codex 的同一请求从约 3 万 tokens 降到约 1.5 万（不再注入用户 MCP 服务器的工具定义）；再削掉 Codex 自己的基础指令、技能说明与 web_search 面后约 5.7k（见 §2）。Claude Code 的延迟仍未测到：两次复核都在模型调用前被周配额挡下（见文末「未验证」）。
- **Codex 的 `--ignore-user-config` 有代价**：用户 `config.toml` 里配置的自定义 provider 与模型不再生效，应用只用它的内置默认（登录态照旧）。用自定义网关的用户会遇到这一条。
- **不启用 App Sandbox 才能用**：受沙箱约束的应用无法执行用户本机的 CLI。这与 [规范范围边界](../../README.md) 里「本机签名自用，不启用 App Sandbox」一致；若将来上架并启用沙箱，这两个服务商要么移除，要么改走用户显式授权的路径。
- 未验证：**Claude Code 的真实返回**——2026-10-13 与 2026-10-14 两次真人复核都撞上周配额未恢复，最近一次（`claude 2.1.296`，2026-10-14 21:18 JST）实测报错 `本地 agent 运行失败：exit 1: You've hit your weekly limit · resets 5am (Asia/Tokyo)`（提示写在标准输出、标准错误为空；文案比 10-13 记录的少了日期），所以既没有真实译文，也没有确认缓存里的 id 与 `--effort low` 在模型侧被接受。命令行本身被 2.1.296 接受——参数被拒会是 exit 2——**所以 `--json-schema` 只验证到「参数被收下」，它是否真的约束了输出仍未知**。Claude Code 的模型缓存（§9）在 2026-10-13／10-14 两次读到的都是同一份 `86008f99-…-cc.json`：12 个模型、11 个带 `thinking.type: "effort"`，但字段含义与它自己菜单的对应关系未经官方确认；各 CLI 后续版本对上述参数的兼容性；`service_tier="fast"` 只各测 3 次（见 §2，样本小；用户已决定默认不开）；`model_instructions_file` 被未来版本移除时会静默失效（见 §2 末的残留风险）。
