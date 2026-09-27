# Owlet · 未实现功能清单

状态：`design/index.html` 已收敛为只覆盖 Swift 端已实现的功能。
对象：`spec/product.md` 中已定义、但 `Owlet/` 尚未落地的功能。
目的：原型中被移除的设计状态不再有界面承载，逐条记录在此，避免产品定义随原型一起丢失。

首版实现按 [tasks/todo.md](../tasks/todo.md) 的里程碑推进。表中"任务"一列给出将来实现该功能的编号；标注"首版不做"的条目见 `spec/product.md › 首版不做`。设计状态的原始对照见 [docs/liquid-glass-components.md](liquid-glass-components.md) 第 4 节的逐屏表。

## 未实现功能

| 功能 | `spec/product.md` 章节 | 已移除的设计状态 | 任务 |
| --- | --- | --- | --- |
| 生词本：词汇／短语／整句收藏、列表、详情、搜索、语言筛选、编辑、删除、导出 | 个人生词本（收藏行为见 学习内容与收藏） | `book-list`、`book-detail`、`book-empty`、`no-results` | T08、T09、T11 |
| 历史记录：列表、详情、搜索、按翻译／润色筛选、删除单条、清空全部、从历史收藏 | 历史记录 | `history-list`、`history-detail`、`history-empty` | T15、T16、T17 |
| 学习表达：展开、整理中、生成失败、无推荐、勾选入库、自动请求开关 | 学习内容与收藏 | `learning`、`learning-loading`、`learning-error`、`learning-empty`、`saved` | T10、T13 |
| 收藏选中内容：手选原文／结果片段收藏 | 学习内容与收藏 | —（无独立状态；就地反馈并入学习区块的 `saved`） | T08 |
| 翻译显示方式 · 逐句对照：原文／译文按语义配对显示 | 翻译 | `aligned` | T14 |
| System Prompt 查看／编辑／保存／恢复默认 | 模型与数据设置 | `settings-prompts` | T12 |
| 独立 Settings 窗口（现在是主窗口的侧栏页面） | 两种界面形态 | `settings-shortcuts`（`settings-prompts` 同时移除） | T19 |
| 直接替换的完成确认界面（写回成功后直接关闭） | 翻译并直接替换 | `success` | T06 |
| 内容区响应式的原文／译文两栏并排（实现为单列 `VStack`） | 两种界面形态（布局细节见 `spec/DESIGN.md › 布局约束`） | `workspace-narrow` | T22 |
| 处理中的整圈边框呼吸（实现只用 `ProgressView`） | 两种界面形态 | —（处理中状态保留，未单列） | T24 |
| 复习／间隔重复／掌握度 | 首版不做（另见 个人生词本） | — | 首版不做 |
| 「提示词设置」恢复入口（返回格式错误时的按钮落不到 Prompt 编辑） | 定义边界 | `direct-format-error` | T12 |

其余被移除、但不对应任何未实现功能的状态：`empty` 是无结果的纯输入态，实现已覆盖；`direct-selection-error`、`direct-permission`、`direct-unconfigured`、`direct-error`、`direct-cancelled` 是"翻译并直接替换"的紧凑提示，实现中由 `PanelController.Notice` 的 `stale`／`permission`／`missingConfig`／`failure`／`cancelled` 覆盖。只有 `direct-format-error` 因缺少可用的恢复入口留在上表。

## 实现与产品定义的差异

以下各条是已实现代码相对 `spec/product.md` 的偏离，均给出现状与出处。

- **设置是主窗口的侧栏页面，不是独立窗口。** `MainView` 用 `NavigationSplitView`，`.settings` 只是 `Page` 的一个 case；`⌘,` 由 `SettingsButton` 切到该页面，应用里没有 `Settings` scene。证据：`Owlet/App/OwletApp.swift`。
- **格式错误的恢复入口到不了 Prompt 编辑器。** 格式错误时 `Notice.actionTitle` 返回"提示词设置"，但 `PanelView.recover` 把 `.failure` 一律映射到 `settings()`，而设置页只有"模型服务"与"浮窗"两个分组，没有 Prompt 编辑，只有 `DefaultPrompts` 常量。证据：`Owlet/App/PanelController.swift`、`Owlet/Processing/TranslationView.swift`、`Owlet/Settings/ServiceSettingsView.swift`、`Owlet/LLM/DefaultPrompts.swift`。
- **替换成功后浮窗直接关闭，没有确认屏。** `replace(with:)` 写回成功即调用 `close()`，`Notice` 没有成功分支，`ExpandedPanel` 也没有成功内联行。证据：`Owlet/App/PanelController.swift`、`Owlet/App/ExpandedPanel.swift`。
- **已展开的面板只在有结果时出现。** `expanded` 只在第一次请求成功时置为 `true`，因此 `.success` 之外没有展开内容，设计里的 `success`／`empty` 状态没有对应界面。证据：`Owlet/App/PanelController.swift` 的 `translate()`。
- **内联的选区失效提示显示的是 `Notice.stale` 的短消息，`replaceMessage` 从未显示。** `inlineNotice` 在 `.success` 且 `replaceMessage != nil` 时返回 `.stale`，`ExpandedPanel` 渲染的是 `notice.message`（"原选区已变化，未替换"）；`replaceMessage` 更完整的"原选区已变化或无法确认，未替换。可复制结果。"被赋值却没有视图读取。证据：`Owlet/App/PanelController.swift`、`Owlet/App/ExpandedPanel.swift`。
