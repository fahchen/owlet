[English](README.md) · [简体中文](README.zh-CN.md)

# 产品行为规格

本目录是当前项目的产品规格入口，基于已确认的首版需求。原生 macOS 应用已在 `Owlet/` 实现，测试在 `OwletTests/`（Swift Testing），由 `mise run check` 运行；Gherkin 场景尚未绑定 step definitions。早期的浏览器原型 `design/` 已退役。

- [产品定义](product.zh-CN.md)：范围、系统支持与用户流程。
- [设计规范](DESIGN.zh-CN.md)：原生组件、系统强调色与中性玻璃界面（玫瑰主色已于 2026-09-29 撤销）。
- [工程规范](engineering.zh-CN.md)：命令、结构、风格、验证与边界。
- [术语](glossary.zh-CN.md)：统一概念。
- `processing/features/`：翻译、润色、快捷入口、替换与工具栏错误呈现。
- `learning/features/`：独立开关、临时展开、推荐收藏与释义语言。
- `vocabulary/features/`：手动收藏、语境、生词本管理与编辑；[阅读查词第一步](vocabulary/features/word-lookup.zh-CN.feature) 五类区域均已实现（T48–T51），待最终验收。
- `history/features/`：保存、查看、搜索与删除历史；按天分组、关联从该记录收藏的词条。
- `settings/features/`：自填模型服务配置、[本机 agent CLI 作为模型服务](settings/features/local-agent.zh-CN.feature)、自定义 Prompt、按源语言决定翻译目标、按语言配置读音体系、浮窗玻璃效果，以及原生窗口的输入焦点。
- [LLM 返回契约](llm/contract.zh-CN.md)：默认 Prompt、JSON Schema 与失败行为。
- [屏幕区域 OCR 输入方案](../docs/screen-region-input.zh-CN.md)：未实现的输入来源设计提案，不改现有读取路径。
- [连续语音输入方案](../docs/speech-input.zh-CN.md)：未实现的输入来源设计提案，本轮不做。
- [模型返回的流式显示方案](../docs/streaming-output.md)：未实现的呈现设计提案，只改「何时看见」，不改请求契约、本地校验与写回；是否实现取决于人对替换入口 UI 的决定。
- [替换行为决策](processing/decisions/BDR-0001-explicit-replacement-intent.zh-CN.md)。
- [错误呈现决策](processing/decisions/BDR-0002-preserve-open-toolbar-on-error.zh-CN.md)：已展开的工具栏遇错保持展开。
- [翻译目标映射决策](settings/decisions/BDR-0003-translation-target-mapping.zh-CN.md)：按检测到的源语言查表决定目标，未命中用兜底；润色与快捷键不变。
- [生词本可编辑决策](vocabulary/decisions/BDR-0004-editable-notebook.zh-CN.md)：释义、表达、语言、笔记、标签、重点可编辑；释义可被重新生成覆盖，笔记是用户的安全区。
- [释义语言决策](learning/decisions/BDR-0005-definition-language.zh-CN.md)：释义跟随本次翻译目标语言，润色按目标映射查原文语言；生成与重新生成都按当下的映射。
- [按需补充决策](vocabulary/decisions/BDR-0006-on-demand-enrichment.zh-CN.md)：读音与词性在详情按需补充；「补充缺失」只填空、单项「重新生成」只覆盖该项；整句不标；读音体系按语言设置。
- [历史作为学习本决策](history/decisions/BDR-0007-history-as-learning-log.zh-CN.md)：收藏记录来源入口与原文所在 App；历史按天分组、可按有收藏与来源 App 筛选、详情关联收藏词条。
- [阅读查词决策](vocabulary/decisions/BDR-0008-reading-word-lookup.zh-CN.md)：只读正文 ⌘ 单击、选区工具栏／右键查询；学习行保留点击收藏，跨句旧释义标来源，手动系统发音，查询不入库。五类区域均已实现（T48–T51），待最终验收。
- [学习词形决策](learning/decisions/BDR-0009-learning-lemma.zh-CN.md)：学习契约的 `text` 用语境中的实际词形，字典形另放 `lemma`；生词本按词形收藏、原形作次级信息。
- [查词入库决策](vocabulary/decisions/BDR-0010-collect-from-lookup.zh-CN.md)：查词卡可显式「加入生词本」，保存本次查询词形、语境与释义，不另发请求；查词本身仍不自动入库。
- [界面语言决策](settings/decisions/BDR-0011-interface-language.zh-CN.md)：界面支持简体中文、繁體中文、English、日本語，默认跟随系统、设置里可覆盖；语言名跟随界面语言，选择器例外；发给模型的提示词不本地化。
- [母语决策](learning/decisions/BDR-0012-native-language.zh-CN.md)：设置里的「母语」只影响学习内容包含哪些条目（两种操作都受约束），不参与释义语言的计算。
- [本机 agent 决策](settings/decisions/BDR-0013-local-agent-provider.zh-CN.md)：Claude Code、Codex CLI 作为模型服务时只当一次性的纯补全后端——工具、技能、MCP、项目上下文与会话落盘全关；返回仍走同一份契约，配置完整性改看可执行文件而不是 API Key。
- [玻璃强度决策](settings/decisions/BDR-0014-system-liquid-glass-intensity.zh-CN.md)：液态玻璃及其强度由系统设置 › 外观统一调整；应用的「玻璃效果」只区分两种玻璃变体，并给出一句说明与打开该面板的入口，不提供自己的强度控件。
- [服务商预设决策](settings/decisions/BDR-0015-provider-presets.zh-CN.md)：`Provider` 只表示协议与两个本地 agent；HTTP 厂商是数据表 `ServicePreset`，选中即填好公开的 Base URL 与默认模型，返回格式能力跟着预设走，模型记忆按服务分槽。

Gherkin 使用英文关键字；`.feature` 中的行为描述为英文，`.zh-CN.feature` 副本为中文。示例是本次从已确认规则整理的具体说明，不要求模型输出固定措辞，且尚未绑定 step definitions。未完成的工作见 [路线图](../docs/roadmap.zh-CN.md)；技术选型不作为领域场景。

## 范围边界

最低 macOS Tahoe 26.0；无复习、同步、账号、自动收藏、学习水平评估或多版本润色。Keychain 等技术约束保留在产品定义与[工程规范](engineering.zh-CN.md)。

## 明确留待实现时确定

- 快捷键无默认组合，须由用户录制；本机签名自用，不启用 App Sandbox。项目名为 Owlet。
- 支持外部应用读取与写回的具体兼容清单；不支持时遵循已定义的手动输入／复制行为。
- 查词卡打开时，Esc 先关闭卡片并恢复正文焦点；否则关闭浮窗并取消进行中的请求。浮窗不因失去焦点关闭，点击浮窗外部或“完成”同样关闭；历史记录不恢复写回权限。
- 原实现计划建议 UTF-8 JSON 导出、仅去首尾空白进行表达匹配；这些是实施默认值，不引申为语言词形归一化需求。

## 对应任务

T 编号是历史任务标签，原任务清单已删除。

| 行为 | 实现任务 |
|---|---|
| 服务配置、翻译 | T01 |
| 快捷入口 | T02、T04、T03a |
| 安全替换、直接替换 | T03、T03a |
| 润色 | T04 |
| 历史 | T05、T06 |
| 手动收藏、生词本 | T07、T08 |
| 学习推荐 | T09 |
| 重复表达追加语境 | T10 |
| 阅读查词第一步（已实现，待最终验收） | T47–T51 |

## T59：界面语言 i18n，支持四种语言（已实现）

依据 [BDR-0011](settings/decisions/BDR-0011-interface-language.zh-CN.md)。用户要求「实现系统的 i18n，支持英语、简体和繁体中文，日语」，并允许分多个提交。

后续变更：界面的源语言已改为英文，对照表移到 `strings/translations.json`（以英文为键），`Owlet/Localizable.xcstrings` 的 `sourceLanguage` 为 `en`；发给模型的提示词不本地化。下文保留当时的验收记录。

范围与取舍：界面文字与用户可见的错误文案进 `Localizable.xcstrings`（源语言简体中文，另存 English／繁體中文／日本語）；发给模型的提示词、任务描述与示例保持中文；界面语言默认跟随系统，设置里可覆盖，下次启动生效。

验收：

- [x] `project.yml` 声明 `developmentLanguage: zh-Hans`；四种语言随构建产出 `en／zh-Hans／zh-Hant／ja` 四个 `lproj`。
- [x] 目录由 `scripts/build-strings.py` 的对照表生成，`mise run lint` 校验两者一致；测试断言「每条四语齐全」且「源语言等于 key」。
- [x] 设置「通用」页可选「跟随系统／简体中文／繁體中文／English／日本語」，写入 `AppleLanguages` 且在构建视图前生效；`AppLanguage.resolve` 为纯函数并覆盖四类输入。
- [x] 语言名跟随界面语言；「界面语言」选择器例外，用 `Text(verbatim:)` 显示各语言自己的名字。
- [x] 「按失败类型选恢复入口」不再依赖文案：`ModelError.Kind` 扩为契约／连接／服务，`Notice.failure` 与 `TextProcessingModel.State.failure` 携带它；`DebugExchange` 携带 `failureKind`。
- [x] `mise run i18n` 以产物 `en.lproj` 为准列出未翻译的界面串；当前报告三种语言全覆盖（236 条）。

验证：`mise run check` 退出码 0，345 项测试通过；用 Foundation 本体解析产物，四种语言对同一批键各自正确（`界面语言／生词本／翻译／润色／取消处理／加入生词本／查询／设置…` 与两个插值串）。`scripts/check-i18n.py` 报告无缺口。

已知缺口（不属于本任务）：`PanelControllerTests.opensWithNothingFocusedButTraversalStillReachesTheControls` 在全量套件中偶发失败（单独连跑五次均通过），属窗口焦点类测试的隔离脆弱性，待单独处理。
