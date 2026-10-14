# BDR-0015：服务商预设与「协议／厂商」分离

状态：已实现（T75，2026-10-15）。来源：用户要求「增加服务商预设，选完只差一把 API Key」。

## 背景与问题

`Provider` 起初同时承担两件事：**怎么说话**（`.openAICompatible` 的协议）与**说的是谁**（`.deepSeek` 带着一份 `("https://api.deepseek.com", "deepseek-chat")` 的预设）。结果是每加一家 OpenAI 兼容厂商就要加一个枚举 case，而用户想用 Moonshot／Kimi、智谱 GLM、通义千问／DashScope、xAI、OpenRouter、Ollama、LM Studio 时，只能自己查 Base URL 和模型名。返回格式能力也挂在 `Provider.supportsJSONSchema` 上，等于把「厂商行为」伪装成「协议属性」。

## 决定

### 1. `Provider` 只表示协议与两个本地 agent

`Provider` 收敛为 `openAICompatible`、`claudeCode`、`codexCLI` 三个 case：前一个是「OpenAI 风格 HTTP 服务」这条投递路径，后两个是各自要跑的本机 CLI。`.deepSeek` 被移除，因为它描述的是厂商而不是协议——这正是本次要修的混淆。

### 2. 厂商列表是数据：`ServicePreset`

新增 `ServicePreset` 值类型（`Owlet/Settings/ServicePreset.swift`），字段为展示名、Base URL、默认模型、返回格式能力、是否读 `GET /models`、钥匙串账户。`ServicePreset.all` 是唯一真源，追加一家厂商只加一行数据，不动任何枚举、后端或请求构造。

自定义入口是其中一个预设（`id == openAICompatible`，`baseURL == nil`），也是整份列表的地基：所有厂商最终都走同一条 `openAICompatible` 投递路径，预设只是替用户填地址与模型名的便利层。

### 3. 返回格式能力跟着预设走

`ServiceConfig` 新增可空 `supportsJSONSchema`：预设给出厂商答案，`nil` 则退回协议自己的默认（`Provider.supportsJSONSchema`）。`ModelClient.format` 读它决定 `.jsonSchema` 还是 `.jsonObject`。这样：

- 自定义 `openAICompatible` 与两个本地 agent 的现有行为一字不变（协议默认仍是「可以用 schema」）；
- DeepSeek 仍只发 `{"type": "json_object"}`，形状继续写在 System Prompt 里；
- 只有**文档明确写出**兼容 `response_format` 的 `json_schema`（含 `name`／`strict`／`schema`）的厂商才标为 true。

**能力只按文档核对，没有在真实账号上各发一次请求**：本机没有这些厂商的 Key。可核对到文档、标为 schema-capable 的是 **Moonshot／Kimi**（其 response_format 文档给出与 OpenAI 相同的结构）与 **xAI**（其 structured outputs 文档同构）；其余厂商或只文档 `json_object`（智谱 GLM）、或支持随模型／端点而变（OpenRouter、DashScope 的 `json_schema` 只覆盖部分模型系列）、或没有可核对的文档（Ollama、LM Studio），一律取更安全的 `json_object`。宁可形状靠 Prompt，也不要一次 400。

### 4. 模型记忆按「服务」分槽，而不是按协议

沿用 T67「切回上一个服务商恢复它原来的模型名」，槽位改为 `service.model.<服务 id>`：

- HTTP 厂商的 id 就是预设 id，所以 `service.model.deepSeek`、`service.model.openAICompatible` 与旧值同名同义，旧安装的记忆**原地兼容**；
- 本地 agent 的 id 就是 `Provider.rawValue`，`service.model.claudeCode` 等同样不变；
- 必须以厂商（而非协议）为单位：Moonshot、GLM、DeepSeek 都是 `openAICompatible`，共用一个槽会让 `glm-5.3` 跟着用户切到 Moonshot。

### 5. 持久化一个「服务选择」，旧键只作迁移输入

新键 `service.choice` 存当前选择：HTTP 厂商存预设 id，本地 agent 存 `Provider.rawValue`。旧键 `service.provider` 不再写，只在读取时兜底——它存的值（`deepSeek`、`claudeCode`、`codexCLI`、`openAICompatible`）恰好都是合法的服务 id，所以老安装无需一次性迁移脚本，第一次读到就得到与升级前相同的服务、钥匙串账户与能力。钥匙串账户：自定义仍是 `default`，其余厂商等于预设 id，因此 DeepSeek 老 Key 继续生效。

## 备选与不采纳

- **每家厂商一个 `Provider` case**：类型上最直白，但每加一家都要改枚举、能力表、模型清单分支与测试，而且把「协议」和「厂商」永久绑死，正是本次要拆开的耦合。
- **把本地 agent 也做成 `ServicePreset`**：列表与持久化会更统一，但 agent 没有 Base URL、默认模型、钥匙串账户，硬塞进去只会让预设的一半字段对它们无意义；`Provider` 继续当「协议 + 两个 agent」更诚实。
- **新增厂商时顺手把 `GET /models` 也打开**：除 DeepSeek 外没有在本机核对过各家的 `/models` 行为与鉴权差异，先只保留既有的 DeepSeek 模型下拉，避免把「填默认模型」变成「读不出来的空下拉」。
- **给未核对的厂商标 schema-capable**：一次 400 比形状写在 Prompt 里糟得多；本地校验对两者同样严格，所以取安全值没有正确性代价。

## 后果与已知风险

- 默认模型只是「第一次选中时填进去的名字」，用户可以改，也不会因为厂商改版而失效——它只是初值。
- 各厂商文档里的模型名会变；这份表需要随文档更新（与 `Provider` 的 CLI 参数同属「外部行为」）。
- **未验证**：任何真实厂商的端到端调用（没有 Key），因此 `supportsJSONSchema` 的 true 只到「文档同构」这一层，真实返回质量、模型名是否仍可用、Base URL 的地区差异（如 DashScope 新业务空间域名）都留给人工验收。
