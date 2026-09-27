# Owlet · 未实现功能清单

状态：`design/index.html` 有 58 个状态：42 个对应 Swift 端已实现的功能，16 个是尚未实现功能的提案画面（画面上带“未实现”徽标，总览里各自成区）。
对象：`spec/product.md` 中已定义、但 `Owlet/` 尚未落地的功能。
目的：为每项未实现功能保留一张提案画面，并把仍无画面的部分逐条记录在此，避免产品定义随原型一起丢失。

首版实现按 [tasks/todo.md](../tasks/todo.md) 的里程碑推进。表中“任务”一列给出将来实现该功能的编号；标注“首版不做”的条目见 `spec/product.md › 首版不做`。提案画面的组件对照见 [docs/liquid-glass-components.md](liquid-glass-components.md) 第 4 节的逐屏表。

## 未实现功能

| 功能 | `spec/product.md` 章节 | 提案画面（未实现） | 任务 |
| --- | --- | --- | --- |
| 生词本：词汇／短语／整句收藏、列表、详情、搜索、语言筛选、编辑、删除、导出 | 个人生词本（收藏行为见 学习内容与收藏） | [book-list](../design/screenshots/book-list.png)、[book-detail](../design/screenshots/book-detail.png)、[book-empty](../design/screenshots/book-empty.png)、[no-results](../design/screenshots/no-results.png) | T08、T09、T11 |
| 历史记录：列表、详情、搜索、按翻译／润色筛选、删除单条、清空全部、从历史收藏 | 历史记录 | [history-list](../design/screenshots/history-list.png)、[history-detail](../design/screenshots/history-detail.png)、[history-empty](../design/screenshots/history-empty.png) | T15、T16、T17 |
| 学习表达：展开、整理中、生成失败、无推荐、勾选入库、自动请求开关 | 学习内容与收藏 | [learning](../design/screenshots/learning.png)、[learning-loading](../design/screenshots/learning-loading.png)、[learning-error](../design/screenshots/learning-error.png)、[learning-empty](../design/screenshots/learning-empty.png)、[saved](../design/screenshots/saved.png) | T10、T13 |
| 收藏选中内容：手选原文／结果片段收藏 | 学习内容与收藏 | —（无独立画面；就地反馈并入学习区块的 [saved](../design/screenshots/saved.png)） | T08 |
| 翻译显示方式 · 逐句对照：原文／译文按语义配对显示 | 翻译 | [aligned](../design/screenshots/aligned.png) | T14 |
| System Prompt 查看／编辑／保存／恢复默认 | 模型与数据设置 | [settings-prompts](../design/screenshots/settings-prompts.png) | T12 |
| 独立 Settings 窗口（现在是主窗口的侧栏页面） | 两种界面形态 | —（仍无画面；[settings-prompts](../design/screenshots/settings-prompts.png) 只画 Prompt 编辑分组） | T19 |
| 内容区响应式的原文／译文两栏并排（实现为单列 `VStack`） | 两种界面形态（布局细节见 `spec/DESIGN.md › 布局约束`） | [workspace-narrow](../design/screenshots/workspace-narrow.png)（窄窗口下的堆叠分支；宽窗口并排尚未出图） | T22 |
| 处理中的整圈边框呼吸（实现只用 `ProgressView`） | 两种界面形态 | —（仍无画面） | T24 |
| 复习／间隔重复／掌握度 | 首版不做（另见 个人生词本） | — | 首版不做 |
| 「提示词设置」恢复入口（返回格式错误时的按钮落不到 Prompt 编辑） | 定义边界 | [format-error](../design/screenshots/format-error.png)、[direct-format-error](../design/screenshots/direct-format-error.png)（展示当前按钮；落点仍是服务设置） | T12 |

其余旧状态：`empty` 已出图（[empty](../design/screenshots/empty.png)，展开面板中原文为空，`canRetry` 为假，头部无重新处理、动作行无按钮）；`direct-selection-error`、`direct-permission`、`direct-unconfigured`、`direct-error`、`direct-format-error`、`direct-cancelled` 是“翻译并直接替换”的紧凑提示，实现中由 `PanelController.Notice` 的对应分支覆盖，画面与 `selection-error`／`permission`／`unconfigured`／`error`／`format-error`／`cancelled` 逐像素相同，已随本次恢复出图；`success` 是“写回完成确认”，原生应用已落地（写回成功保留面板、按 Esc／完成关闭），原型徽标沿用旧画面；`settings-shortcuts` 是快捷键页的旧画面，现已由 `shortcuts-recording` 承载；`stale` 由 `unwritten` 承载。上表的提案画面均标注未实现，不改变实现现状。

- **主窗口的错误提示是英文原文。** `TranslationView` 对 `.failure` 直接渲染 `ModelError.message`，而该文案是英文（如 `Authentication failed. Check the API key.`、`Network error: …`）；浮窗侧则把这些映射成中文。证据：`Owlet/LLM/ModelClient.swift` 的 `ModelError.message`、`Owlet/Processing/TranslationView.swift` 的 `status`。设计图的 `workspace-error` 因此画的是英文文案。
- **设置里模型列表失败也显示原始错误。** `ServiceSettingsView.modelField` 的 `.failed` 分支渲染 `Label(message, …)`，`message` 同样来自英文的 `ModelError` 或 `localizedDescription`。证据：`Owlet/Settings/ServiceSettingsView.swift`。
- **浮窗没有可替换选区时不显示「替换」按钮，但这条路径没有可演示的入口。** `PanelView` 只在 `controller.selection != nil` 时传入 `replace`，因此动作行会只留「复制」；然而写回成功后 `replace(with:)` 会清空选区并关闭面板，未能构造出「面板可见、选区为空」的状态，所以设计图没有为它单独出图。证据：`Owlet/App/PanelController.swift`、`Owlet/App/ExpandedPanel.swift`。

- **玫瑰品牌色没有接到应用强调色。** 工程里没有 `AccentColor` 资源，也没有任何 `.tint()`；`ASSETCATALOG_COMPILER_APPICON_NAME: OwletIcon` 与目录中的 `AppIcon.appiconset` 名称还不一致。因此 `.glassProminent` 按钮、侧栏选中与工具栏强调都跟随系统强调色（默认蓝色），不是设计图里的玫瑰色。证据：`ls Owlet/Assets.xcassets`、`project.yml`、`grep -rn "tint(\|AccentColor" Owlet/` 无命中。
- **所有设计图的侧边栏都按目标画出，含尚未实现的「生词本」与「历史记录」。** 设计图描述目标形态，因此侧栏统一是「随手处理 › 文本处理」「我的积累 › 生词本 · 历史记录」「快捷键 · 设置」；实现目前只有文本处理、快捷键与设置三个页面，生词本与历史记录两个入口点了没有页面。每个画面的实现进度由「未实现」徽标与本文说明，不靠画一张不完整的侧栏来表达。
- **菜单栏没有为每个工具栏项提供命令与快捷键。** 菜单栏只有打开主界面、三个快捷键状态、`设置… (⌘,)` 与退出。面板自己的三个键（`⌘↩`、`⌘⇧C`、`Esc`）不受此影响：它们画在按钮上、由 `FloatingPanel` 的按键监听执行，并列在快捷键页的「面板内」分组。
- **同一布局下的其它错误文案没有单独出图。** 紧凑条与面板行内提示复用同一个组件：`ModelError` 的 `emptyResponse`／`truncated`／`refused`（`The service returned an empty response.`、`The result was too long and got truncated.`、`The service refused to process this text.`）与快捷键注册失败的 `该组合已被系统或其他应用占用，请换一个。`、`快捷键注册失败（…）。` 都只是文案不同。设计图各取一个代表状态（`format-error`、`result-notice`、`shortcuts-conflict`）。
- **已展开且原文为空时，头部没有重新处理、动作行没有主操作。** `canRetry` 要求原文非空，因此该组合下 `PanelHeader` 不显示刷新按钮、`PanelFooter` 的默认分支也不渲染按钮。清空原文栏即可到达该界面，设计图见 [empty](../design/screenshots/empty.png)。证据：`Owlet/App/ExpandedPanel.swift` 的 `canRetry`。

## 实现与产品定义的差异

以下各条是已实现代码相对 `spec/product.md` 的偏离，均给出现状与出处。

- **设置是主窗口的侧栏页面，不是独立窗口。** `MainView` 用 `NavigationSplitView`，`.settings` 只是 `Page` 的一个 case；`⌘,` 由 `SettingsButton` 切到该页面，应用里没有 `Settings` scene。证据：`Owlet/App/OwletApp.swift`。
- **格式错误的恢复入口到不了 Prompt 编辑器。** 格式错误时 `Notice.actionTitle` 返回"提示词设置"，但 `PanelView.recover` 把 `.failure` 一律映射到 `settings()`，而设置页只有"模型服务"与"浮窗"两个分组，没有 Prompt 编辑，只有 `DefaultPrompts` 常量。证据：`Owlet/App/PanelController.swift`、`Owlet/Processing/TranslationView.swift`、`Owlet/Settings/ServiceSettingsView.swift`、`Owlet/LLM/DefaultPrompts.swift`。
- **面板在首次成功或写回成功后展开，之后一直保持展开。** `expanded` 在首次 `.success` 或写回成功时置为 `true`，此后重新处理（`.loading`）、失败、取消都保留展开态，只是结果区按 `hasResultSection`（仅 `.loading`／`.success`）显示或隐藏；`empty` 对应展开后原文被清空的界面（[empty](../design/screenshots/empty.png)）。证据：`Owlet/App/PanelController.swift` 的 `translate()`、`performReplace`。
- **写回失败只有两种文案，共用同一个布局。** `inlineNotice` 在 `.success` 且 `writebackRefusal` 非空时返回它：粘贴确实没落到任何地方是 `Notice.unwritten`（"未能写回原应用"），选区可证明不能容纳文字是 `Notice.unwritable`（"原选区不可编辑"）。`ExpandedPanel` 渲染的是 `notice.message`，两个状态下布局相同、动作都是"复制结果"，因此设计图只出一张（`result-unwritten`／`unwritten`），文案变体不单独出图。
