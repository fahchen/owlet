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

- **主窗口的错误提示是英文原文。** `TranslationView` 对 `.failure` 直接渲染 `ModelError.message`，而该文案是英文（如 `Authentication failed. Check the API key.`、`Network error: …`）；浮窗侧则把这些映射成中文。证据：`Owlet/LLM/ModelClient.swift` 的 `ModelError.message`、`Owlet/Processing/TranslationView.swift` 的 `status`。设计图的 `workspace-error` 因此画的是英文文案。
- **设置里模型列表失败也显示原始错误。** `ServiceSettingsView.modelField` 的 `.failed` 分支渲染 `Label(message, …)`，`message` 同样来自英文的 `ModelError` 或 `localizedDescription`。证据：`Owlet/Settings/ServiceSettingsView.swift`。
- **浮窗没有可替换选区时不显示「替换」按钮，但这条路径没有可演示的入口。** `PanelView` 只在 `controller.selection != nil` 时传入 `replace`，因此动作行会只留「复制」；然而写回成功后 `replace(with:)` 会清空选区并关闭面板，未能构造出「面板可见、选区为空」的状态，所以设计图没有为它单独出图。证据：`Owlet/App/PanelController.swift`、`Owlet/App/ExpandedPanel.swift`。

- **玫瑰品牌色没有接到应用强调色。** 工程里没有 `AccentColor` 资源，也没有任何 `.tint()`；`ASSETCATALOG_COMPILER_APPICON_NAME: OwletIcon` 与目录中的 `AppIcon.appiconset` 名称还不一致。因此 `.glassProminent` 按钮、侧栏选中与工具栏强调都跟随系统强调色（默认蓝色），不是设计图里的玫瑰色。证据：`ls Owlet/Assets.xcassets`、`project.yml`、`grep -rn "tint(\|AccentColor" Owlet/` 无命中。
- **面板与菜单栏的 Owlet 标记在浅色玻璃上不可见。** `Image("OwletMark")` 用的是近白的 `mark-18.png`（中心像素约 252,255,255，四角透明），资源又是 `template-rendering-intent: original`，所以 `ExpandedPanel` 与 `OwletApp` 上的 `.foregroundStyle(.secondary)` 不生效，标记基本看不到。证据：`Owlet/Assets.xcassets/OwletMark.imageset/Contents.json`、`Owlet/App/ExpandedPanel.swift`、`Owlet/App/OwletApp.swift`。设计图按此如实画出，未美化。
- **按钮上的快捷键只存在于悬停提示。** `⌘↩` 之类的组合只写在 `.help()` 里，菜单栏也没有为每个工具栏项提供命令与快捷键（菜单栏只有打开主界面、三个快捷键状态、`设置… (⌘,)` 与退出）。设计图为了可读仍在按钮里画出快捷键，属于 §2.2 未采纳的建议。
- **同一布局下的其它错误文案没有单独出图。** 紧凑条与面板行内提示复用同一个组件：`ModelError` 的 `emptyResponse`／`truncated`／`refused`（`The service returned an empty response.`、`The result was too long and got truncated.`、`The service refused to process this text.`）与快捷键注册失败的 `该组合已被系统或其他应用占用，请换一个。`、`快捷键注册失败（…）。` 都只是文案不同。设计图各取一个代表状态（`format-error`、`result-notice`、`shortcuts-conflict`）。
- **已展开且原文为空时，头部没有重新处理、动作行没有主操作。** `canRetry` 要求原文非空，因此该组合下 `PanelHeader` 不显示刷新按钮、`PanelFooter` 的默认分支也不渲染按钮。这条路径没有可演示的入口，设计图未出图。证据：`Owlet/App/ExpandedPanel.swift` 的 `canRetry`。

## 实现与产品定义的差异

以下各条是已实现代码相对 `spec/product.md` 的偏离，均给出现状与出处。

- **设置是主窗口的侧栏页面，不是独立窗口。** `MainView` 用 `NavigationSplitView`，`.settings` 只是 `Page` 的一个 case；`⌘,` 由 `SettingsButton` 切到该页面，应用里没有 `Settings` scene。证据：`Owlet/App/OwletApp.swift`。
- **格式错误的恢复入口到不了 Prompt 编辑器。** 格式错误时 `Notice.actionTitle` 返回"提示词设置"，但 `PanelView.recover` 把 `.failure` 一律映射到 `settings()`，而设置页只有"模型服务"与"浮窗"两个分组，没有 Prompt 编辑，只有 `DefaultPrompts` 常量。证据：`Owlet/App/PanelController.swift`、`Owlet/Processing/TranslationView.swift`、`Owlet/Settings/ServiceSettingsView.swift`、`Owlet/LLM/DefaultPrompts.swift`。
- **替换成功后浮窗直接关闭，没有确认屏。** `replace(with:)` 写回成功即调用 `close()`，`Notice` 没有成功分支，`ExpandedPanel` 也没有成功内联行。证据：`Owlet/App/PanelController.swift`、`Owlet/App/ExpandedPanel.swift`。
- **面板只在第一次成功后才展开，之后一直保持展开。** `expanded` 只在首次 `.success` 时置为 `true`，此后重新处理（`.loading`）、失败、取消都保留展开态，只是结果区按 `hasResultSection`（仅 `.loading`／`.success`）显示或隐藏；因此设计里的 `success`／`empty` 状态没有对应界面。证据：`Owlet/App/PanelController.swift` 的 `translate()`。
- **内联的选区失效提示显示的是 `Notice.stale` 的短消息，`replaceMessage` 从未显示。** `inlineNotice` 在 `.success` 且 `replaceMessage != nil` 时返回 `.stale`，`ExpandedPanel` 渲染的是 `notice.message`（"原选区已变化，未替换"）；`replaceMessage` 更完整的"原选区已变化或无法确认，未替换。可复制结果。"被赋值却没有视图读取。证据：`Owlet/App/PanelController.swift`、`Owlet/App/ExpandedPanel.swift`。
