# BDR-0016：多协议支持，服务列表按「协议／厂商／本地 agent」三组排列

状态：已实现（2026-10-16）。来源：用户要求「开新功能来支持更多的协议而不是 provider」，并把选择列表改成「第一组协议、第二组 DeepSeek 等预设、第三组本地 agent」；随后要求厂商预设只留最常见的几家，Base URL 可改且按服务记住，模型名与思考强度都能从列表选也能手填，并加一个测试按钮。

## 背景与问题

BDR-0015 已经把厂商变成数据（`ServicePreset`），但所有 HTTP 预设都被写死在同一条 OpenAI Chat Completions 投递路径上：`ServiceChoice.provider` 对任何预设都返回 `.openAICompatible`，`Provider.backend` 也只分 HTTP 与 CLI 两种。因此用不了 Anthropic、Gemini 或 OpenAI Responses 这些原生协议，只能找一个 OpenAI 兼容的转接服务。

## 决定

### 1. `Provider` 就是协议

`Provider` 的 case 为 `openAICompatible`（Chat Completions）、`openAIResponses`、`anthropic`（Messages）、`gemini`（generateContent），再加上两个本地 agent `claudeCode`、`codexCLI`。每个 HTTP 协议有自己的后端：路径、鉴权头、请求体、思考强度字段与回复信封都由它自己处理。只有发送请求、HTTP 状态映射与调试页展示是共用的（`HTTPBackend`）。

| 协议 | 路径 | 鉴权 | 返回格式 | 思考强度 |
| --- | --- | --- | --- | --- |
| OpenAI Compatible | `chat/completions` | `Authorization: Bearer` | `response_format` | `reasoning_effort`，按模型映射（`ModelEffort`） |
| OpenAI Responses | `responses` | `Authorization: Bearer` | `text.format` | `reasoning.effort`，与上一行同一张表 |
| Anthropic | `messages` | `x-api-key` + `anthropic-version: 2023-06-01` | `output_config.format`（没有 json_object，无 Schema 时形状只写在 System Prompt 里） | `output_config.effort`；当前模型不能关闭思考，「关闭」发 `low` |
| Gemini | `models/{model}:generateContent` | `x-goog-api-key` | `responseMimeType: application/json` + `responseJsonSchema` | `thinkingConfig.thinkingLevel`，只对 Gemini 3 及以后的模型发送，并按模型族取它接受的档位 |

截断、拒答与空回复在每个后端里分别映射为 `truncated`／`refused`／`emptyResponse`，之后的契约校验对所有协议完全相同。

### 2. 预设带上自己的协议

`ServicePreset` 新增 `provider` 字段，`ServiceChoice.provider` 直接返回它。新增一家厂商仍然只是加一行数据；它说哪种协议，就由这一行写明。

### 3. 列表分三组

1. **协议**：OpenAI Compatible、OpenAI Responses、Anthropic、Gemini。每个协议一个入口，可用于任何说这种协议的服务。
2. **厂商预设**：只留 DeepSeek、OpenRouter、Ollama（见第 6 节）。
3. **本地 agent**：Claude Code、Codex CLI，与 BDR-0013 相同。

### 4. 协议入口填协议方自己的地址，不填模型名

Base URL 只有一个共用的设置项。如果切换到 Anthropic 时不改地址，上一个厂商的地址会留在框里，第一次请求就会发错地方。所以 OpenAI Responses、Anthropic、Gemini 选中时填入协议方自己的地址（`api.openai.com/v1`、`api.anthropic.com/v1`、`generativelanguage.googleapis.com/v1beta`），用户仍可改成任何兼容端点。模型名由用户自己填，因为协议入口不代表某一个模型。OpenAI Compatible 保持 BDR-0015 的行为：不改用户已填的地址。

每个协议入口有自己的钥匙串账户（等于入口 id），模型名记忆同样按入口分槽。

### 5. 兼容性

已有的 `service.choice`／`service.provider` 值都不变，老安装打开后得到的服务、地址、Key 与模型与升级前相同。

### 6. 厂商预设只留三家

预设只是「替用户填地址与默认模型」的便利，列表越长越难找。只留每类最常见的一家：直连厂商 DeepSeek、聚合平台 OpenRouter、本机运行时 Ollama。BDR-0015 加入的 Moonshot／Kimi、智谱 GLM、通义千问、xAI、LM Studio 移除——它们从未进入正式发布，没有需要迁移的用户；这些服务仍可通过 OpenAI Compatible 入口自己填地址使用。

### 7. Base URL 按服务记住

切换服务时，离开的服务记下当前地址（`service.baseURL.<服务 id>`），进入的服务优先用它记下的地址，其次用预设地址。这样用户把 Anthropic 改成自己的转接地址后，切走再切回不会被预设覆盖。OpenAI Compatible 没有记录时保持框里已有的地址，与以前相同。

### 8. 模型名与思考强度是文本框加「预设」按钮

两行都由一个可自由输入的文本框加右侧一个「预设」按钮组成，都用系统默认外观（文本框与 Base URL 行相同，按钮是普通 `Menu`），没有自绘材质。值控件始终可输入，候选值从按钮的下拉里选，两种用法互不遮挡。第一版用 AppKit 的 `NSComboBox` 把两者合成一个控件，用户看过之后不要，改成现在这样。

- 模型清单：每个 HTTP 协议都按自己的形状读取（OpenAI 两种协议 `GET /models`，Anthropic `GET /models?limit=1000` 加 `x-api-key`，Gemini `GET /models?pageSize=1000`，去掉 `models/` 前缀并只留支持 `generateContent` 的模型）。读不到时清单为空、「预设」按钮不可用，原因按 §10 显示，输入框照常可用。本地 agent 的清单来源不变（BDR-0013）。
- 思考强度：「预设」按钮列出各档位的原始值 `automatic`／`none`／`low`／`medium`／`high`／`max`，值按用户要求**不翻译**——框里显示的就是要发送的值。输入原始值（大小写不敏感）对应该档位，留空为 `automatic`。输入其他值（如 `xhigh`）时，该值**原样**放进当前协议的强度参数，不经过按模型映射；这样模型新增的档位不必等应用更新。值不被服务接受时，服务返回的错误照常显示。

### 9. 测试按钮

模型分组底部有「测试」按钮：先保存正在编辑的 Key，再用已保存的配置走正式请求的同一条路径，翻译《蒹葭》首句「蒹葭蒼蒼，白露為霜。」（与网站展示的是同一首诗；文言很少与目标语言相同，能证明模型真的翻译了）。状态（运行中、成功、失败）与耗时显示在按钮上；成功时模型的译文显示在按钮下方。配置不完整时只提示补齐，不发请求，也不显示耗时。

### 10. 模型相关的报错只显示一处

模型分组里只有一行错误位置：读取模型清单失败与测试失败都写在这一行，先出现的失败（测试失败）优先，一行里写明原因并带「重试」——重试重放刚失败的那件事。同一句话不再在分组内出现第二次。这样 Key 填错时不会一边在模型名下面报一次、一边在测试按钮下面再报一次。失败信息仍然就地显示，不改变各行的控件（用户要求的「错误只在一个地方」）。

其它分组的失败保持原位：本机 agent 的可执行文件出错仍显示在 Detect 一行下方，Prompt 契约错误仍显示在提示词分组。

## 备选与不采纳

- **把协议做成预设上的一个可选下拉，让用户给自定义入口选协议**：设置项更少，但多出一个只在自定义时才有意义的控件；每个协议一个入口更直观，也不需要新的持久化键。
- **为 Gemini 2.5 发 `thinkingBudget`**：每个模型的取值范围不同，又不在当前文档里。先只支持 Gemini 3 的 `thinkingLevel`，其余模型不发强度参数，由服务决定。
- **模型名用 Picker 加「其他…」再弹出文本框**：仍是两个控件，用户明确不要。
- **一个 Picker 列出候选值、不加文本框**：外观最像服务列表，但模型名与强度都只能是清单里的值，清单读不到或服务有清单以外的名字时没法用。
- **继续用 `NSComboBox` 把输入与下拉合成一个控件**：技术上最贴「一个控件」，但外观要自绘（去掉系统边框再用 `glassEffect`），用户看过后不要。改成文本框加按钮后，两行都是系统默认外观，不再需要例外。
- **保留全部八家厂商预设**：列表太长，且其余几家都能通过协议入口使用。

## 后果与已知风险

- **未验证**：没有用真实 Key 端到端调用过这三个协议，请求形状只按各家文档和单元测试核对。Gemini 的 `responseJsonSchema` 是否接受 `["string","null"]` 这样的联合类型、Anthropic 结构化输出是否接受当前 Schema，都留给人工验收。
- Gemini 结构化输出的字段名各家文档不一致：`responseSchema` 已标废弃，当前写法是 `generationConfig.responseFormat.text.{mimeType, schema}`，而本实现发的是标准 JSON Schema 的 `responseJsonSchema`（公开 schema 里仍在、未标废弃，且已同时发 `responseMimeType: application/json`）。人工验收若被 400 拒绝，改发 `responseFormat.text`。
- Gemini 的无效 Key 历史上返回 HTTP 400（`API_KEY_INVALID`），目前会显示为「HTTP 400」而不是「认证失败」。
- Gemini 的思考档位表按模型名前缀匹配，模型族变化时需要更新，与 `ModelEffort` 相同。
- 手填的思考强度不做任何校验；填错时由服务返回 400，测试按钮可以提前发现。
- 文本框加「预设」按钮两行的宽度与对齐未在真机上目测过（预览脚本出图），留给人工验收。
