# Owlet · macOS 26 Liquid Glass 组件对照

状态：设计已更新（`design/index.html`、`design/screenshots/`），原生实现未开始。
对象：`design/screenshots/` 中出现的每一个可见组件。
目标：每个组件都对应到 macOS 26（Tahoe）原生 SwiftUI / AppKit 组件，不再手写控件，不再自定义颜色、圆角、边框、渐变与阴影。

---

## 1. 两条判据

整套对照只依据两条规则，其余都是它们的推论。

**判据一：功能层用 Liquid Glass，内容层不用。**
Liquid Glass 只属于浮在内容之上的控制与导航层——工具栏、侧边栏、面板、弹窗。内容层用系统材质，绝不叠玻璃。

> `materials.md › Liquid Glass`：**Don't use Liquid Glass in the content layer.** "Instead, use standard materials for elements in the content layer, such as app backgrounds."

**判据二：能用系统组件就不用自定义。**
系统组件自动获得 Liquid Glass 外观、`Reduce Transparency` / `Increase Contrast` / `Reduce Motion` 适配、Vibrancy、焦点环、键盘与 VoiceOver 支持。手写的等价物不会自动获得任何一项。

> `liquid-glass.md › Where the material belongs`：**Use Liquid Glass effects sparingly.** "Standard system components pick up the material automatically. If you apply it to a custom control, limit it to the most important functional elements."

推论（本项目最容易违反的三条）：

- 内容区的按钮不是玻璃按钮。工具的次要/主要按钮用 `.bordered` / `.borderedProminent`；只有浮动面板内的按钮用 `.glass` / `.glassProminent`。
- 玻璃不叠玻璃且数量受限。一屏内的玻璃按钮保持在"最重要的几个功能元素"以内。
- 一屏只有一个 prominent 动作，放在 trailing 端。

> `buttons.md › Style`：**Keep the number of prominent buttons to one or two per view.**
> `toolbars.md › Actions`：**Use the `.prominent` style for key actions such as Done or Submit.** "Only specify one primary action, and put it on the trailing side of the toolbar."

---

## 2. 本次设计更新（已落地）

更新只做两件事：把窗口骨架换成系统骨架，把控件换成系统控件。设计图里的信息结构、状态与可执行动作一个都没删；删掉的是重复与空心文案。

| # | 变更 | 之前 | 现在 | 依据 |
| --- | --- | --- | --- | --- |
| 1 | 侧边栏可收起，且是真正的 source list | 178px 固定栏，自己画红绿灯、自己画分组标题、选中态是自定义白胶囊；`设置` 与 `本地` 钉在栏底 | 工具栏 leading 端新增系统侧边栏切换按钮；`⌃⌘S` 语义；选中态用系统强调色填充；`设置` 移入"应用"分组，取消栏底钉死；`本地` 角标删除 | `sidebars.md › Best practices`；`sidebars.md › Desktop (macOS)`：**Avoid putting critical information or actions at the bottom of a sidebar.** |
| 2 | 右上角翻译／润色 + 目标语言改为工具栏控件 | 两个手写下拉框塞在 64px 自绘标题栏里 | 统一工具栏跨整窗：`简体中文` 弹出式按钮在左、`翻译｜润色` 分段控件在右，居中；选中态是系统分段控件外观 | `segmented-controls.md › Best practices`；`pop-up-buttons.md › Best practices` |
| 3 | 底部动作栏删除 | 64px 自绘 footer 放 `复制` / `翻译文本`，跨整窗固定在底部 | 两个动作移入工具栏 trailing 端；`翻译文本` 是唯一的 prominent 动作 | `windows.md › Desktop (macOS)`：**Avoid putting critical information or actions in a bottom bar, because people often relocate a window in a way that hides its bottom edge.** |
| 4 | 快捷键提示不再画在按钮里 | 按钮内嵌 `⌘ ↵` 字块 | 快捷键归菜单栏与 `.keyboardShortcut`；工具栏只留动作名 | `toolbars.md › Desktop (macOS)`：**Make every toolbar item available as a command in the menu bar.** |
| 5 | 列表搜索框改为系统搜索框 | 全宽自绘输入框 + 独立筛选下拉 | 工具栏 trailing 端的系统搜索框（放大镜、清除按钮）+ 弹出式按钮筛选 | `search-fields.md › Tablet and desktop (iPadOS, macOS)`：**Put a search field at the trailing side of the toolbar for many common uses.** |
| 6 | 空状态改为系统空状态视图 | 自绘图标 + 标题 + 按钮 | 大号次级符号 + 标题 + 一句说明 + 一个 bordered 按钮 | `writing.md › Best practices`：**Provide clear next steps on any blank screens.** |
| 7 | 列表行的删除不再常驻 | 每行常显垃圾桶 | 悬停／聚焦才出现的 borderless 图标按钮 | `lists-and-tables.md › Best practices`：**Let people edit a table when it makes sense.** |
| 8 | 处理中的呼吸灯改为整圈边框呼吸 | 1.7px 粉色渐变描边，整圈流动 | 动画直接作用在玻璃面板自身的 `border-color` 与边缘阴影上：单色（`separator` 色阶），无渐变、无新增描边、无内部 spinner；小面板（托盘）与大面板（展开）共用同一个状态 | `motion.md › Best practices`：**Add motion purposefully, supporting the experience without overshadowing it.**；`motion.md › Providing feedback`：**Aim for brevity and precision in feedback animations.** |
| 9 | 面板浮玻璃重做 | 两层渐变 + 四道内阴影 + 双层描边 | 单层半透明玻璃 + 一道发丝描边 + 一道柔和投影 | `liquid-glass.md › Review checklist` #2：**Restraint.** "Glass stacked on glass blurs the hierarchy the material was meant to create." |
| 10 | 错误与恢复入口改为按钮 | 玫瑰色下划线文字链接 | 玻璃／bordered 按钮 | `buttons.md › Content`：按钮要能被一眼认出是按钮 |
| 11 | 设置页改为 inset grouped 表单 | 每行一条贯穿分隔线 | 分组圆角容器 + 行内分隔线，容器随分组结束 | `boxes.md › Best practices`：**Consider using padding and alignment to communicate additional grouping within a box.** |
| 12 | 开关与复选框改为系统尺寸 | 34×21 开关、15px 复选框 | 38×22 开关（`NSSwitch` regular）、14px 复选框 | `toggles.md › Desktop (macOS) › Switches` |
| 13 | 焦点环改为系统焦点环 | `2px` 玫瑰色 outline，偏移 4px | 3px 强调色光晕 + 强调色描边 | `focus-and-selection.md › Best practices`：**Rely on system-provided focus effects.** |
| 14 | 新增"侧栏收起"状态图 | — | `screenshots/workspace-collapsed.png` | 证明收起态与展开态是同一套工具栏 |
| 15 | 文本处理页响应式 | 原文与译文固定上下排列 | 内容区 ≥ 720px 时并排两栏，不足则上下堆叠；新增 `workspace-narrow.png` | `layout.md › Adaptability`；`split-views.md › Desktop (macOS)`：**Set reasonable defaults for minimum and maximum pane sizes.** |
| 16 | 面板动作行改放动作 | 左侧是 `快捷键未设置` 之类的提示文字，`收藏选中内容` 浮在内容流里 | 动作行的 leading 端放 `收藏选中内容`，提示文字全部删除；`编辑原文` 仍留在内容里（它切换内容，不是提交动作） | `layout.md › Visual hierarchy`：**Group related items to clearly express related information or functions.**；`writing.md › Best practices`：**Be action oriented.** |
| 17 | 界面不再画快捷键与空提示 | 按钮与内容里散落 `⌘ ↵`、`Esc 取消`、`⌘ V 粘贴`、`录制后立即生效`、`示例模式`、空态提示行 | 快捷键归菜单栏、`.keyboardShortcut` 与 `.help()`；提示文字只留在确实需要它解释状态的地方（如快捷键录制页的说明行） | `the-menu-bar.md`：快捷键出现在菜单项右侧；`motion.md`／`writing.md`：每一行文案都要有职责 |
| 18 | 按钮改动词，去掉重复宾语 | `翻译文本`、`润色文本`、`复制译文`、`保存修改`、`保存快捷键`、`收藏整句`、`导出生词本` | `翻译`、`润色`、`复制`、`保存`、`保存`、`收藏`、`导出…` | `buttons.md › Content`：**Consider using text when a short label communicates more clearly than an icon.**；`writing.md › Best practices`：**Build language patterns.** |
| 19 | 状态总览改按窗口／面板分组 | 按流程分 16 条泳道，用箭头连线 | 按 surface 分 9 个横向分区（紧凑条 16 / 展开 6 / 学习区块 5 / 文本处理 3 / 生词本 4 / 历史 3 / 快捷键 2 / 设置 2 / 菜单栏 1），分区竖向堆叠，同一面板内状态横向换行 | 原型工具；分组后一次能看到同一 surface 的全部状态，与本文的对照表一致 |

### 文案规则

从 #16–#18 抽出三条规则，后续新增界面按它写：

1. **动作区只放动作。** 工具栏、动作行里不放解释性文字。状态由内容区、`.help()` 或菜单栏承担。
2. **界面不展示快捷键。** 快捷键的唯一出处是菜单栏（`.keyboardShortcut`）与悬停提示（`.help()`）；不把 `⌘↵` 画进按钮，也不写“快捷键未设置”。
3. **按钮用动词，宾语留给上下文。** 处在同一屏的控件已经把宾语说清楚（分段控件已选“翻译”、窗口就是“生词本”），按钮就不再重复它。只有宾语会歧义时才保留，例如设置里的 `恢复默认`、`清除筛选`。

同一屏内同一动作叫法要一致：`复制` 就一直是 `复制`，不在一处叫 `复制译文`、另一处叫 `复制结果`。

---

## 3. 组件对照总表

按 Apple HIG 的组件分类（<https://developer.apple.com/design/human-interface-guidelines/components>）排列。每一行都是"设计图里的东西 → 系统组件"。

### 3.1 组件 › 布局与组织

| 设计元素 | 出处 | 原生组件 | 备注 |
| --- | --- | --- | --- |
| 主窗口骨架（侧栏 + 内容） | 全部完整窗口截图 | `NavigationSplitView` + `List(selection:)` + `.listStyle(.sidebar)` | 桌面端侧栏用 `NavigationSplitView`，不用 `TabView`。 |
| 侧边栏本体 | `workspace.png`、`settings.png`、`book-list.png`、`history-list.png`、`shortcuts.png` | `List` 的 sidebar 外观；`NavigationSplitViewVisibility` 持久化 | 系统负责材质、选中态、键盘导航与 VoiceOver。 |
| 侧栏分组标题（随手处理／我的积累／应用） | 同上 | `List` 内的 `Section("…")` | 不再手写 `.section-label`。 |
| 侧栏行（图标 + 标题 + 计数） | 同上 | `Label` + `.badge(3)` | 计数用 `.badge`，不画胶囊。 |
| 侧栏选中态（玫瑰胶囊） | 同上 | 系统 source list 选中外观 | `sidebars.md`：图标默认跟随系统强调色；`color.md › App accent colors` 允许应用指定 accent。 |
| 侧边栏显示／隐藏 | 新增的切换按钮、`workspace-collapsed.png` | 系统侧栏切换工具栏项 + `⌃⌘S` + 视图菜单 `Show/Hide Sidebar` | `sidebars.md › Best practices`：**Consider letting people hide the sidebar.** |
| 快捷键页的"全局／应用内"分组 | `shortcuts.png`、`settings-shortcuts.png` | `Form` + `Section`（`.formStyle(.grouped)`） | 分组容器由系统绘制。 |
| 生词本／历史列表条目 | `book-list.png`、`history-list.png`、`no-results.png` | `List(selection:)` 行 + `.contextMenu` + `onDelete` | macOS 没有 swipe actions；删除放上下文菜单与工具栏。 |
| 语言标签（EN／JA） | `book-list.png`、`history-list.png` | `.badge` 或次级 `Text` | 别用自绘圆角方块。 |
| 逐句对照分组 | `aligned.png`、`long.png` | `List` 或 `LazyVStack` + `Text` | 配对关系来自模型返回，不按显示行推断。 |
| 空状态 | `book-empty.png`、`history-empty.png`、`no-results.png` | `ContentUnavailableView { label: } description: { } actions: { }` | 三个状态共用同一个系统视图，只改文案与动作。 |
| 原句语境引用块 | `book-detail.png`、`history-detail.png` | `GroupBox` 或 `.background(.quaternary)` 内可选中 `Text` | `boxes.md`：盒子要小于容器，别嵌套盒子。 |
| Prompt 编辑区 | `settings-prompts.png` | `TextEditor` + `DisclosureGroup` | 展开默认 Prompt 用系统 disclosure。 |
| 设置分区 | `settings.png`、`settings-prompts.png` | `Form` + `Section`，`.formStyle(.grouped)` | 见 §6 关于设置窗口本身的建议。 |
| 分栏分隔线 | 全部完整窗口截图 | `NavigationSplitView` 自带 divider | 永不自绘 1px 竖线。 |

### 3.2 组件 › 菜单与操作

| 设计元素 | 出处 | 原生组件 | 备注 |
| --- | --- | --- | --- |
| 顶部工具栏 | 全部完整窗口截图 | `.toolbar { ToolbarItem(placement:) }` + `.navigationTitle` | 跨整窗，位于侧栏之上。 |
| 工具栏分组与空隙 | `workspace.png` | `ToolbarItemGroup` + `ToolbarSpacer(.fixed)` | `toolbars.md › Item groupings`：最多三组。 |
| `翻译｜润色` 选择 | `workspace.png`、`workspace-collapsed.png` | `Picker(...).pickerStyle(.segmented)`，`ToolbarItem(placement: .principal)` | `segmented-controls.md › Content`：段标签用名词，标题式大小写。 |
| `简体中文` 目标语言 | `workspace.png`、`result.png`、`aligned.png` | `Picker(...).pickerStyle(.menu)` = 原生弹出式按钮，放在分段控件左侧 | `pop-up-buttons.md`：互斥选项用 pop-up，动作列表用 pull-down。 |
| `复制` | `workspace.png`、`result.png`、`book-detail.png`、`history-detail.png` | `ToolbarItem(placement: .primaryAction)` 上的 Button；文本域聚焦时走系统 `Edit > Copy`（`⌘C`） | 不要用 `⌘C` 覆盖系统复制。同一动作一律叫 `复制`。 |
| `翻译` / `润色` | `workspace.png`、`workspace-narrow.png` | `Button(...).buttonStyle(.borderedProminent)`（内容区）或工具栏 `.prominent`；`.keyboardShortcut(.return, modifiers: .command)` | 每屏唯一 prominent。按钮只用动词：宾语由分段控件与窗口标题提供。 |
| `保存` / `收藏` / `导出…` | `settings*.png`、`shortcuts.png`、`book-detail.png`、`history-detail.png`、`book-list.png` | 同上，trailing 端 prominent；`导出…` 配 `.fileExporter` | 同一条文案规则：宾语由当前窗口提供，不写进按钮。 |
| 浮动面板头部：重试 / 设置 | `result.png`、`polish.png`、`learning*.png` | 面板内 `Button(systemImage:).buttonStyle(.glass)`，包在 `GlassEffectContainer` 中 | 面板是功能层，玻璃按钮成立。 |
| 浮动面板头部：操作选择 `翻译 ▾` | `result.png`、`polish.png`、`success.png` | `Picker(...).pickerStyle(.menu)`，`.buttonStyle(.borderless)` | 等价于菜单按钮。 |
| 浮动面板底部动作行：`收藏选中内容` / `复制` / `替换` / `完成` | `result.png`、`polish.png`、`learning.png`、`saved.png`、`success.png`、`stale.png` | leading 端 `Button("收藏选中内容").buttonStyle(.glass)`（次级，无结果时隐藏）；trailing 端 `Button(.glass)` + `Button(.glassProminent)`，包在 `GlassEffectContainer` 中 | 动作行只放动作，不放提示文案（见 §2 文案规则）。`编辑原文` 仍留在内容区，因为它切换的是内容。 |
| `取消`（处理中） | `loading.png`、`direct-loading.png` | 紧凑条内 `Button(.glass)` | `progress-indicators.md`：**When it's feasible, let people halt processing.** |
| `清除` 快捷键 | `shortcuts.png` | `Button("清除").buttonStyle(.borderless).controlSize(.small)` | |
| `导出…` | `book-list.png` | `Button` + `.fileExporter`，或不带省略号的 `ShareLink` | `buttons.md › Desktop (macOS) › Push buttons`：**Append a trailing ellipsis to the title when a push button opens another window, view, or app.** |
| `清空历史` | `history-list.png` | `Button(role: .destructive)` + 确认对话框；实现时归入应用专属"历史"菜单 | `menus.md › Organization`：破坏性动作放菜单。 |
| `重试学习内容` | `learning-error.png` | `Button` 内联在提示行内 | |
| 应用菜单栏 | 未在截图中，但 `menubar.png` 隐含 | `CommandGroup` / `CommandMenu`：App / File / Edit / View / 处理 / Window / Help | `the-menu-bar.md › App menu`：`Settings…`、`Hide`、`Quit` 由系统提供，顺序固定。 |
| 菜单栏常驻图标 | `menubar.png` | `MenuBarExtra` + `Menu` | `the-menu-bar.md › Menu bar extras`：**Display a menu — not a popover — when people click your menu bar extra.** |

### 3.3 组件 › 导航与搜索

| 设计元素 | 出处 | 原生组件 | 备注 |
| --- | --- | --- | --- |
| 侧栏导航（文本处理／生词本／历史记录／快捷键／设置） | 全部完整窗口截图 | `List(selection:)` 绑定 `enum Page` | 导航不等于动作。 |
| 列表 → 详情 | `book-detail.png`、`history-detail.png` | `NavigationStack` 或 `NavigationSplitView` 的列选择 | 详情是导航层级，不是新窗口。 |
| `← 返回列表` | `book-detail.png`、`history-detail.png` | 系统返回按钮（`.navigation` placement），用 `chevron.backward` | `toolbars.md › Navigation`：**Use the standard Back and Close buttons.** |
| 搜索表达或释义 / 搜索原文或结果 | `book-list.png`、`history-list.png` | `.searchable(text:placement:)`，工具栏 trailing 端 | `search-fields.md`：边打边搜。 |
| `全部语言` / `全部类型` | 同上 | `Picker(.menu)` 作为工具栏项；若要作为搜索范围则用 `.searchScopes` | `search-fields.md › Scope bars and tokens` |

### 3.4 组件 › 呈现

| 设计元素 | 出处 | 原生组件 | 备注 |
| --- | --- | --- | --- |
| 浮动工具条窗口 | 全部浮窗截图 | `NSPanel`（`.borderless`, `.nonactivatingPanel`, `.floating`）+ `NSGlassEffectView` | 已实现，保留。玻璃由 window server 绘制。 |
| 浮窗圆角与投影 | 同上 | `NSGlassEffectView.cornerRadius` + `hasShadow` | 不叠加自绘边框、渐变与内阴影。 |
| 紧凑处理条 | `loading.png`、`polish-loading.png`、`direct-loading.png` | `NSGlassEffectView` 容器（regular 变体）+ `Text`；进度由容器自身边缘的呼吸承载 | 见 §7 例外 1。按 `spec/product.md` 不显示终止按钮，Esc 取消。 |
| 紧凑提示条（失败／权限／未配置／取消／选区失效） | `error.png`、`permission.png`、`unconfigured.png`、`cancelled.png`、`stale.png` | 同上容器 + `Label` + 一个恢复按钮 | 见 §7 例外 2。 |
| 展开态内联状态行 | `error.png`、`format-error.png`、`cancelled.png`、`stale.png`、`success.png` | `Label(systemImage:)` + 恢复按钮，放进内容流 | 错误用 `exclamationmark.triangle`，成功用 `checkmark.circle`；不靠颜色单独表意。 |
| 权限未授权引导 | `permission.png` | `AXIsProcessTrustedWithOptions` 系统提示 → 打开"系统设置 › 隐私与安全性 › 辅助功能" | 不用自绘弹窗。 |
| 确认清空历史 | `history-list.png` 的动作 | `.alert` / `.confirmationDialog`，Cancel 为默认 | `alerts.md`：破坏性动作给警告与 Cancel。 |
| `已复制` 提示条 | 交互反馈 | 删除；结果本身已在界面上，剪贴板即是反馈 | `feedback.md › Best practices`：**Consider integrating status feedback into your interface.** 可选替代：面板内一行短暂 `Label`。 |
| 设置窗口 | `settings.png`、`settings-prompts.png` | `Settings` scene + 分栏 `TabView`（通用／显示／提示词／服务），固定不可自定义工具栏 | `settings.md › Desktop (macOS)`：**In your settings window, use a noncustomizable toolbar that remains visible and always indicates the active toolbar button.** |
| 滚动内容与栏的衔接 | 长列表、`long.png` | `.scrollEdgeEffectStyle(.soft, for: .top)` | `layout.md › Visual hierarchy`：**Differentiate controls from content.** 不要用半透明底色代替材质。 |

### 3.5 组件 › 选择与输入

| 设计元素 | 出处 | 原生组件 | 备注 |
| --- | --- | --- | --- |
| 原文输入区 | `workspace.png`、`result.png`、`empty.png`、`book-detail.png` | 多行 → `TextEditor`；单行 → `TextField(axis: .vertical)` | `text-views.md › Best practices`：长可编辑文本用 text view。 |
| 中文释义 / 语境编辑 | `book-detail.png` | `TextEditor`（`Form` 行内） | |
| Base URL / 模型名称 | `settings.png` | `TextField`（`Form` 行内） | |
| API Key | `settings.png` | `SecureField` | `entering-data.md`：永不预填密码。 |
| Prompt 文本 | `settings-prompts.png` | `TextEditor` | |
| `翻译显示方式` / `服务商` / `模型名称` / `浮窗位置` | `settings.png` | `Picker(...).pickerStyle(.menu)` | `pickers.md › Best practices`：短列表用弹出式按钮，不用 picker。 |
| `翻译 · 自动请求学习表达` / `润色 · 自动请求学习表达` | `settings.png` | `Toggle(...).toggleStyle(.switch)`，`Form` 行内；紧凑表单可用 `.controlSize(.mini)` | `toggles.md › Desktop (macOS) › Switches` |
| 学习表达勾选 | `learning.png`、`saved.png` | `Toggle(...).toggleStyle(.checkbox)` | `toggles.md`：多选与层级用复选框，不用开关。 |
| 快捷键录制控件 | `shortcuts.png`、`settings-shortcuts.png` | **无系统组件**。用 `Button` + `.buttonStyle(.bordered)`，录制中换成强调色描边；全局注册走 Carbon / `NSEvent` | 见 §7 例外 3。 |
| `⌘ ↵` / `Esc` 字块 | `shortcuts.png`、`result.png`、`success.png` | 删除。快捷键由菜单栏、`.keyboardShortcut` 与 `.help()` 呈现；`快捷键` 页面本身仍列出绑定，因为那是该页的内容 | `the-menu-bar.md › Edit menu`：快捷键出现在菜单项右侧。 |
| 输入框聚焦态 | 全部输入 | 系统焦点环（`focusEffect`／`.focusable()`） | `focus-and-selection.md`：**Rely on system-provided focus effects.** |

### 3.6 组件 › 内容与状态

| 设计元素 | 出处 | 原生组件 | 备注 |
| --- | --- | --- | --- |
| 译文／润色结果 | `result.png`、`polish.png`、`aligned.png` | `Text` + `.textSelection(.enabled)`；字号用语义字体（`.body` / `.title3`） | `labels.md › Best practices`：**Make useful label text selectable.** |
| 原文／译文分区标签行 | `result.png`、`workspace.png` | `LabeledContent` 或 `Section` 头 | 用 `.secondary` 而不是自绘 muted 色。 |
| 处理中骨架屏 | `polish-loading.png`、`learning-loading.png` | `.redacted(reason: .placeholder)` 作用在真实内容上 | 不手绘灰条。 |
| 处理中指示 | `loading.png`、`polish-loading.png`、`direct-loading.png`；展开态重新处理同上 | 面板玻璃边缘的呼吸：`border-color` 与边缘阴影在两档之间循环（2.1s）。不叠加 spinner；状态文字是动效之外的载体 | 见 §7 例外 1。不使用 `ProgressView`：进度不可量化，而 `spec/product.md` 已指定整圈呼吸灯。 |
| 学习表达推荐列表 | `learning.png` | `LabeledContent` 行 + 复选框 `Toggle` | 推荐是 AI 输出：默认手动触发已满足"先问再做"。 |
| `收藏所选 0` | `learning.png`、`saved.png` | `Button`，计数写在标签里，`.disabled(count == 0)` | |
| `✓ 已加入生词本 查看` | `saved.png` | `Label(systemImage: "checkmark")` + `Button("查看")` 切换侧栏选择 | 就地反馈，不跳转。 |
| `✓ 已替换原选区，结果已保留在历史。` | `success.png` | `Label(systemImage: "checkmark.circle")`，`.foregroundStyle(.secondary)`；可选 `.tint(.green)` | `feedback.md`：确认重要动作完成；不要用颜色单独表意。 |
| 翻译／润色标签 | `history-list.png` | `.badge("翻译")` | |

### 3.7 系统体验

| 设计元素 | 出处 | 原生组件 | 备注 |
| --- | --- | --- | --- |
| 菜单栏常驻入口 | `menubar.png` | `MenuBarExtra` + `Menu` | `the-menu-bar.md › Menu bar extras` |
| 全局快捷键 | `shortcuts.png` | 无系统 API 提供"用户可录制"的 UI；注册用 Carbon `RegisterEventHotKey` | 见 §7 例外 3 |
| 应用图标 | `design/logo/`、`screenshots/*` 的 Dock 表现 | `AppIcon` 资源目录，含 light / dark / tinted 变体 | `app-icons.md`：分层、无文字、无 UI 复刻。 |

---

## 4. 逐屏对照

与 `design/index.html` 的"状态总览"同一分组：先浮动面板（紧凑条、展开、学习区块），再应用窗口（文本处理、生词本、历史、快捷键、设置），最后菜单栏。

| 截图 | 已落到设计里的系统组件 |
| --- | --- |
| `workspace.png` | 统一工具栏（跨整窗）· 侧栏切换 · 弹出式按钮 `简体中文` · 分段控件 `翻译｜润色` · 次级按钮 `复制` · prominent 按钮 `翻译` · 系统侧边栏与选中态 · `TextEditor` · 内容区两栏并排（原文 ｜ 译文，中间一道发丝分隔）· 分区标题行 |
| `workspace-collapsed.png` | 同一套工具栏；`NavigationSplitViewVisibility` 收起态 |
| `workspace-narrow.png` | 同一页在 760px 窗口下的堆叠布局；工具栏自动收紧 |
| `shortcuts.png` | `Form` 分组 · 录制按钮（例外 3）· 次级 `Text` 说明 · 全局 prominent `保存` |
| `settings.png` | inset grouped `Form` · 弹出式按钮 · 开关 · 分组容器 |
| `settings-prompts.png` | `TextEditor` · `DisclosureGroup`（查看默认 Prompt）· `Button("恢复默认")` |
| `settings-shortcuts.png` | 同 `shortcuts.png`，从设置入口进入 |
| `book-list.png` / `history-list.png` | 工具栏搜索框 · 筛选弹出式按钮 · `导出…` / 清空（destructive）· `List` 行 · 悬停显示的行内删除 · 语言 `.badge` |
| `book-empty.png` / `history-empty.png` / `no-results.png` | `ContentUnavailableView` 三段式：符号 · 标题 + 说明 · 一个 bordered 动作 |
| `book-detail.png` / `history-detail.png` | 工具栏返回按钮 · `复制` · prominent `保存` / `收藏` · `TextEditor` · `GroupBox` 语境块 |
| `result.png` / `polish.png` / `aligned.png` / `long.png` | `NSGlassEffectView` 面板 · 头部 `Picker(.menu)` + 玻璃图标按钮 · 可选中结果文本 · 动作行 leading `收藏选中内容` + trailing `复制` / `替换` |
| `learning.png` / `learning-loading.png` / `learning-error.png` / `learning-empty.png` / `saved.png` | 系统 disclosure（学习表达）· 复选框 `Toggle` · `.redacted` 占位 · 内联 `Label` 反馈 · 计数按钮 · 动作行同上 |
| `empty.png` | 无结果区时的纯输入态：`TextEditor` + 空态提示 + prominent 提交 |
| `loading.png` / `polish-loading.png` / `direct-loading.png` | 紧凑玻璃条 · 整圈边框呼吸（单色、无渐变）· 选中文字摘要 · 状态文字；不显示终止按钮，Esc 取消 |
| `error.png` / `format-error.png` / `permission.png` / `unconfigured.png` / `cancelled.png` / `stale.png` / `selection-error.png` 及其 `direct-*` 变体 | 紧凑玻璃条 · 一行说明 · 一个恢复按钮（服务设置／提示词设置／权限设置／重新读取／配置服务／复制／重新处理） |
| `success.png` | 内联 `Label` 成功反馈 · prominent `完成 esc` |
| `menubar.png` | `MenuBarExtra` 菜单（非 popover） |

---

## 5. 设计令牌退役表

`spec/DESIGN.md` 的配色表与 `RoseGlass`（`PanelController.swift`、`TranslationView.swift`）在实现时必须整体删除。

| 现令牌 | 现用途 | 替换为 |
| --- | --- | --- |
| `RoseGlass.accent` | 主按钮、焦点、开关、选中态 | 应用 `AccentColor` 资源（唯一允许的品牌色出口）；视图内用 `.tint(nil)` 跟随系统 |
| `RoseGlass.ink` | 正文与标题 | `.primary` / `NSColor.labelColor` |
| `RoseGlass.muted` | 标签与次要文字 | `.secondary` / `NSColor.secondaryLabelColor` |
| `RoseGlass.paper` | 内容底 | `Color(nsColor: .textBackgroundColor)` 或系统纸张材质 |
| `RoseGlass.line` | 分隔线 | `Divider()` / `NSColor.separatorColor` |
| `RoseGlass.selectedNav` | 侧栏选中 | 系统 source list 选中外观 |
| `RoseGlass.tint` / `keyFill` | 录制中底色、键帽底 | 系统控件默认外观 |
| `RoseGlass.errorFill` / `errorText` | 错误块 | `.foregroundStyle(.red)` + 系统材质底，或纯 `Label` |
| `RoseGlass.green` | 成功 | `.green`（语义系统色） |
| `RoseGlass.skeleton` | 骨架屏 | `.redacted(reason: .placeholder)` |
| `RoseGlass.window` / `sidebar` / `footerFill` | 窗口／侧栏／底栏底 | 系统窗口背景、`List` sidebar 外观、工具栏材质 |
| `MainButtonStyle` / `MainLabelStyle` | 自绘按钮 | `.bordered` / `.borderedProminent` / `.glass` / `.glassProminent` |
| `FieldBox` | 自绘输入框描边与焦点环 | `Form` 行内的系统 `TextField` + 系统焦点环 |
| `SelectField` | 自绘下拉 | `Picker(.menu)` |
| `KbdChip` | 键帽 | 删除；快捷键归菜单栏与 `.help()` |
| `GroupTitle` / `FormRow` / `PageFooter` / `PageHeader` / `SectionLabel` / `NavRow` | 自绘窗口零件 | `Form` + `Section`、`.toolbar`、`List` |
| `ProcessingStrip` / `NoticeStrip` | 紧凑条零件 | 保留玻璃容器，内部只用 `ProgressView`、`Text`、`Label`、`Button(.glass)` |
| `Skeleton` / 粉色渐变呼吸描边 | 处理中装饰 | 骨架屏改 `.redacted`；呼吸改单色边框动画 |

`spec/DESIGN.md` 的颜色表保留为历史记录，并在文件顶部标注"已由本文与原生组件取代"。

---

## 6. 关于设置窗口的建议（未改动设计图）

设计图把设置画成主窗口的一个页面。`settings.md › Desktop (macOS)` 要求设置是**独立窗口**：从应用菜单（`⌘,`）打开，工具栏分栏、分栏按钮常驻且不可自定义，最小化与缩放按钮置灰，窗口标题跟随当前分栏。

实现时：

1. 设置改为 `Settings` scene + 分栏 `TabView`：**通用**（翻译显示方式、浮窗位置）· **显示** · **提示词** · **服务**（Base URL、API Key、模型）。
2. 侧栏不再出现 `设置` 行；工具栏也不放设置按钮。

> `settings.md › Desktop (macOS)`：**Include a settings item in the App menu.** "Avoid adding settings buttons to a window's toolbar, because doing so decreases the space available for essential commands that people use frequently."

设计图暂时保留侧栏入口，是为了让原型可被点击探索；`settings.png` 的**内容**（inset grouped 表单）与最终实现一致。

---

## 7. 判断与例外

macOS 26 没有提供系统对应物的四处，必须保留自定义。它们都不是“换个控件就能解决”的样式问题，而是系统没有对应物的行为或状态呈现，因此不违反判据二。

**例外 1 · 处理中的整圈边框呼吸。** 两个系统组件都不适用：`ProgressView` 是圆形或条形，不能沿已有玻璃边缘呼吸；而“单行状态条”本身在 macOS 上也没有对应控件（带内容的托盘才带操作行）。做法：保留 `NSGlassEffectView`（regular 变体）作托盘，内容只用 `Text` 与 `Button`；进度不改结构，只把动画作用在面板自身的 `border-color` 与边缘阴影上，单色 `separator` 色阶、2.1s 循环，无渐变、无新增描边、无 spinner。`NSGlassEffectView` 管材质，呼吸只管它自己的边。

实现要点：

- 静止态（动画未运行或 `Reduce Motion` 开启）也保留亮边，因此取消动画不会得到一个无标记的面板。
- 状态文字（`翻译中…`）是动效之外的另一个载体，满足 `motion.md`：**Make motion optional.** "avoid using it as the only way to communicate important information."。
- 面板尺寸与位置不随呼吸变化，只变描边与阴影，不会引发重新布局。
- 原生侧可用 `CABasicAnimation` 作用在 `NSGlassEffectView` 所在层的 `borderColor` 与 `shadowOpacity`，或用一个 `@State` 驱动的 `TimelineView` 改`.overlay` 描边透明度；不新增视图层级。

**例外 2 · 内联提示行。** macOS 没有系统 banner。`feedback.md` 要求状态反馈就近呈现、`alerts.md` 要求 alert 只用于关键信息，二者都不适用于"连接失败，请检查模型服务"。做法：`Label(systemImage:)` + 一个恢复 `Button`，放在内容流内。失败态另给符号，不靠颜色单独表意。

**例外 3 · 全局快捷键录制控件。** 没有任何系统 API 提供"点击后录制组合键"的 UI，Carbon 的 `RegisterEventHotKey` 只负责注册。做法：`Button` + `.bordered`，录制中换成强调色描边；保留 `Esc` 取消、`Delete` 清除、冲突提示；提供 `accessibilityLabel` 与 `accessibilityValue`。这是本项目唯一不可避免的自定义控件。

**例外 4 · 逐句对照布局。** 没有任何系统组件表达"原文／译文按语义句子配对"。做法：`LazyVStack` 内的配对视图，子元素全部是系统 `Text`；配对关系由模型返回，不按显示行推断。

**其余判断（我的判断，不是 Apple 的条文）：**

- 粉色保留为应用强调色。`color.md › App accent colors` 允许应用指定 accent；只要它只出现在强调色、prominent 按钮、选中态与状态指示，就符合 `liquid-glass.md › Color on glass`。**不要**把它散布到每个视图的 tint。
- `本地` 角标删除。它不承载可操作信息，属于装饰；数据存放位置应写在设置的"服务"分栏里。
- `已复制` toast 建议删除。复制成功时结果已经在界面上，剪贴板本身即是反馈。
- 面板头部的 Owlet 标记目前是白色 PNG，在浅色玻璃上几乎不可见。实现时改用可着色符号（`.symbolRenderingMode(.monochrome)`）或 template 图像，让它随外观反转。
- 列表行的删除按钮悬停才出现，键盘用户通过上下文菜单与工具栏删除同样可达。

---

## 8. 验收清单

实现完成后逐条核对：

1. **层纪律。** 玻璃只出现在工具栏、侧边栏、浮动面板、弹出视图。内容区、卡片、列表行、分组容器一律无玻璃。
2. **玻璃数量。** 一屏内的自定义玻璃表面不超过"最重要的几个功能元素"。面板内不再叠玻璃于玻璃之上。
3. **颜色预算。** 每屏最多一个 tinted prominent 动作。控制标签单色。品牌色只在强调色、prominent 动作与状态指示。
4. **辅助功能。** `Reduce Transparency` 有实底回退；`Increase Contrast` 有更强描边；`Reduce Motion` 去掉展开动画，并把边框呼吸静止为稳定亮边（`ExpandedPanel` 已有 `reduceMotion` 分支）。`workspace-collapsed.png` 与展开态的功能完全一致。
5. **对比度。** 正文 ≤17pt 达 4.5:1；≥18pt 或粗体达 3:1。玫瑰 `oklch(47% .17 350)` 在白底上约 8:1，作为强调色安全；白字在其上约 8:1。所有次要文字用 `.secondary` 由系统保证。
6. **点击区。** 桌面端默认 28×28pt，最小 20×20pt。工具栏图标按钮 28×28；列表行高不低于 28pt。
7. **字号。** 桌面端默认 13pt，最小 10pt，不出现细体小字。
8. **键盘。** 每个工具栏项都有对应菜单栏命令与快捷键（`toolbars.md › Desktop (macOS)`）；焦点环可见；`Full Keyboard Access` 下可达每个控件。
9. **深色外观。** 无硬编码颜色后，浅色与深色都要过一遍；无应用级外观开关。
10. **菜单栏。** `Settings… (⌘,)` 在应用菜单；`Show/Hide Sidebar (⌃⌘S)` 在视图菜单；`编辑` 菜单提供 `Undo/Redo/Cut/Copy/Paste/Select All`。
11. **适应宽度。** 从最小宽度到满宽连续拖动，文本处理页在 720pt 处切换并排／堆叠，无跳变、无截断、无重排抖动；窄窗口下工具栏自动 overflow。
12. **文案。** §2 的三条文案规则无例外；界面里找不到快捷键字块与空心提示。

已可运行的自动检查：

- 浏览器控制台 `checkDesignStates()` → 42 个状态全部有工具栏或动作行，浮窗动作不被裁切。
- 浏览器控制台 `checkFlowBoard()` → 42 个状态全部出现在总览上，无重复，分组数与定义一致（9 个窗口／面板）。

---

## 9. 迁移顺序（暂不实现）

按影响面从小到大，每一步都可独立验证。

| 步骤 | 内容 | 验证 |
| --- | --- | --- |
| 1 | 删除 `RoseGlass` 与自绘按钮样式，全部换成系统语义色与系统按钮 | 浅色／深色截图对比，无硬编码色残留 |
| 2 | 设置改为 `Settings` scene + 分栏；侧栏与工具栏移除设置入口 | `⌘,` 打开，`settings.md` 逐条核对 |
| 3 | 主窗口改 `NavigationSplitView`：侧栏可收起、选中态系统化、计数用 `.badge` | 收起／展开同功能，`⌃⌘S` 生效 |
| 4 | 工具栏就位：`navigationTitle` + 弹出式按钮（左）+ 分段控件（中）+ trailing prominent | 窄窗时系统自动 overflow，不手动加"更多"菜单 |
| 5 | 删除底部动作栏，动作与状态迁入工具栏与内容区 | 窗口缩到最小高度时动作仍可见 |
| 6 | 文本处理页响应式：内容区 ≥720pt 两栏并排，不足则堆叠 | 连续拖动窗口，无跳变与截断 |
| 7 | 列表换 `List` + `.searchable` + `ContentUnavailableView` + 上下文菜单 | 空、无匹配、有数据三态 |
| 8 | 浮动面板：呼吸边框、紧凑条不显示终止按钮、动作行改放 `收藏选中内容` | 处理中／失败／取消／成功四态；`Reduce Motion` 下呼吸静止 |
| 9 | 菜单栏补全并收口文案 | 每个工具栏项都能在菜单栏找到；界面里无快捷键字块与空心提示 |
| 10 | 辅助功能与外观终检 | §8 全部 12 条 |

---

## 10. 参考

本项目的 HIG 参考资料位于 `.pi/skills/apple-design/references/`。

- `.pi/skills/apple-design/references/hig/liquid-glass.md` · `Where the material belongs` / `Which variant` / `Color on glass` / `Review checklist`
- `hig/materials.md` · `Liquid Glass` / `Standard materials`
- `hig/color.md` · `Liquid Glass color` / `System colors` / `App accent colors`
- `hig/layout.md` · `Visual hierarchy`
- `hig/designing-for-macos.md` · `Best practices`
- `hig/sidebars.md` · `Best practices` / `Desktop (macOS)`
- `hig/toolbars.md` · `Best practices` / `Titles` / `Actions` / `Item groupings` / `Desktop (macOS)`
- `hig/segmented-controls.md` · `Best practices` / `Content`
- `hig/pop-up-buttons.md`、`hig/menus.md`、`hig/the-menu-bar.md`
- `hig/windows.md` · `Desktop (macOS)`；`hig/panels.md`；`hig/split-views.md`
- `hig/lists-and-tables.md`、`hig/boxes.md`、`hig/labels.md`、`hig/text-views.md`
- `hig/search-fields.md` · `Tablet and desktop (iPadOS, macOS)`
- `hig/settings.md` · `Best practices` / `Desktop (macOS)`
- `hig/toggles.md` · `Desktop (macOS)`；`hig/pickers.md`；`hig/disclosure-controls.md`
- `hig/buttons.md` · `Style` / `Content` / `Role` / `Desktop (macOS)`
- `hig/progress-indicators.md` · `Best practices` / `Desktop (macOS)`
- `hig/feedback.md`、`hig/writing.md`、`hig/accessibility.md` · `Vision`、`hig/focus-and-selection.md`、`hig/dark-mode.md`
- `hig/generative-ai.md` · `Best practices`

组件分类依 Apple 官方目录：<https://developer.apple.com/design/human-interface-guidelines/components>
