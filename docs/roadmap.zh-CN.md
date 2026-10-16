[English](roadmap.md) · [简体中文](roadmap.zh-CN.md)

# Owlet · 路线图

还没收尾的事。行为以 `spec/` 为准；已发布的改动见 [CHANGELOG.md](../CHANGELOG.md)。新工作在这里登记一条，写明验收条件与验证方式；发布并验证后删掉该条。

## 待验收

已实现，但部分证据只能由人或真实环境给出。

| 事项 | 还剩什么 | 位置 |
| --- | --- | --- |
| 按 Figma 画板重做的浮窗 | 对照画板的视觉复核：圆角、错误文字颜色、活跃玻璃、交互状态。 | [Panel 调试与测试](panel-debugging-and-testing.zh-CN.md) |
| 阅读查词第一步 | 五类区域均已可用；待验收：真实系统语音发音、真实 VoiceOver、安装版。 | [word-lookup.feature](../spec/vocabulary/features/word-lookup.feature)、[BDR-0008](../spec/vocabulary/decisions/BDR-0008-reading-word-lookup.md) |
| 学习推荐的纠正重试 | 用真实模型复验：一次纠正能修好违约的返回。 | [LLM 契约](../spec/llm/contract.md) |
| 选中文字读取 | 辅助功能路径、⌘C 兜底与粘贴写回已实现；在各真实应用上的兼容性仍需手测。 | [selected-text-capture.zh-CN.md](selected-text-capture.zh-CN.md) |
| 调试页改为记录卡片 | 跑 `mise run dev`，各做一次失败与成功的请求：看卡片在 620 宽的窗口里是否像一条条记录、各段原文的折叠动效、`清除` 是否清空、以及 `复制` 是否短暂显示「已复制」。 | `Owlet/Settings/DebugSettingsPane.swift` |

## 未做端到端验证

- **本机 agent 作为模型服务。** Claude Code 与 Codex CLI 有假 runner 的测试覆盖。未验证：真实登录态下的质量与延迟、Claude Code 的 `--json-schema`、后续 CLI 版本的兼容性。Claude Code 的模型清单读它自己在 `~/.claude/cache/model-catalog/` 的缓存，这不是官方接口。见 [BDR-0013](../spec/settings/decisions/BDR-0013-local-agent-provider.md)。
- **HTTP 服务商预设。** Base URL、默认模型与 JSON Schema 能力只按各家公开文档核对，没有用真实 Key 调用过任何一家。见 [BDR-0015](../spec/settings/decisions/BDR-0015-provider-presets.md)。
- **OpenAI Responses、Anthropic 与 Gemini 协议。** 请求形状只按各家文档与单元测试核对，没有用真实 Key 调用过。验收：用真实 Key 经每种协议各发一次翻译、查词与学习请求，确认带 JSON Schema 的请求被接受、错误 Key 显示为认证失败、模型清单能读到、测试按钮能报告成功与失败；并目测「文本框加预设按钮」两行在设置表单里的宽度与对齐。见 [BDR-0016](../spec/settings/decisions/BDR-0016-wire-protocols.md)。
- **每种界面语言各一份 System Prompt。** 单元测试覆盖取哪一份、以及切换语言不算编辑；没有在真实应用里看过。验收：打开模型页切换界面语言，确认没编辑过的 Prompt 跟着换、编辑过的不变，并读一遍四份文本作为 Prompt 是否通顺（英文、繁体中文与日文是这次新写的）。见 [BDR-0011](../spec/settings/decisions/BDR-0011-interface-language.md)。

## 设计就绪，未实现

- **模型返回的流式显示。** 只改「何时看见」，不改请求契约、本地校验与写回。等待对替换入口的决定。见 [streaming-output.md](streaming-output.md)。

## 尚未进入产品定义的提案

- **屏幕区域 OCR 输入。** 在屏幕上框一个矩形，用 Vision 识别其中文字；只能复制，没有可写回的地方。见 [screen-region-input.zh-CN.md](screen-region-input.zh-CN.md)。
- **连续语音输入。** 见 [speech-input.zh-CN.md](speech-input.zh-CN.md)。暂不做。

## 首版不做

复习、间隔重复与掌握度；自动收藏；同步与账号；多版本润色与语气模板。见 [product.zh-CN.md](../spec/product.md) 的「首版不做」。
