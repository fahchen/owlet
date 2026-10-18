# 模型返回的流式显示方案

状态：**已实现，第一轮已落地**（翻译／润色面板与阅读查词；主窗口的翻译／润色显示已到达的文字，接收中的排版跟随即将定稿的显示方式；学习收集保持整段，见下面的取舍记录与 `spec/processing/decisions/BDR-0017-streaming-display.md`）。本文件不改变请求契约、本地校验与写回规则，与用户可见字符串一律进 `strings/translations.json` 的约束一致。第一轮之后，「必须实测」一节列出的项目仍待人验收（也登记于 [roadmap.md](roadmap.md)）。

`spec/llm/contract.md` 是硬约束：结构、目标语言、原文拼接三项都在本地校验，校验失败不得当成成功结果、不得写回（[contract.md:17](../spec/llm/contract.md)、[:102](../spec/llm/contract.md)、[:110](../spec/llm/contract.md)）。本方案的所有取舍都从这条出发。

## 为什么值得看，以及它不解决什么

今天每次请求都等完整回答才显示任何文字：本机 Claude Code / Codex CLI 大约 7–15 s，OpenAI 兼容 HTTP 服务 1–3 s（人类给出的本机测量／观感数字，本文未重测）。整段时间面板只显示处理态（`PanelController.Notice.translating`，[PanelController.swift:188-192](../Owlet/App/Panel/PanelController.swift)）。

流式能把**首个字符**的等待压到 1 s 以内（预期，**待实测**）。它**不**解决：

- **总时长基本不变**。模型仍要生成整段文字，流式只是把它分多次送达。
- **契约校验仍只在回答完整后做**。一个 JSON 对象要能解析、源文要能拼接、目标语言要能比较，都是「整段到齐」之后的事。流式期间的文字在被校验之前，**不是结果**。
- **不改善翻译质量**，也不减少请求次数。

一句话：流式改的是「何时看见」，不是「何时可信」。

## 现状：一次请求今天怎么走

- 组装层 `ModelClient.perform` 调 `backend.complete`（[ModelClient.swift:430-460](../Owlet/LLM/ModelClient.swift)、[:452](../Owlet/LLM/ModelClient.swift)）。
- `ModelBackend` 协议只有 `describe` 与 `complete` 两个方法（[ModelBackend.swift:55-60](../Owlet/LLM/ModelBackend.swift)）。
- HTTP 后端的传输是注入的：`OpenAICompatibleBackend.transport`（[ModelBackend.swift:63-64](../Owlet/LLM/ModelBackend.swift)）、`ModelClient.transport`（[ModelClient.swift:93](../Owlet/LLM/ModelClient.swift)），类型是「一次返回 `(Data, URLResponse)`」（[ModelClient.swift:69](../Owlet/LLM/ModelClient.swift)）——**这是流式要动的第一处**。
- 本机 agent 后端：`LocalAgent.complete` → `spawn` → `runProcess`，stdout / stderr 落文件，**等进程退出才读回文件**（[LocalAgent.swift:211-227](../Owlet/LLM/LocalAgent.swift)、[:359-381](../Owlet/LLM/LocalAgent.swift)、[:406-447](../Owlet/LLM/LocalAgent.swift)）。
- 三个消费者都只有「处理中／完成／失败」三态，没有「正在收到文字」：`TextProcessingModel.State.loading`（[TextProcessingModel.swift:8](../Owlet/Processing/TextProcessingModel.swift)）、`LearningModel.State.loading`（[LearningContent.swift:56-58](../Owlet/Learning/LearningContent.swift)）、`LookupStore.State.loading`（[LookupStore.swift:9-11](../Owlet/Lookup/LookupStore.swift)）。
- 面板的替换只认完成结果：`PanelController.run(.replace)` 要求 `case .success`（[PanelController.swift:317-319](../Owlet/App/Panel/PanelController.swift)），`inlineNotice` 在处理中返回 `nil`（[:224-234](../Owlet/App/Panel/PanelController.swift)）。

## 流式落在哪、不落在哪

| 消费者 | 是否流式 | 为什么 |
| --- | --- | --- |
| 浮窗翻译／润色结果 | **是（主场景）** | 用户正在盯着等的就是它；今天整段延迟最明显。 |
| 翻译并直接替换 | 面板可流式，**正文写入仍等校验** | 见交互选项；`contract.md:17` 的写回门槛不因流式放松。 |
| 阅读查词卡 | **待人决定**（见决策 3） | 响应短，且卡片已有独立的 loading／复用／重试状态；先做主场景更划算。 |
| 学习推荐（后台请求） | **否** | 它是后台请求，主结果已显示，规范写明「主结果先显示／写回；不等待学习完成」（[contract.md:46](../spec/llm/contract.md)）。用户没在等它，流式只增加状态与失败面。 |
| 按需补充释义（`fillMeaning`） | **否** | 单字段、短，收益最小。 |

## 逐后端实测（本机）

### OpenAI 兼容 HTTP

- **已验证（读代码）**：传输以 `Transport` 注入，默认 `URLSession.shared.data(for:)`（[ModelClient.swift:69](../Owlet/LLM/ModelClient.swift)、[:93](../Owlet/LLM/ModelClient.swift)；[ModelBackend.swift:64](../Owlet/LLM/ModelBackend.swift)），一次拿到完整 `Data`。流式需要**第二个 seam**（返回字节流的传输），而不是改现有这个——现有 seam 还要给 `listModels` 和测试用。
- **已验证（本机 SDK）**：Foundation 已提供 `URLSession.bytes(for:) async throws -> (AsyncBytes, URLResponse)`（`…/MacOSX.sdk/System/Library/Frameworks/Foundation.framework/Modules/Foundation.swiftmodule/arm64e-apple-macos.swiftinterface:16721`），`AsyncBytes`（同文件 :16701）与按行遍历的 `AsyncSequence.lines`（同文件 :14815、:14839）都在。macOS 12+ 可用，满足最低 macOS 26。
- **形状（待实测）**：请求体加 `stream: true`；响应 `text/event-stream`，逐行 `data: {...}`；增量在 `choices[].delta.content`，以 `data: [DONE]` 收尾。**本机没有任何可达的 OpenAI 兼容服务**（`127.0.0.1:11434`／`1234`／`8080` 的 `/v1/models` 均无响应），也没有配置的 Key，故这些字段名只按协议常识列出，**待实测**。
- 流式实现必须照旧应用现有的外壳规则：`finish_reason` 的截断／拒绝（[ModelBackend.swift:113-123](../Owlet/LLM/ModelBackend.swift)）与 HTTP 状态到 `ModelError` 的映射（[:138-141](../Owlet/LLM/ModelBackend.swift)）。

### Claude Code CLI

- 本机版本：`claude --version` → `2.1.299 (Claude Code)`。
- `claude --help` 的原文：`--output-format <format>` 取 `"text"`（默认）、`"json"`、`"stream-json"`；`--include-partial-messages`「Include partial message chunks as they arrive (only works with --print and --output-format=stream-json)」；`--verbose`「Override verbose mode setting from config」。
- **实测（命令与输出）**：`claude --print --output-format stream-json …`（不带 `--verbose`）→ 退出码 1，stderr 恰为 `Error: When using --print, --output-format=stream-json requires --verbose`。与人类此前的观察一致。
- **实测事件外壳**：加上 `--verbose` 后，一次调用（本机 Claude 周配额已用尽，所以正文是一条配额提示，但信封是真的）逐行输出：
  - `{"type":"system","subtype":"init", …}`
  - `{"type":"rate_limit_event", …}`
  - `{"type":"assistant","message":{ … "content":[{"type":"text","text":"…"}]} …}`
  - `{"type":"result", … "result":"…","is_error":true,"subtype":"success"}`

  即：**助手正文在 `assistant` 事件的 `message.content[].text`**，最终正文也在 `result.result`。
- **纠正一处流传的说法**：本应用今天**不从** `--output-last-message` 读 Claude 的答案。`answersToFile` 只有 Codex 为真（[LocalAgent.swift:272](../Owlet/LLM/LocalAgent.swift)），Claude 的答案从 **stdout** 读回；本机 `claude --help | grep output-last-message` 无输出，该开关不存在（`--output-last-message` 是 Codex 的，[LocalAgent.swift:151](../Owlet/LLM/LocalAgent.swift)、[:336](../Owlet/LLM/LocalAgent.swift)）。
- **今天的配方**（claude 分支，[LocalAgent.swift:300-307](../Owlet/LLM/LocalAgent.swift)）：`--print --tools "" --safe-mode --strict-mcp-config --no-session-persistence --system-prompt …`，带 Schema 时再加 `--json-schema`。**流式配方**：在该分支追加 `--output-format stream-json --verbose`，逐行解析 stdout；如要更细的增量再加 `--include-partial-messages`。`--output-last-message` 不适用。
- **待实测**：一次**成功**回答的流事件（是否出现 `stream_event`／增量块，增量块的确切类型与字段），以及 `--include-partial-messages` 的粒度。原因：本机周配额用尽。

### Codex CLI

- 本机版本：`codex --version` → `codex-cli 0.160.1`。
- `codex exec --help` 的原文：`--json`「Print events to stdout as JSONL」；`-o, --output-last-message <FILE>`「Specifies file where the last message from the agent should be written」。
- **实测命令**（在 `/tmp`，行为只针对 CLI，不涉及本应用）：

  ```sh
  codex exec --json --ephemeral --skip-git-repo-check --sandbox read-only \
    --ignore-user-config -c 'approval_policy="never"' \
    -c 'model_instructions_file="/tmp/owlet-codex-instr.txt"' \
    --output-last-message /tmp/owlet-codex-answer.txt "Reply with exactly the word: owlet"
  ```

  退出码 0，stdout 恰好四行 JSONL：

  ```json
  {"type":"thread.started","thread_id":"…"}
  {"type":"turn.started"}
  {"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":"owlet"}}
  {"type":"turn.completed","usage":{…}}
  ```

  与人类给出的 `thread.started`／`turn.started`／`item.completed`／`turn.completed` 四种事件一致。
- **助手正文在 `item.completed` 的 `item.text`（`item.type == "agent_message"`）**；`-o` 指定的文件里也是同一段文字（实测 `answer.txt` 内容为 `owlet`）。
- **没有部分增量**：换一个 120 词的长回答重跑，事件类型计数仍是 `{'thread.started': 1, 'turn.started': 1, 'item.completed': 1, 'turn.completed': 1}`，`agent_message` 文本 830 字符，没有 `item.updated`、`item.delta` 或任何 `delta` 事件。**本机 0.160.1 实测：一次回答整段在结束时到达**。所以 Codex 路径上「流式」只能做到「一个进程事件流」，做不到「更早看见字」。
- 一条顺带实测：`model_instructions_file` 不能指向 `/dev/null`（`Error: failed to read model instructions file /dev/null: path '/dev/null' is not a file`），必须是真实文件——与本应用写临时 instructions 文件的做法一致（[LocalAgent.swift:394-396](../Owlet/LLM/LocalAgent.swift)）。

## 交互设计（要人决定的正是这里）

**不在候选内的做法**：把流式文本直接写进用户的目标应用。两个原因：它未过本地校验即写回，违反 [contract.md:17](../spec/llm/contract.md)；用户会看到自己的文档里出现半截、可能被替换掉的文字。

面板现状：结果由 `TextProcessingModel.State` 表达（`.idle／.loading／.success／.failure／.missingConfig`，[TextProcessingModel.swift:6-14](../Owlet/Processing/TextProcessingModel.swift)），替换动作与复制都只认 `.success`（[PanelController.swift:245-249](../Owlet/App/Panel/PanelController.swift)、[:317-319](../Owlet/App/Panel/PanelController.swift)）。

| 方案 | 面板看到什么 | 替换入口 | 校验失败时 | 代价 |
| --- | --- | --- | --- | --- |
| **A. 仅面板流式 + 原子替换** | 逐段到来的文字，标记「正在接收」 | 流结束且校验通过后，才按现有语义可替换（写入动作本身不变） | 面板从 partial 切到错误态，partial 丢弃 | 替换键在流中「看起来能按但没反应」，需要额外说明 |
| **B. A + 流式中显式禁用替换（推荐）** | 同 A | 同 A，但替换控件显式置灰并说明「正在接收，收到完整结果后可替换」 | 同 A | 多一个要维护的控件状态；换来的是「没有静默失败」 |
| **C. 混合：partial 保留 + 用纠正结果原地替换** | 同 A，另加「仍在接收」的动效 | 同 B | partial **被纠正后的结果替换**（一次可见跳动）；若纠正仍失败才进错误态 | 跳动可能被误读为「结果变了」；纠正本身多一次请求，等待更久 |
| **D. 不可见流式（保持处理态）** | 与今天完全相同 | 与今天完全相同 | 与今天完全相同 | 几乎没收益：用户仍面对同样的空白等待，只是内部时序变了 |

### 各方案在同一个场景下的表现

| 场景 | A | B（推荐） | C | D |
| --- | --- | --- | --- | --- |
| 流中用户取消 | 停止请求、清空 partial，回到取消提示（沿用 `PanelController.stop`，[:207-212](../Owlet/App/Panel/PanelController.swift)） | 同 A | 同 A | 同今天：取消处理态 |
| 流到一半出错 | partial 丢弃，进错误态与恢复入口 | 同 A | 同 A | 进错误态 |
| 流结束后校验失败 | partial 丢弃，进契约错误态；纠正轮照旧（`ModelClient.learning`／`lookup` 的纠正路径，[ModelClient.swift:191-223](../Owlet/LLM/ModelClient.swift)） | 同 A | partial 被纠正结果原替换；仍失败才错误态 | 同今天 |
| 纠正后重试成功 | 用新结果正常显示 | 同 A | 用户看到 partial→纠正结果的一次跳动 | 同今天 |
| 流中按替换快捷键 | **新失败面**：必须给出可见理由 | 控件置灰并说明；快捷键同样给出可见提示 | 同 B | 不存在（仍在处理态） |

**新的、必须可见且诚实的失败面**：只有「流中取消／半途出错」和「流中按替换」是今天不存在的状态。「收流中的文字不是结果」必须由界面明确表达（例如一行「正在接收…」与置灰的替换），否则用户会把 partial 当成已完成结果——这正是 `spec` 里「不得静默失败」的对偶：**也不能静默地假装完成**。

## 架构草图（不写代码）

- **`ModelBackend` 加第二个方法**，例如 `stream(_:config:) -> AsyncThrowingStream<String, Error>`（逐块 yield）。**给一个默认实现**：内部调用现有 `complete`，把整段作为单个元素 yield 后结束。这样不能流式的后端零改动继续工作，`complete` 也不删（[ModelBackend.swift:55-60](../Owlet/LLM/ModelBackend.swift)）。
- **HTTP 后端**覆盖默认实现：body 加 `stream: true`，走新的字节流 seam（`URLSession.bytes(for:)`）。现有 `Transport`（`(Data, URLResponse)`）保留，`listModels` 与现有测试不受影响。
- **本机 agent**：`LocalAgent` 需要一条「边读 stdout 边产出」的 runner；今天 stdout 落文件、进程结束才 `read`（[LocalAgent.swift:406-447](../Owlet/LLM/LocalAgent.swift)）。Claude 走 `--output-format stream-json --verbose` 逐行解析；**Codex 在本机只能整段到达**（上面已实测），因此它的流最多是一个元素。
- **组装层**：`ModelClient.perform`（[:430-460](../Owlet/LLM/ModelClient.swift)）分流——需要流式时用 `stream`，把累计文本交给一个 partial 回调，**流结束后仍然用同一条 `parse(content)` 校验**；校验失败仍走现有的错误与纠正路径。`parse` 只吃完整文本，partial 永不进 `parse`。
- **面板／模型**：`TextProcessingModel.State` 增加一个「正在接收，携带 partial 文本」的状态（或给 `.loading` 带 partial）。**`.success` 仍然只在 `parse` 通过后设置**——这样 `PanelController` 里所有以 `.success` 为门槛的路径（替换 [:317](../Owlet/App/Panel/PanelController.swift)、`inlineNotice` [:224](../Owlet/App/Panel/PanelController.swift)、`lookupOrigin` [:237](../Owlet/App/Panel/PanelController.swift)、`copyResult` [:245](../Owlet/App/Panel/PanelController.swift)）自动保持今天语义，不需要新增「部分结果算结果」的分支。这是本方案能小的关键。
- **显示层**：接收中的文字由一处 `ReceivingResult` 按显示方式排版——「逐句对照」逐对长出，「原文／译文分段」只长译文文字——面板与主窗口的翻译／润色共用它，定稿时不发生「配对↔整段」的跳变；它不接 `LookupOrigin`，接收中的文字不提供查词、复制或替换。接收中的文字上方不加进度指示器：转圈或「正在翻译…」与流动的文字并置既像过期标签又白占一行，**文字本身即进度**；第一段到达前各界面维持自己的空态。逐句对照下面板在收流期间就收起源文框：面板高度上限 480，源文框压在上面会把正在生长的句组挤出可视区，而句组自带原文。
- **取消与迟到**：沿用 `ModelClient` 的 `Task` 取消与 `operationID` 守卫（[TextProcessingModel.swift:63-67](../Owlet/Processing/TextProcessingModel.swift)、[:127](../Owlet/Processing/TextProcessingModel.swift)）。HTTP 的 `AsyncBytes` 随 Task 取消；agent 仍由 `AgentProcess` kill（[LocalAgent.swift:947-974](../Owlet/LLM/LocalAgent.swift)）。**新增要求**：取消或切换请求后，已 yield 的 partial 必须清空，不能残留到下一个请求。
- **调试页**：`DebugExchange.response` 是单个 `String?`（[DebugLog.swift:16](../Owlet/Debug/DebugLog.swift)），调试页承诺不含 Key（[contract.md:104](../spec/llm/contract.md)）。建议**只记最终文本**，不记整条流：流的价值在交互，不在取证；整条流会把大量未校验片段写进记录。若确需取证，只加计数类字段（首个块到达时间、块数），不存每块文本。

## 决策（要人定，不是排期）

1. **替换 UI 选 A／B／C／D 哪一个。本文件建议 B**：A 的原子替换方向正确，但状态是「碰巧不可用」；B 把它变成显式的、有说明的控件状态，代价小，符合「不得静默失败」。C 的信息量与可见跳动是否值得，是产品口味问题；D 基本没有收益。
2. **partial 是否进历史。建议不进**：历史记的是成功结果，partial 未过校验，写入等于把未校验文本存成成功（[contract.md:110](../spec/llm/contract.md)）。
3. **查词卡是否也流式。建议先不**：响应短，卡片已有独立的 loading／复用／重试状态（[LookupStore.swift:9-11](../Owlet/Lookup/LookupStore.swift)），先做主场景。
4. **是否按 provider 自动降级。建议是**：能力开关放 `Provider`（今天 `supportsJSONSchema` 就在那里，[SettingsStore.swift:34-38](../Owlet/Settings/SettingsStore.swift)），不能流式的 provider 走默认实现整段返回，界面不承诺「一定逐字出现」。

## 必须实测（本文不回答的部分）

- OpenAI 兼容服务的真实 SSE 字段与 `[DONE]`：本机无可用服务，也未配置 Key。
- 一次成功的 Claude `stream-json`（尤其是 `--include-partial-messages` 的增量事件）：本机周配额用尽。
- 首字延迟与总时长的真实数字：7–15 s / 1–3 s 是人类的观感数字，本次未重测。
- 流式下只支持 `json_object` 的服务（如 DeepSeek，[SettingsStore.swift:34-38](../Owlet/Settings/SettingsStore.swift)）是否稳定分片、以及分片是否影响本地校验的可靠性。

## 相关

- [LLM 返回契约](../spec/llm/contract.md)：本地校验与写回门槛，本方案的硬约束。
- [未实现功能清单](unimplemented-features.md)：本提案的登记处。
- [产品规格索引](../spec/README.md)：本文件的索引位置。
