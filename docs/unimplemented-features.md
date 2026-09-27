# Owlet · 未实现功能清单

状态：`design/index.html` 有 58 个状态：42 个对应 Swift 端已实现的功能，16 个是尚未实现功能的提案画面（画面上带“未实现”徽标，总览里各自成区）。
对象：`spec/product.md` 中已定义、但 `Owlet/` 尚未落地的功能。
目的：为每项未实现功能保留一张提案画面，并把仍无画面的部分逐条记录在此，避免产品定义随原型一起丢失。

首版实现按 [tasks/todo.md](../tasks/todo.md) 的里程碑推进。表中“任务”一列给出将来实现该功能的编号；标注“首版不做”的条目见 `spec/product.md › 首版不做`。提案画面的组件对照见 [docs/liquid-glass-components.md](liquid-glass-components.md) 第 4 节的逐屏表。

## 未实现功能

| 功能 | `spec/product.md` 章节 | 提案画面（未实现） | 任务 |
| --- | --- | --- | --- |
| 独立 Settings 窗口（现在是主窗口的侧栏页面） | 两种界面形态 | —（仍无画面；[settings-prompts](../design/screenshots/settings-prompts.png) 只画 Prompt 编辑分组） | T19 |
| 复习／间隔重复／掌握度 | 首版不做（另见 个人生词本） | — | 首版不做 |

其余旧状态：`empty` 已出图（[empty](../design/screenshots/empty.png)，展开面板中原文为空，`canRetry` 为假，头部无重新处理、动作行无按钮）；`direct-selection-error`、`direct-permission`、`direct-unconfigured`、`direct-error`、`direct-format-error`、`direct-cancelled` 是“翻译并直接替换”的紧凑提示，实现中由 `PanelController.Notice` 的对应分支覆盖，画面与 `selection-error`／`permission`／`unconfigured`／`error`／`format-error`／`cancelled` 逐像素相同，已随本次恢复出图；`success` 是“写回完成确认”，原生应用已落地（写回成功保留面板、按 Esc／完成关闭），原型徽标沿用旧画面；`settings-shortcuts` 是快捷键页的旧画面，现已由 `shortcuts-recording` 承载；`stale` 由 `unwritten` 承载。上表的提案画面均标注未实现，不改变实现现状。

- **主窗口的错误提示是英文原文。** `TranslationView` 对 `.failure` 直接渲染 `ModelError.message`，而该文案是英文（如 `Authentication failed. Check the API key.`、`Network error: …`）；浮窗侧则把这些映射成中文。证据：`Owlet/LLM/ModelClient.swift` 的 `ModelError.message`、`Owlet/Processing/TranslationView.swift` 的 `status`。设计图的 `workspace-error` 因此画的是英文文案。
- **设置里模型列表失败也显示原始错误。** `ServiceSettingsView.modelField` 的 `.failed` 分支渲染 `Label(message, …)`，`message` 同样来自英文的 `ModelError` 或 `localizedDescription`。证据：`Owlet/Settings/ServiceSettingsView.swift`。
- **浮窗没有可替换选区时不显示「替换」按钮，但这条路径没有可演示的入口。** `PanelView` 只在 `controller.selection != nil` 时传入 `replace`，因此动作行会只留「复制」；然而写回成功后 `replace(with:)` 会清空选区并关闭面板，未能构造出「面板可见、选区为空」的状态，所以设计图没有为它单独出图。证据：`Owlet/App/PanelController.swift`、`Owlet/App/ExpandedPanel.swift`。

- **同一布局下的其它错误文案没有单独出图。** 紧凑条与面板行内提示复用同一个组件：`ModelError` 的 `emptyResponse`／`truncated`／`refused`（`The service returned an empty response.`、`The result was too long and got truncated.`、`The service refused to process this text.`）与快捷键注册失败的 `该组合已被系统或其他应用占用，请换一个。`、`快捷键注册失败（…）。` 都只是文案不同。设计图各取一个代表状态（`format-error`、`result-notice`、`shortcuts-conflict`）。
- **已展开且原文为空时，头部没有重新处理、动作行没有主操作。** `canRetry` 要求原文非空，因此该组合下 `PanelHeader` 不显示刷新按钮、`PanelFooter` 的默认分支也不渲染按钮。清空原文栏即可到达该界面，设计图见 [empty](../design/screenshots/empty.png)。证据：`Owlet/App/ExpandedPanel.swift` 的 `canRetry`。

## 实现与产品定义的差异

以下各条是已实现代码相对 `spec/product.md` 的偏离，均给出现状与出处。

- **设置是主窗口的侧栏页面，不是独立窗口。** `MainView` 用 `NavigationSplitView`，`.settings` 只是 `Page` 的一个 case；`⌘,` 由 `SettingsButton` 切到该页面，应用里没有 `Settings` scene。证据：`Owlet/App/OwletApp.swift`。
- **面板在首次成功或写回成功后展开，之后一直保持展开。** `expanded` 在首次 `.success` 或写回成功时置为 `true`，此后重新处理（`.loading`）、失败、取消都保留展开态，只是结果区按 `hasResultSection`（仅 `.loading`／`.success`）显示或隐藏；`empty` 对应展开后原文被清空的界面（[empty](../design/screenshots/empty.png)）。证据：`Owlet/App/PanelController.swift` 的 `translate()`、`performReplace`。
- **写回失败只有两种文案，共用同一个布局。** `inlineNotice` 在 `.success` 且 `writebackRefusal` 非空时返回它：粘贴确实没落到任何地方是 `Notice.unwritten`（"未能写回原应用"），选区可证明不能容纳文字是 `Notice.unwritable`（"原选区不可编辑"）。`ExpandedPanel` 渲染的是 `notice.message`，两个状态下布局相同、动作都是"复制结果"，因此设计图只出一张（`result-unwritten`／`unwritten`），文案变体不单独出图。
