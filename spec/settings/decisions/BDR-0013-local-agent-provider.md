# BDR-0013：本机 agent CLI 作为模型服务

状态：已实现（T61，2026-10-12）。来源：用户要求「支持本地的 agent，比如 codex、pi 等来作为 llm provider」，并补充「还有 Claude Code」。

范围只涉及「一次模型请求怎么到达模型」。JSON 契约、本地校验、纠正重试、写回、学习与查词的行为都不变，见 [LLM 契约](../../llm/contract.md)。

## 用户价值与动机

已经为本机 agent 付过费的用户（订阅登录或自己的 provider 配置）不必再申请一把 API Key，也不必把同一份额度买两次。译文与原文不出本机去配置第二家服务，只需要信任用户自己已经登录的那个 agent。

价值只在「用户本机已经装好并登录了某个 agent」时成立：没装的人多出一个选了就报配置缺失的选项，不构成回退——三个新服务商都是额外选项，默认仍是 OpenAI 兼容。

## 决定

### 1. 本地 agent 是「一次性的纯补全后端」，不是编码 agent

应用每次请求起一个进程、要一次回答、然后结束它。**工具、技能、MCP、项目上下文与会话落盘一律关闭**，工作目录是一次性的空目录，沙箱只读（Codex）。理由：本应用每次要的是「一个 JSON 对象」，而编码 agent 会读用户仓库、跑命令、写文件——那既不是用户要的，延迟与不确定性也不可接受。

### 2. 三条配方

| | Claude Code | Codex CLI | pi |
| --- | --- | --- | --- |
| 可执行文件 | `claude` | `codex` | `pi` |
| 关工具与上下文 | `--tools "" --safe-mode --strict-mcp-config` | `-s read-only --disable shell_tool --disable hooks` | `--no-tools --no-extensions --no-mcp --no-skills --no-prompt-templates --no-context-files` |
| 用户级配置 | 由 `--safe-mode` 全部跳过，**保留登录态** | 不忽略用户配置；`-c approval_policy` 覆盖审批，`--disable hooks` 停掉用户自己的 hooks | `--no-approve` 忽略项目信任文件 |
| 系统提示词通道 | `--system-prompt` 参数 | 与原文合成一条，走标准输入 | `--system-prompt <文件>`（0600 临时文件） |
| 原文通道 | 标准输入 | 标准输入 | 标准输入 |
| 结果读取 | 标准输出 | `--output-last-message <文件>` | 标准输出 |
| 思考强度 | `--effort` | `-c model_reasoning_effort=` | `--thinking` |
| 不落盘会话 | `--no-session-persistence` | `--ephemeral` | `--no-session` |

Codex 额外需要 `--skip-git-repo-check`（空目录不是仓库）与 `-C <空目录>`；三者的工作目录都设成同一个一次性空目录。

Claude Code 与 pi 还各拿一句**应用自己的**短指令作为位置参数（`Answer the request provided on standard input…`），真正的负载仍走标准输入：两者的文档只说「管道输入会附加到提示词」，没有承诺没有提示词时把标准输入当成提示词；这句话不含用户内容，`ps` 里看到它没有关系。Codex 用 `-` 明确要求从标准输入读提示词。

真实调用暴露过三处 Codex 细节（2026-10-13 实测 codex 0.160.1）：`codex exec` 不接受 `--ask-for-approval`（那是顶层选项，子命令直接以 exit 2 拒绝），审批策略改用 `-c approval_policy="never"`；`--ephemeral` 并不阻止用户自己配置的 hooks 在每次请求里执行，所以要显式 `--disable hooks`；思考强度的枚举里有 `none`，但模型不认——`gpt-6.1-sol` 对 `none` 返回 HTTP 400 并列出 `low／medium／high／xhigh／max`，而「关闭」正是未改动安装的默认档，所以 Codex 的关闭取最低档 `low`。

思考强度沿用「档位按模型映射、不支持时取最近的较低档」：Claude Code 的档位是 `low／medium／high／xhigh／max`，没有关闭档，`关闭` 取最低档；Codex 的开关值域相同（见上），`关闭` 也取 `low`；pi 是 `off／minimal／low／medium／high／xhigh／max`，`关闭` 就是 `off`。`自动` 一律不发送该参数。

这三张表是**按 CLI 的档位**而不是按模型做的，因为本地 agent 的模型由它自己决定、应用甚至可以为空：某个模型只接受更窄的值域时，只有那一次请求失败（提示里带着 agent 自己的报错）。相比之下 HTTP 服务的表能按模型名细分。等真实使用暴露更多模型差异，再决定要不要给本地 agent 也加一张按模型的表。

### 3. 请求体仍是一份 JSON，agent 只是另一种投递

三个 `make…Request` 组装的 OpenAI 风格 JSON body 仍是应用**唯一的请求 IR**：本地 agent 后端从 body 里取模型名、消息与思考强度，再翻译成命令行参数与标准输入；返回的最终文本套回同一份响应外壳。因此解码、截断／拒绝／空内容的判定、结构与原文拼接校验、纠正重试、调试页都只有一条代码路径，也不需要为每个 agent 各写一套解析。

代价是一个诚实的不一致：`ServiceConfig` 仍带一个 `baseURL`，而本地 agent 从不请求它（它只是共享请求构造器的载体）。备选是引入一层 `Completion` 抽象并重写三处请求装配，收益只是命名，却要改掉十几个断言 URLRequest body 的测试，不采纳。

### 4. v1 不做结构化输出

本地 agent 一律按「只支持 `json_object`」处理：形状写在提示词里，本地校验完全不变。Codex 的 `--output-schema` 与 Claude Code 的 `--json-schema` 都能真正约束 schema，但都要按 CLI 版本与模型验证兼容性，留作后续增强，不在 v1 押注。

### 5. 不需要 API Key

配置完整性从「Keychain 里有 Key」改成「可执行文件存在且可执行」；模型名可以留空，表示用该 agent 自己的默认模型。Keychain 对本地 agent 不参与，也不会因此多写一条记录。

### 6. 有界的资源与时间

默认超时 180 秒（HTTP 服务没有这个上限，本地 agent 的进程必须能被回收）；同时在跑的 agent 进程最多 2 个，其余排队——一次翻译加一次学习加一次查词会各起一个进程，而一个 Node 版 CLI 就是上百 MB。用户取消时结束子进程。

### 7. 隐私边界

用户原文一律走标准输入，**不进命令行参数**（`ps` 对同机其他进程可见）；系统提示词文件以 0600 写入一次性目录，用完连目录一起删除；调试页记下实际命令行与提示词，命令行里本来就没有原文，记录里也没有任何密钥。非零退出、超时与不可执行都归为连接类失败 `ModelError.localAgent`，提示里带上该 agent 自己的错误输出——先取标准错误，为空时退回标准输出，因为 Claude Code 把配额提示写在标准输出上、只读标准错误会得到一句「exit 1: 」。

### 8. 可执行文件路径

按服务商分别保存绝对路径（GUI 应用从 Finder 启动时 `PATH` 只有 `/usr/bin:/bin:/usr/sbin:/sbin`，而 pi 是 `#!/usr/bin/env node`，不补 `PATH` 根本跑不起来）。设置的「检测」走一次登录 shell 的 `command -v`，再用 `--version` 验证并显示版本号——CLI 参数属于版本行为，失败时要能一眼看出装的是哪一版。

设置页每次打开都主动扫一遍登录 shell 的 `PATH`：**没装的 agent 不出现在服务商列表里**，远程服务与本地 agent 之间用一条分隔线分成两组。选中某个 agent 时立刻找它——找得到就填好路径并显示版本，不需要先点「检测」；「检测」只是手动重来一次。用户手选的路径不会被扫描覆盖，只有在其不可执行时才改用扫描结果；有手选路径的 agent 即使不在 `PATH` 里也仍然列出，已选但已被删除的 agent 也保留在列表里，让人看到问题而不是一个空行。

## 备选与不采纳

- **HTTP shim**：本地起一个常驻小服务，把 CLI 包成 `/v1/chat/completions`，应用零改动。不采纳：多一个要用户自己管的常驻进程，超时、取消与调试页都退化，而且「谁在用」变得不清楚。
- **抽出 `protocol Completion` 重写请求装配**：概念更干净，但见 §3。
- **Claude Code 的 `--bare`**：看着更干净，但它规定 auth 只能是 `ANTHROPIC_API_KEY` 或 apiKeyHelper，**不读 OAuth 与 keychain**——正好废掉「用订阅登录」这个前提，因此用 `--safe-mode` 加显式开关代替。
- **让 agent 带着工具跑**：会读写用户文件，延迟与不确定性不可接受。
- **长驻 RPC**（`pi --mode rpc`、`codex app-server`）：省启动开销、能流式输出，但要处理进程生命周期与协议版本漂移；留作后续。
- **一个可自由编辑的命令行模板**：最灵活，但没有可校验的能力开关，用户写错只能得到「运行失败」；三个具名服务商各自配好参数更符合既有 `Provider` 的写法。

## 后果与已知风险

- CLI 参数是各 agent 的版本行为，升级后可能变化；缓解手段是探测版本号、把 agent 的 stderr 带进失败提示，并保留人工验收。
- 延迟高于 HTTP 服务，但没有想象中严重：两三句翻译实测 codex 6.7 秒、pi 1.6 秒，查词 7.5 秒（本机 2026-10-13）。学习与查词会各自再起一个进程，同时在跑的进程限 2 个。Codex 一次极小请求也要约 3 万 tokens（它自带很长的系统提示词与工具），额度成本明显高于直连。
- **不启用 App Sandbox 才能用**：受沙箱约束的应用无法执行用户本机的 CLI。这与 [规范范围边界](../../README.md) 里「本机签名自用，不启用 App Sandbox」一致；若将来上架并启用沙箱，这三个服务商要么移除，要么改走用户显式授权的路径。
- 未验证：三个 agent 在真实登录态下的端到端译文质量与延迟；`--output-schema`／`--json-schema` 的可用性；各 CLI 后续版本对上述参数的兼容性。
