# Owlet · 未实现功能清单

状态：仓库内 `design/` 已退役，不再维护旧截图状态数。当前原生布局升级见 T33；旧截图名称和逐像素说明仅作历史记录，不代表当前实现。
对象：`spec/product.md` 中已定义、但 `Owlet/` 尚未落地的功能。
目的：为每项未实现功能保留一张提案画面，并把仍无画面的部分逐条记录在此，避免产品定义随原型一起丢失。

首版实现按 [tasks/todo.md](../tasks/todo.md) 的里程碑推进。表中“任务”一列给出将来实现该功能的编号；标注“首版不做”的条目见 `spec/product.md › 首版不做`。提案画面的组件对照见 [docs/liquid-glass-components.md](liquid-glass-components.md) 第 4 节的逐屏表。

## 未实现功能

| 功能 | `spec/product.md` 章节 | 提案画面（未实现） | 任务 |
| --- | --- | --- | --- |
| 阅读查词第一步：解释、读音与手动系统发音 | 阅读中查词（第一步，部分实现） | 浮窗选区、单击与悬停已原生验收；其余四类区域未实现 | T50–T51 |
| 复习／间隔重复／掌握度 | 首版不做（另见 个人生词本） | — | 首版不做 |

查词第一步已交付浮窗结果的选区路径（选区工具栏、右键「查询所选」、Return、辅助功能动作，卡片、复用、重试与系统发音），见 [正式行为规格](../spec/vocabulary/features/word-lookup.feature)、[BDR-0008](../spec/vocabulary/decisions/BDR-0008-reading-word-lookup.md) 与 [意图记录](intent/word-lookup.md)。保留可编辑原文与学习行点击收藏，查询通过只读正文单击或选区工具栏／右键触发；跨句旧释义标明来源，不自动重查，也不写入生词本。文本处理页／生词本／历史详情与学习行尚未接入；不计入已退役 `design/` 的截图状态、分区或提案数。

其余旧状态：`empty` 已出图（[empty](../design/screenshots/empty.png)，展开面板中原文为空，`canRetry` 为假，头部无重新处理、动作行无按钮）；`direct-selection-error`、`direct-permission`、`direct-unconfigured`、`direct-error`、`direct-format-error`、`direct-cancelled` 是“翻译并直接替换”的紧凑提示，实现中由 `PanelController.Notice` 的对应分支覆盖，画面与 `selection-error`／`permission`／`unconfigured`／`error`／`format-error`／`cancelled` 逐像素相同，已随本次恢复出图；`success` 是“写回完成确认”，原生应用写回成功直接关闭浮窗，该画面保留旧布局但不再对应实现（原型未加徽标）；`settings-shortcuts` 是快捷键页的旧画面，现已由 `shortcuts-recording` 承载；`stale` 由 `unwritten` 承载。上表的提案画面均标注未实现，不改变实现现状。

- **错误文案已统一为中文，但契约失败仍只有三类。** `ModelError.message` 已全部改成中文，主窗口与浮窗共用；契约只区分「结构不符」「目标语言不一致」「原文拼接不一致」（外加截断／拒绝／网络／认证／HTTP／空内容）。要看清哪一项失败、以及模型的原始返回，须打开设置里的「调试」页。证据：`Owlet/LLM/ModelClient.swift`、`Owlet/LLM/ModelResponse.swift`、`Owlet/Debug/`。
- **设置里模型列表失败也显示原始错误。** `ServiceSettingsView.modelField` 的 `.failed` 分支渲染 `Label(message, …)`，`message` 同样来自英文的 `ModelError` 或 `localizedDescription`。证据：`Owlet/Settings/ServiceSettingsView.swift`。
- **浮窗没有可替换选区时不显示「替换」按钮，但这条路径没有可演示的入口。** `PanelRootView` 只在 `controller.selection != nil` 时传入 `replace`，因此动作行会只留「复制」；然而写回成功后 `replace(with:)` 会清空选区并关闭面板，未能构造出「面板可见、选区为空」的状态，所以设计图没有为它单独出图。证据：`Owlet/App/Panel/PanelController.swift`、`Owlet/App/Panel/ExpandedPanel.swift`。

- **同一布局下的其它错误文案没有单独出图。** 紧凑条与面板行内提示复用同一个组件：`ModelError` 的 `emptyResponse`／`truncated`／`refused` 与快捷键注册失败的 `该组合已被系统或其他应用占用，请换一个。`、`快捷键注册失败（…）。` 都只是文案不同。设计图各取一个代表状态（`format-error`、`result-notice`、`shortcuts-conflict`）。
- **已展开且原文为空时，头部没有重新处理、动作行没有主操作。** `canRetry` 要求原文非空，因此该组合下 `PanelHeader` 不显示刷新按钮、`PanelFooter` 的默认分支也不渲染按钮。清空原文栏即可到达该界面，设计图见 [empty](../design/screenshots/empty.png)。证据：`Owlet/App/Panel/ExpandedPanel.swift` 的 `canRetry`。

## 实现与产品定义的差异

以下各条是已实现代码相对 `spec/product.md` 的偏离，均给出现状与出处。

- **设置是独立窗口，且不再有整页保存按钮。** `OwletApp` 用 `Settings` scene（App 菜单与 ⌘, 由 SwiftUI 提供），主窗口侧栏只有文本处理／生词本／历史记录／快捷键；标签页为通用、语言、模型、Prompt（调试开关打开后多一页）。API Key 与 Prompt 在编辑框失焦时提交。证据：`Owlet/App/OwletApp.swift`、`Owlet/Settings/SettingsView.swift`、`Owlet/Settings/PromptSettingsPane.swift`。
- **面板在首次成功后展开，之后一直保持展开；复制与写回成功则直接关闭。** `expanded` 在首次 `.success` 时置为 `true`，此后重新处理（`.loading`）、失败、取消都保留展开态，只是结果区按 `hasResultSection`（仅 `.loading`／`.success`）显示或隐藏；复制结果（`copyResult`）与写回成功关闭浮窗，不再停留确认（`empty` 对应展开后原文被清空的界面，[empty](../design/screenshots/empty.png)）。证据：`Owlet/App/Panel/PanelController.swift` 的 `translate()`、`copyResult`、`performReplace`。
- **写回失败只有两种文案，共用同一个布局。** `inlineNotice` 在 `.success` 且 `writebackRefusal` 非空时返回它：粘贴确实没落到任何地方是 `Notice.unwritten`（"未能写回原应用"），选区可证明不能容纳文字是 `Notice.unwritable`（"原选区不可编辑"）。`ExpandedPanel` 渲染的是 `notice.message`，两个状态下布局相同、动作都是"复制结果"，因此设计图只出一张（`result-unwritten`／`unwritten`），文案变体不单独出图。

## T33 原生布局升级

按确认原型落地原生工具栏、分组、学习展开流程与管理页分栏。管理页导出、复制、编辑入口已从当前产品范围移除，不计为未实现功能；旧导出数据能力不要求删除。验证进度以 `tasks/todo.md` 的 T33 为准。

T42：当前 panel 布局以 Figma Owlet 页为准，独立状态条和结果／学习双栏替代旧浮窗截图；app 主界面保持原有布局。

通用设置中的“玻璃效果”仅影响浮窗：更透明／更高对比度（默认），即时生效并持久保留。

浮窗从处理状态以弹簧动效展开为结果面板；遵循系统减少动态效果设置。

浮窗学习界面以弹簧动效展开；点击词条整行立即切换词库收藏状态，取消立即移除，不需确认或提交；完整窗口学习流程保持不变。
