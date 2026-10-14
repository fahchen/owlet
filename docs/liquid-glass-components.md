# Owlet · macOS 26 Liquid Glass 组件对照

> T33 当前组件对照（取代下文旧截图中的工作台、生词本和历史布局）：设计原型仅表达布局，实际界面全部使用系统组件。`design/` 已退役，下文截图清单保留为历史记录，不代表当前界面。

| 页面 | 原生组件与当前行为 |
| --- | --- |
| 翻译与润色 | 原生 `.toolbar`：中间 `SwiftUI 承载的 NSSegmentedControl（momentary／fit）`，右侧执行 `Button`；系统 SF Symbols 与 `.help`。原文／结果用 `GroupBox`，标题与语言 `Picker(.menu)` 同排，语言靠右。 |
| 学习（工作台、历史、浮窗共用） | `PanelLearningView`：右下角学习按钮展开并按需请求；每个词条是整行按钮，点击即时切换收藏（书签图标，收藏为强调色），悬停有背景。无独立释义语言设置。 |
| 生词本 | 原生分栏、`List(selection:)` 与详情滚动区，各自滚动；工具栏搜索／筛选一组，右侧删除。无导出、复制、编辑按钮。 |
| 历史 | 同构分栏与搜索／筛选；右侧学习、删除。学习打开该条结果的学习区，勾选后加入生词本。无复制、编辑按钮。 |

不仿制 HTML 的圆角、chevron 或图标按钮外观，不自定义 `ButtonStyle`；由原生组件决定外观和辅助功能。


状态：`design/index.html` 有 66 个状态（对应 `design/screenshots/`），全部对应 `Owlet/` 已实现的功能，设计图与实现一致；唯一的例外是 `success`（写回完成确认）保留旧画面，逐条见 [docs/unimplemented-features.md](unimplemented-features.md)。对照对象是截图中每一个可见组件，目标是把它们逐一换成 macOS 26（Tahoe）原生 SwiftUI / AppKit 组件，不再手写控件，不再自定义颜色、圆角、边框、渐变与阴影。

## 1. 两条判据
**判据一：功能层用 Liquid Glass，内容层不用。** Liquid Glass 只属于浮在内容之上的控制与导航层——工具栏、侧边栏、面板、弹窗；内容层用系统材质，绝不叠玻璃。`materials.md › Liquid Glass`：**Don't use Liquid Glass in the content layer.**

**判据二：能用系统组件就不用自定义。** 系统组件自动获得 Liquid Glass 外观、`Reduce Transparency` / `Increase Contrast` / `Reduce Motion` 适配、Vibrancy、焦点环、键盘与 VoiceOver 支持；手写的等价物不会自动获得任何一项。`liquid-glass.md › Where the material belongs`：**Use Liquid Glass effects sparingly.**

推论（本项目最容易违反的三条）：

- 按钮按层选样式。实现中所有动作按钮都用 `.glass` / `.glassProminent`，包括工具栏图标按钮、内容区的状态恢复入口、页脚操作栏与浮动面板。「内容区用 `.bordered` / `.borderedProminent`」是更严格的建议，尚未采纳，见 §2.2。
- 玻璃不叠玻璃且数量受限，一屏内的玻璃表面保持在"最重要的几个功能元素"以内。
- 一屏只有一个 prominent 动作，放在 trailing 端（`buttons.md › Style`：**Keep the number of prominent buttons to one or two per view.**；`toolbars.md › Actions`：**Use the `.prominent` style for key actions such as Done or Submit.**）。

## 2. 本次设计更新

更新只做两件事：把窗口骨架换成系统骨架，把控件换成系统控件。设计图里的信息结构、状态与可执行动作一个都没删；删掉的是重复与空心文案。下面按"设计图与实现是否一致"分两部分。

### 2.1 已落地（设计图与实现一致）

| # | 变更 | 之前 | 现在 | 依据 |
| --- | --- | --- | --- | --- |
| 1 | 侧边栏是真正的 source list | 178px 固定栏，自己画红绿灯、自己画分组标题、选中态是自定义白胶囊；`设置` 与 `本地` 钉在栏底 | `NavigationSplitView` + `List(selection:)`：工具栏自带的收起／展开按钮来自系统（设计图里的切换按钮就是它）；`Show/Hide Sidebar (⌃⌘S)` 需要显式 `SidebarCommands()`，当前未添加，见 tasks/todo.md T25；选中态是系统外观；`设置` 移入同一分组，取消栏底钉死；`本地` 角标删除；`.badge` 计数未采用 | `sidebars.md › Best practices`；`sidebars.md › Desktop (macOS)`：**Avoid putting critical information or actions at the bottom of a sidebar.** |
| 2 | 右上角翻译／润色 + 目标语言改为工具栏控件 | 两个手写下拉框塞在 64px 自绘标题栏里 | `NavigationSplitView` 的 toolbar：`简体中文` 弹出式按钮在左、`翻译｜润色` 分段控件在右；`复制` 与提交动作仍在底部 safe-area 操作栏，未上移（§2.2 #6） | `segmented-controls.md › Best practices`；`pop-up-buttons.md › Best practices` |
| 3 | 面板浮玻璃重做、错误入口改按钮、焦点环交给系统 | 两层渐变 + 四道内阴影 + 双层描边；错误恢复是玫瑰色下划线链接；`2px` 玫瑰色 outline 偏移 4px | 系统 `NSGlassEffectView` 的默认外观（默认圆角、regular 变体），不叠自绘边框与投影；玻璃外面套一层按同一圆角遮罩的容器，`NSPanel.hasShadow = true` 的阴影因此跟着圆角走，而不是照着方形 frame 投出矩形；恢复入口改为 `.glass` 按钮（`StatusNote`、`CompactNoticeView` 与面板动作行）；3px 强调色光晕 + 强调色描边 | `liquid-glass.md › Review checklist` #2：**Restraint.** "Glass stacked on glass blurs the hierarchy the material was meant to create."；`buttons.md › Content`：按钮要能被一眼认出是按钮；`focus-and-selection.md`：**Rely on system-provided focus effects.** |
| 4 | 设置页改为 inset grouped 表单 | 每行一条贯穿分隔线 | 分组圆角容器 + 行内分隔线，容器随分组结束 | `boxes.md › Best practices`：**Consider using padding and alignment to communicate additional grouping within a box.** |
| 5 | 状态总览改按窗口／面板分组 | 按流程分 16 条泳道，用箭头连线 | 按 surface 分 9 个横向分区（翻译与润色 12 / 生词本 4 / 历史记录 3 / 设置 14 / 紧凑条 10 / 直接替换紧凑提示 6 / 学习表达区块 5 / 展开 10 / 菜单栏 2），分区竖向堆叠，同一面板内状态横向换行 | 原型工具；分组后一次能看到同一 surface 的全部状态，与本文的对照表一致 |

### 2.2 建议但当前未采纳

以下决定 `design/index.html` 与 `Owlet/` 都没有采用，保留为后续任务（编号见 [docs/unimplemented-features.md](unimplemented-features.md)）的设计输入。

| # | 建议 | 依据 | 实现现状 |
| --- | --- | --- | --- |
| 6 | 底部动作栏删除，动作上移工具栏 | `windows.md › Desktop (macOS)`：**Avoid putting critical information or actions in a bottom bar…** | 保留 `.safeAreaBar(edge: .bottom)` 底部操作栏（`翻译文本` / `复制` / `保存设置`）。 |
| 7 | 快捷提示不再画在按钮里 | `toolbars.md › Desktop (macOS)`：**Make every toolbar item available as a command in the menu bar.** | 原文标签仍是 `⌘ V 粘贴`，面板底部仍有 `快捷键未设置` / `Esc 取消` 提示行。 |
| 8 | 按钮改用纯动词 | `writing.md › Best practices`：**Build language patterns.** | 仍写 `翻译文本`、`保存设置`，宾语留在按钮里。 |
| 9 | 处理中的整圈边框呼吸 | `motion.md › Providing feedback`：**Aim for brevity and precision in feedback animations.** | 只用 `ProgressView`；玻璃条边缘不做呼吸（T24）。 |
| 10 | 文本处理页 720pt 响应式双栏 | `layout.md › Adaptability`；`split-views.md › Desktop (macOS)` | 已实现：`ProcessingLayout.choose(width:)` 以 720pt 为阈值，足够宽时并排、否则堆叠；画面为 `workspace-narrow`。 |
| 11 | 设置改为独立 `Settings` 窗口 | `settings.md › Desktop (macOS)`：**Include a settings item in the App menu.** | `设置` 是主窗口侧栏的一个 `Page`，应用里没有 `Settings` scene（T19）；细节见 §6。 |
| 12 | 面板动作行删除提示文字，leading 端放 `收藏选中内容` | `layout.md › Visual hierarchy`；`writing.md`：**Be action oriented.** | 提示文字仍在；`收藏选中内容` 已移除，收藏改为在学习区块内勾选入库（画面 `learning`／`saved`）。 |

### 2.3 文案规则（曾拟采用，设计图与实现均未采纳）
1. **动作区只放动作。** 工具栏、动作行里不放解释性文字；状态由内容区、`.help()` 或菜单栏承担。
2. **界面不展示快捷键。** 快捷键的唯一出处是菜单栏（`.keyboardShortcut`）与悬停提示（`.help()`）；不把 `⌘↵` 画进按钮，也不写"快捷键未设置"。
3. **按钮用动词，宾语留给上下文。** 同一屏的控件已把宾语说清楚（分段控件已选"翻译"），按钮就不再重复它；只有宾语会歧义时才保留，例如设置里的 `恢复默认`。同一动作叫法要一致：`复制` 就一直是 `复制`，不在一处叫 `复制译文`。

## 3. 组件对照总表

按 Apple HIG 的组件分类（<https://developer.apple.com/design/human-interface-guidelines/components>）排列；只列 66 个状态中真实出现的东西。

### 3.1 组件 › 布局与组织
- 主窗口骨架（侧栏 + 内容）→ `NavigationSplitView` + `List(selection:)` + `.listStyle(.sidebar)`，桌面端不用 `TabView`，分隔线用系统自带 divider，永不自绘 1px 竖线；侧边栏本体、`Section` 分组与选中态由 `List` 的 sidebar 外观与系统 source list 选中态负责；显示／隐藏用系统侧栏切换工具栏项 + `⌃⌘S`（`sidebars.md`：**Consider letting people hide the sidebar.**）；设置分区用 `Form` + `Section`（`.formStyle(.grouped)`），设置仍是主窗口侧栏页面，见 §6。

### 3.2 组件 › 菜单与操作
- 顶部工具栏 → `.toolbar { ToolbarItem(placement:) }` + `.navigationTitle`，跨整窗、位于侧栏之上；`简体中文` → `Picker(.menu)`，`翻译｜润色` → `SwiftUI 承载的 NSSegmentedControl（momentary／fit）`（段标签用名词）；底部操作栏的 `翻译文本` / `保存设置` / `复制` → `.glass` / `.glassProminent` + `.keyboardShortcut(.return, modifiers: .command)`，宾语保留在按钮里（§2.2 #8）；面板头部（重试 / 设置）与底部动作行（`复制 ⌘⇧C` / `替换 ⌘↩` / `取消`）用 `Button(.glass)` 包在 `GlassEffectContainer` 中，提示文字仍在（§2.2 #7）；菜单栏常驻图标用 `MenuBarExtra` + `Menu`（`the-menu-bar.md`：**Display a menu — not a popover — when people click your menu bar extra.**）。

### 3.3 组件 › 导航与搜索
- 侧栏导航（文本处理／生词本／历史记录／快捷键／设置，调试开关打开时多一项）→ `List(selection:)` 绑定 `enum Page`；快捷键页的“全局／面板内”分组用 `Form` + `Section`；生词本与历史的 `List`、工具栏搜索与筛选、行内删除、列表→详情层级均已落地（见 [docs/unimplemented-features.md](unimplemented-features.md)）。

### 3.4 组件 › 呈现
- 浮动工具条窗口 → `NSPanel`（`.borderless`, `.nonactivatingPanel`, `.floating`）+ `NSGlassEffectView`，玻璃由 window server 绘制，保留其默认圆角与样式，不叠自绘边框与内阴影；窗口的 `contentView` 是按玻璃圆角遮罩的容器，`hasShadow = true` 的投影因此跟随玻璃形状——浅色背景上也需要它来分辨浮层边界；紧凑处理条（`loading` / `polish-loading` / `direct-loading`）用同款玻璃容器 + `Text` + `ProgressView` + 玻璃停止按钮，整圈呼吸是未采纳建议（§2.2 #9、T24）。
- 紧凑提示条（失败／权限／未配置／取消／未能写回）→ 同上容器 + `Label` + 一个恢复按钮，失败态另给重试图标按钮（见 §7 例外 1）；展开态内联状态行（`result-notice`）用 `Label(systemImage:)` + 恢复按钮放进内容流，不收起面板；权限未授权引导用 `AXIsProcessTrustedWithOptions` 打开系统设置，不用自绘弹窗。

### 3.5 组件 › 选择与输入
- 原文输入区 → 多行 `TextEditor`、单行 `TextField(axis: .vertical)`，聚焦态交给系统焦点环；服务设置用 `Form` 行内的 `TextField` / `SecureField` / `Picker(.menu)`（`entering-data.md`：永不预填密码；`pickers.md`：短列表用弹出式按钮）；快捷键录制控件**无系统组件**，实现用 `Button` + `.glass`，录制中换 `.glassProminent`，注册走 Carbon / `NSEvent`（§7 例外 2）；`⌘ V 粘贴` / `⌘ ↵` / `Esc` 提示在设计图与实现里都保留（§2.2 #7）。

### 3.6 组件 › 内容与状态
- 译文／润色结果 → `Text` + `.textSelection(.enabled)` 与语义字号（`labels.md`：**Make useful label text selectable.**），分区标签行用 `LabeledContent` 或 `Section` 头 + `.secondary`；处理中骨架屏用 `.redacted(reason: .placeholder)` 作用在真实内容上，不手绘灰条。
- 处理中指示 → `ProgressView().controlSize(.small / .mini)` + 状态文字,状态文字是动效之外的载体(整圈呼吸未采纳,T24)；内联提示用 `StatusNote`（`Label` + 恢复 `Button`）就地反馈；学习区块、生词本与历史（`learning*`、`saved`、`book-*`、`history-*`）复用同一批系统组件。

### 3.7 系统体验
- 菜单栏常驻入口 → `MenuBarExtra` + `Menu`（`the-menu-bar.md › Menu bar extras`）；全局快捷键没有系统 API 提供"用户可录制"的 UI，注册用 Carbon `RegisterEventHotKey`（§7 例外 2）；应用图标由 `project.yml` 的 `ASSETCATALOG_COMPILER_APPICON_NAME` 指定（当前值 `OwletIcon` 与目录里的 `AppIcon.appiconset` 不一致，`AppIcon.appiconset` 也没有 `appearances` 条目，即没有深色／着色变体，见未实现清单），含 light / dark / tinted 变体。
- 菜单栏与面板的 Owlet 标记 → `Image("OwletMark")`，彩色标记图（紫色眼睛、橙色喙、粉色腮红）；资源必须保持 `template-rendering-intent: original`，改成 `template` 会把它压成单色剪影、丢掉标记的颜色。

## 4. 逐屏对照

与 `design/index.html` 的“状态总览”同一分组：9 个分区竖向堆叠（应用窗口的翻译与润色、生词本、历史记录、设置，浮动面板的紧凑条、直接替换紧凑提示、学习表达区块、展开，菜单栏）；共 66 个状态。除 `success` 保留旧画面外，每张画面都对应应用里已实现的界面。

| 截图 | 已落到设计里的系统组件 |
| --- | --- |
| `workspace*.png`（结果、空输入、已输入、处理中、润色结果、请求失败、服务未配置、侧栏收起） | 侧栏切换 · 内容区顶边的 `TabView`（`Tab(标题, systemImage:)`，四周留边距）· 每个 pane 里两个 `GroupBox`（靠背景区隔，不画分割线；标题位放的是控件——原文一侧 `Picker(.menu)` 选源语言、译文一侧是「译文／学习」分段控件；目标语言 `Picker(.menu)` 在译文组内）· 内容右下角浮起的两颗独立玻璃图标按钮（`复制结果`、`翻译`／`润色`，处理中换成 `取消`；`.labelStyle(.iconOnly)` + `.help()`，不套 `GlassEffectContainer`，见 §2.2）· `TextEditor` · 结果区 `.redacted` 占位 · 行内 `StatusNote`；两侧同时可见并各自滚动（宽窗口左右平分宽度、窄窗口上下平分高度），学习表达跟在译文／润色下面；这一页没有底部操作栏 |
| `settings-shortcuts.png` / `settings-shortcuts-recording.png` / `settings-shortcuts-conflict.png` | 设置窗口的快捷键页：`Form` 的两个 `Section`（`全局` 录制器 / `面板内` 固定键）· 录制按钮（例外 2）· `清除` · 每个分组的 footer 承载说明与冲突提示 |
| `settings-general.png` | 独立设置窗口：`Settings` scene 的标题栏 + `TabView` 标签页切换器（不可自定义、始终可见）· 每页 inset grouped `Form` 的多个 `Section`；通用页含「文本处理」分组（翻译显示方式）与「浮窗」分组（玻璃效果 `Picker`，其下一行次级 `Text` + 系统 `Link` 指向「系统设置 › 外观」，见 BDR-0014；`Toggle`「未选中文字时使用焦点所在输入框的全部文本」，默认关闭，见 T69）；工具栏一页为快捷键页 |
| `settings-language-empty.png` / `settings-language-rows.png` | 语言页：「语言」分组（已选语言逐行 `LabeledContent` + 删除按钮，`添加语言` 才展示完整系统清单）+「目标语言」分组（兜底目标 `Picker(.menu)`、一行一源语言的映射、`添加映射`） |
| `settings-model.png` / `settings-model-openai.png` / `settings-model-agent.png` / `settings-model-failed.png` / `settings-model-prompts.png` / `settings-model-prompts-customized.png` | 模型页：「服务」分组（服务商、Base URL、`SecureField`）、「模型」分组（模型名称、思考强度），以及两组 System Prompt 编辑器；模型列表失败时在名称行下就地提示与 `重试`。编辑器分组标题的行尾是 `默认` 标记，改过之后换成小方块 `恢复默认` 按钮。服务商 `Picker(.menu)` 分两节：远程服务与本地 agent 之间有分隔线，没装的 agent 不出现（T61）。`settings-model-agent` 是本地 agent 的同一页：Base URL 与 `SecureField` 换成 `LabeledContent` 的可执行文件行 + `检测`／`选择…` 两个按钮 + 就地显示的检测结果（版本或失败原因），footer 说明不需要 API Key；Codex 的模型名是 `Picker(.menu)`（第一项「该 agent 自己的默认模型」）；Claude Code 读它自己缓存的模型目录给同一份 `Picker`，缓存缺失或读不出来时该行退回 `TextField`，不弹错误（T62、T66）。每个服务商各自记住模型名，切回上一个服务商时恢复它原来的值（T67） |
| `settings-debug.png` / `settings-debug-open.png` / `settings-debug-empty.png` | 调试页：`List(.inset)` + 系统 `DisclosureGroup`，每次交换一行（指示器、动效与无障碍状态都由系统给出），行内是操作名、原文摘要 `.lineLimit(1)` 与时间；展开后是失败行、原文差异与三段可选中原文；没有记录时用 `ContentUnavailableView` |
| `workspace-auto.png` / `workspace-target-pinned.png` | 工具栏的 `Picker(.menu)`：`自动（简体中文）` 与显式语言两态；结果标签沿用解析出的语言名 |
| `loading.png` / `polish-loading.png` / `direct-loading.png` | 紧凑玻璃条 · `ProgressView` · 状态文字 · 玻璃停止按钮；Esc 取消 |
| `error.png` / `format-error.png` / `cancelled.png` / `permission.png` / `unconfigured.png` / `selection-error.png` / `unwritten.png` | 紧凑玻璃条 · 一行说明 · 一个恢复按钮（服务设置／提示词设置／权限设置／手动输入／配置服务／复制结果／重新处理），失败态另有重试图标按钮；开启「未选中文字时使用焦点所在输入框的全部文本」后，焦点在可编辑输入框且没有选中文字时改取该输入框全文，不再进入 `selection-error` 这一态（见 T69） |
| `direct-selection-error.png` / `direct-permission.png` / `direct-unconfigured.png` / `direct-error.png` / `direct-format-error.png` / `direct-cancelled.png` | 与上一行逐像素相同：直接替换流程复用同一条紧凑玻璃条与同一套恢复入口，仅快捷键发起的流程不同；开启「未选中文字时使用焦点所在输入框的全部文本」后原文来自焦点输入框全文，直接替换先 ⌘A 全选该输入框再粘贴，字段里只剩译文而不是在插入点追加，无法确认全选则不发送粘贴并按「未能写回」提示（见 T70） |
| `result.png` / `polish.png` / `long.png` / `result-loading.png` / `result-unwritten.png` / `result-notice.png` / `result-cancelled.png` / `menubar.png` / `menubar-menu.png` | `NSGlassEffectView` 面板 · 头部 `Picker(.menu)` + 玻璃图标按钮 · 可选中结果文本 · 底部提示行 + `复制 ⌘⇧C` / `替换 ⌘↩` · 内容区 `StatusNote`；复制结果或写回成功后关闭面板；`MenuBarExtra` 菜单（非 popover） |
| `empty.png` | 已展开且原文为空：`canRetry` 为假，`PanelHeader` 不传 `retry`、`PanelFooter` 默认分支没有按钮，只留快捷键提示；原文栏仍可编辑 |
| `success.png` | 写回成功确认：展开结果内确认替换、动作行以 `完成` 关闭；应用行为为写回成功直接关闭浮窗，此画面仍是原型提案 |
| `book-list.png` / `book-detail.png` / `book-empty.png` / `no-results.png` | 统一工具栏 · 搜索框 · 弹出式按钮 `全部语言` · `导出…` · `List` 行 · `ContentUnavailableView` 空状态 |
| `history-list.png` / `history-detail.png` / `history-empty.png` | 同构工具栏 · 类型筛选 · 破坏性 `清空历史` · 详情可复制与收藏 |
| `learning.png` / `learning-loading.png` / `learning-error.png` / `learning-empty.png` / `saved.png` | 展开结果内的独立区块 · `ProgressView`／`.redacted` 占位 · 就地重试 · 可勾选列表与 `收藏所选` |
| `aligned.png` | 逐句对照：配对视图内的系统 `Text`，复制与替换仍只输出译文（§7 例外 3） |
| `workspace-narrow.png` | 窄窗口（内容区 < 720pt）下的单列堆叠分支与宽窗口并排 |

旧原型的 40 个状态现已全部覆盖：`stale` 由 `unwritten` 承载、`settings-shortcuts` 由 `shortcuts-recording` 承载，其余 38 个各有画面。

### 4.1 每个状态的实现位置

67 个状态与 `Owlet/` 的对应关系（按实现文件分组）：

| 状态 | 实现位置 |
| --- | --- |
| `workspace`、`workspace-empty`、`workspace-input`、`workspace-loading`、`workspace-polish`、`workspace-error`、`workspace-unconfigured` | `Owlet/Processing/TextProcessingView.swift`（工作台工具栏与编辑区）· `Owlet/Processing/TextProcessingModel.swift`（处理状态）· `Owlet/App/OwletApp.swift`（窗口、侧栏与菜单命令） |
| `workspace-collapsed` | `Owlet/App/OwletApp.swift`（MainView 的 NavigationSplitView 侧栏） |
| `settings-shortcuts`、`settings-shortcuts-recording`、`settings-shortcuts-conflict`（`ShortcutController.registrationError` 的冲突文案） | `Owlet/Shortcuts/ShortcutSettingsPane.swift` · `Owlet/Shortcuts/ShortcutController.swift` |
| `settings-general` | `Owlet/Settings/SettingsView.swift`（标签页）· `Owlet/Settings/GeneralSettingsPane.swift` |
| `settings-language-empty`、`settings-language-rows` | `Owlet/Settings/LanguageSettingsPane.swift` · `Owlet/Settings/LanguageSettingsView.swift` · `Owlet/Settings/TargetMappingSettingsView.swift` · `Owlet/Settings/TargetMapping.swift` |
| `settings-model`、`settings-model-openai`、`settings-model-agent`、`settings-model-failed` | `Owlet/Settings/ModelSettingsPane.swift` · `Owlet/Settings/SettingsStore.swift`（Keychain 与本地 agent 路径）· `Owlet/LLM/LocalAgent.swift`（检测与版本） |
| `workspace-auto`、`workspace-target-pinned` | `Owlet/Settings/TargetLanguagePicker.swift` · `Owlet/Processing/LanguageDetector.swift` · `Owlet/Processing/TextProcessingView.swift` |
| `settings-debug`、`settings-debug-open`、`settings-debug-empty` | `Owlet/Settings/DebugSettingsPane.swift` · `Owlet/Debug/DebugLog.swift` · `Owlet/LLM/ModelClient.swift`（记录点） |
| `loading`、`polish-loading`、`direct-loading` | `Owlet/App/Panel/CompactPanelContent.swift`（CompactProcessingView） |
| `error`、`format-error`、`cancelled`、`permission`、`unconfigured`、`selection-error`、`unwritten` | `Owlet/App/Panel/PanelController.swift`（Notice）· `Owlet/App/Panel/PanelRootView.swift`（recover）· `Owlet/App/Panel/CompactPanelContent.swift`（CompactNoticeView）· `Owlet/Selection/SelectionBridge.swift`（权限与读取失败来源） |
| `direct-selection-error`、`direct-permission`、`direct-unconfigured`、`direct-error`、`direct-format-error`、`direct-cancelled` | `Owlet/App/Panel/PanelController.swift`：“翻译并替换”复用同一 `Notice`／`CompactNoticeView`，与 `selection-error`／`permission`／`unconfigured`／`error`／`format-error`／`cancelled` 同屏 |
| `result`、`polish`、`long`、`result-loading` | `Owlet/App/Panel/ExpandedPanel.swift` · `Owlet/App/Panel/PanelHeader.swift` · `Owlet/App/Panel/ExpandedPanelContent.swift` · `Owlet/App/Panel/PanelFooter.swift`· `Owlet/App/Panel/PanelController.swift`（展开时机） |
| `result-notice`（失败）、`result-cancelled`（取消） | `Owlet/App/Panel/ExpandedPanelContent.swift`（StatusNote）· `Owlet/App/Panel/PanelController.swift`（inlineNotice）；失败与取消时 `hasResultSection` 为假，结果区不渲染 |
| `result-unwritten` | `Owlet/App/Panel/PanelController.swift`（`writebackRefusal` → `inlineNotice` 返回 `.unwritten`／`.unwritable`）· `Owlet/App/Panel/ExpandedPanel.swift` |
| `empty` | `Owlet/App/Panel/ExpandedPanel.swift`（`canRetry`）· `Owlet/App/Panel/PanelFooter.swift`（默认分支）· `Owlet/App/Panel/PanelController.swift`（空原文时 `processCurrentText()` 置 `.idle`，展开态保留） |
| `menubar`、`menubar-menu` | `Owlet/App/OwletApp.swift`（MenuBarExtra、MenuContent、MenuBarLabel） |
| `book-list`、`book-detail`、`book-empty`、`no-results` | `Owlet/Vocabulary/VocabularyView.swift` · `Owlet/Vocabulary/VocabularyStore.swift` · `Owlet/Vocabulary/CollectionAction.swift` |
| `history-list`、`history-detail`、`history-empty` | `Owlet/History/HistoryView.swift` · `Owlet/History/HistoryStore.swift` · `Owlet/History/HistoryRecorder.swift` |
| `learning`、`learning-loading`、`learning-error`、`learning-empty`、`saved` | `Owlet/Learning/LearningView.swift` · `Owlet/Learning/LearningContent.swift` · `Owlet/App/Panel/ExpandedPanel.swift` |
| `aligned` | `Owlet/Processing/AlignedSegments.swift` · `Owlet/Processing/TextProcessingView.swift`（`TranslationDisplayMode` 的 `.aligned`） |
| `settings-model-prompts`、`settings-model-prompts-customized` | `Owlet/Settings/PromptSettingsView.swift` · `Owlet/LLM/DefaultPrompts.swift` |
| `workspace-narrow` | `Owlet/Processing/ProcessingLayout.swift`（720pt 阈值）· `Owlet/Processing/TextProcessingView.swift` |
| `success` | 提案（未实现）：原型画写回完成确认；应用 `Owlet/App/Panel/PanelController.swift` 的 `performReplace` 在写回成功后直接关闭浮窗 |

## 5. 设计令牌退役表

`spec/DESIGN.md` 的配色表与 `RoseGlass` 已从 `Owlet/` 删除；下表保留为迁移依据。

| 现令牌 | 现用途 | 替换为 |
| --- | --- | --- |
| `RoseGlass.accent` / `ink` / `muted` / `paper` / `line` / `selectedNav` / `tint` / `keyFill` | 主按钮与焦点、正文与标题、次要文字、内容底、分隔线、侧栏选中、录制底色与键帽 | 应用 `AccentColor` 资源（唯一允许的品牌色出口）；`.primary` / `.secondary` / `.tint(nil)`；系统窗口纸张与列表材质；`Divider()` |
| `RoseGlass.errorFill` / `errorText` / `green` / `skeleton` / 粉色渐变呼吸描边 | 错误块、成功、骨架屏、处理中装饰 | `StatusNote`（`Label` + `.secondary`）、`.green`、`.redacted(reason: .placeholder)`；呼吸未采纳，实现只用 `ProgressView`（T24） |
| `RoseGlass.window` / `sidebar` / `footerFill` | 窗口／侧栏／底栏底 | 系统窗口背景、`List` sidebar 外观、底部 safe area bar 材质 |
| `MainButtonStyle` / `MainLabelStyle` / `FieldBox` / `SelectField` / `KbdChip` / `GroupTitle` / `FormRow` / `PageFooter` / `PageHeader` / `SectionLabel` / `NavRow` / `ProcessingStrip` / `CompactNoticeView` | 自绘按钮、输入框描边与焦点环、自绘下拉、键帽、自绘窗口与紧凑条零件 | `.bordered` / `.borderedProminent` / `.glass` / `.glassProminent`；`Form` 行内系统 `TextField` + 系统焦点环；`Picker(.menu)`；快捷键归菜单栏与 `.help()`（设计图仍画 `⌘ ↩`，§2.2 #7）；`Form` + `Section`、`.toolbar`、`List`；紧凑条保留玻璃容器，内部只用 `ProgressView`、`Text`、`Label`、`Button(.glass)`、`StatusNote` |

## 6. 关于设置窗口的建议（未改动设计图）

设计图把设置画成主窗口的一个页面，实现也保持这样（§2.2 #11）。若将来采纳 `settings.md › Desktop (macOS)` 要求的**独立窗口**：从应用菜单（`⌘,`）打开，工具栏分栏且按钮常驻不可自定义，最小化与缩放按钮置灰，窗口标题跟随分栏。

1. 设置改为 `Settings` scene + 分栏 `TabView`：**通用**（翻译显示方式、浮窗位置）· **显示** · **提示词** · **服务**（Base URL、API Key、模型）。
2. 侧栏不再出现 `设置` 行；工具栏也不放设置按钮（`settings.md`：**Include a settings item in the App menu.**）。

设置是独立窗口（`Settings` scene，App 菜单与 ⌘, 打开），主窗口侧栏只有文本处理、生词本、历史记录与快捷键。

## 7. 判断与例外

macOS 26 没有提供系统对应物的三处必须自定义；例外 3 对应尚未实现的功能，当前实现还没走到它。

| 例外 | 做法 |
| --- | --- |
| 1 · 内联提示行 | macOS 没有系统 banner，而 `feedback.md` 要求状态反馈就近呈现。做法：`Label(systemImage:)` + 一个恢复 `Button` 放进内容流；失败态另给符号，不靠颜色单独表意。 |
| 2 · 全局快捷键录制控件 | 没有任何系统 API 提供"点击后录制组合键"的 UI，Carbon 的 `RegisterEventHotKey` 只负责注册。实现中录制按钮用 `.glass`，录制中换成 `.glassProminent`（`Owlet/Shortcuts/ShortcutSettingsView.swift`），并保留 `Esc` 取消、`Delete` 清除、冲突提示与 `accessibilityLabel` / `accessibilityValue`。这是本项目唯一不可避免的自定义控件。 |
| 3 · 逐句对照布局（已实现，T14） | 没有系统组件表达“原文／译文按语义句子配对”。做法：`LazyVStack` 内的配对视图，子元素全部是系统 `Text`；配对关系由模型返回，不按显示行推断。画面为 `aligned.png`。 |

**其余判断（我的判断，不是 Apple 的条文）：**

- 粉色保留为应用强调色。`color.md › App accent colors` 允许应用指定 accent；只要它只出现在强调色、prominent 按钮、选中态与状态指示，就符合 `liquid-glass.md › Color on glass`。**不要**把它散布到每个视图的 tint。
- `本地` 角标删除（它不承载可操作信息，数据存放位置写在设置的"服务"分栏）；`已复制` toast 建议删除（结果已经在界面上）；面板头部的 Owlet 标记改用可着色符号或 template 图像，避免白色 PNG 在浅色玻璃上不可见。

## 8. 验收清单

1–7、9 已随实现落地；8 未达成（菜单栏只有打开主界面、四个快捷键动作、设置与退出，没有覆盖每个工具栏项）；11–12 与 §2.2 的未采纳建议绑定，需要先决定是否采用。

1. **层纪律。** 玻璃只出现在工具栏、侧边栏、浮动面板、弹出视图；内容区、卡片、列表行、分组容器一律无玻璃。
2. **玻璃数量。** 一屏内的自定义玻璃表面不超过"最重要的几个功能元素"，面板内不叠玻璃于玻璃之上。
3. **颜色预算。** 每屏最多一个 tinted prominent 动作；控制标签单色；品牌色只在强调色、prominent 动作与状态指示。
4. **辅助功能。** `Reduce Transparency` 有实底回退；`Increase Contrast` 有更强描边；`Reduce Motion` 去掉展开动画（`PanelController` 已有 `reduceMotion` 分支）；呼吸动画属未采纳建议（T24）；`workspace-collapsed.png` 与展开态功能完全一致。
5. **对比度。** 正文 ≤17pt 达 4.5:1，≥18pt 或粗体达 3:1；玫瑰 `oklch(47% .17 350)` 在白底上约 8:1，作为强调色安全；次要文字用 `.secondary` 由系统保证。
6. **点击区。** 桌面端默认 28×28pt，最小 20×20pt；工具栏图标按钮 28×28；列表行高不低于 28pt。
7. **字号。** 桌面端默认 13pt，最小 10pt，不出现细体小字。
8. **键盘。** 每个工具栏项都有对应菜单栏命令与快捷键（`toolbars.md › Desktop (macOS)`）；焦点环可见；`Full Keyboard Access` 下可达每个控件。
9. **深色外观。** 无硬编码颜色后，浅色与深色都要过一遍；无应用级外观开关。
10. **菜单栏。** `Settings… (⌘,)` 在应用菜单（已实现）；`Show/Hide Sidebar (⌃⌘S)` 需要 `SidebarCommands()`，未添加；`编辑` 菜单提供 `Undo/Redo/Cut/Copy/Paste/Select All`。
11. **适应宽度。** 从最小宽度到满宽连续拖动，翻译与润色页在 720pt 处切换并排／堆叠，无跳变、无截断、无重排抖动。
12. **文案（未采纳，§2.2 #7／#8／#12）。** §2.3 的三条文案规则无例外；界面里找不到快捷键字块与空心提示。

`design/index.html` 控制台里有两个自动检查：

- `checkDesignStates()` → 66 个状态逐个渲染过一遍：应用窗口状态必须有工具栏与内容区（翻译与润色页的工具栏必须有动作按钮，设置状态必须有标签页切换器）；浮窗状态必须是浮动面板，紧凑条要有紧凑条元素、展开态要有面板头部与动作行，且动作行不被裁切；`menubar` 只校验状态存在。
- `checkFlowBoard()` → 66 个状态全部出现在总览上、无重复，分区数与定义一致（10 个窗口／面板）；返回 `{states, frames, panels}`。

## 9. 迁移顺序

按影响面从小到大，每一步都可独立验证。

1. 删除 `RoseGlass` 与自绘按钮样式，全部换成系统语义色与系统按钮（已落地）。
2. 主窗口改 `NavigationSplitView`（侧栏可收起）并把工具栏就位：`navigationTitle` + 弹出式按钮（左）+ 分段控件（右）（已落地）。
3. 设置改为 `Settings` scene + 分栏，侧栏与工具栏移除入口（未采纳，T19）。
4. 删除底部动作栏，动作迁入工具栏（已实现，T32）；翻译与润色页在内容区 ≥720pt 时两栏并排（已实现，T22）。
5. 列表换 `List` + `.searchable` + `ContentUnavailableView` + 上下文菜单（随生词本／历史一并未实现）；浮动面板的呼吸动画与 `收藏选中内容` 动作行未采纳（紧凑条与动作行已落地）。
6. 菜单栏补全并收口文案（`⌘,` 已接，文案未收口）；辅助功能与外观终检见 §8。

## 10. 参考

HIG 参考资料取自 Apple 官方文档 <https://developer.apple.com/design/human-interface-guidelines>：`liquid-glass`（`Where the material belongs` / `Which variant` / `Color on glass` / `Review checklist`）、`materials`、`color`、`layout`、`designing-for-macos`、`sidebars`、`toolbars`、`windows`、`panels`、`split-views`、`settings`、`the-menu-bar`、`buttons`、`segmented-controls`、`pop-up-buttons`、`menus`、`search-fields`、`lists-and-tables`、`boxes`、`labels`、`text-views`、`toggles`、`pickers`、`progress-indicators`、`feedback`、`writing`、`accessibility`、`focus-and-selection`、`dark-mode`、`generative-ai`。组件分类依 Apple 官方目录：<https://developer.apple.com/design/human-interface-guidelines/components>

T33 材质：导航与工具栏采用系统默认 Liquid Glass；内容区不叠玻璃，使用 GroupBox／Form 的系统背景。动作使用系统 `.glass`／`.glassProminent`，图标来自 SF Symbols。窄窗工作台通过原生 ScrollView 保持编辑器和学习区可达。

2026-09-29 用户确认覆盖前述内容层限制：工作台三个 GroupBox 添加原生 `.glassEffect(.regular, in: ContainerRelativeShape())`，形状跟随容器，未新增颜色、模糊、边框或阴影实现。

管理页标题：生词本和历史页不重复显示窗口导航标题；数量为 List 第一行 Text（secondary、selectionDisabled），不再使用吸顶 Section 标题。

T35 布局还原：工作台标题移除，语言 Picker 保留布局尺寸，学习 GroupBox 常驻；管理详情采用独立 ScrollView、灰色元信息与原生 GroupBox，列表支持系统多选；ToolbarSpacer 分隔上一条/下一条与内容动作。

T36：移除品牌强调色配置，使用系统默认强调色；侧栏显式 List.sidebar，不覆盖字号。学习使用 SF Symbols lightbulb.fill，生词本使用 books.vertical；筛选 Menu 内 Picker.inline，选项在一级直接显示。

T37：搜索使用 AppKit NSSearchField，系统提供放大镜、清除按钮和焦点环；独立 ToolbarItem 隐藏共享背景，避免玻璃胶囊与局部焦点环叠加。

T38 覆盖 T37：搜索改为 SwiftUI searchable + DefaultToolbarItem(.search)，由系统负责尺寸、焦点和搜索交互；ToolbarSpacer 分隔导航、内容动作和最右侧搜索。

T39：保持 NavigationSplitView；统一工具栏按 navigation/principal/primaryAction 分布筛选、上下条、内容动作与搜索。

管理页正文分栏与顶部安全区保留最小间距，系统分隔线不延伸进入统一工具栏；不裁剪原生列表。

T40：宽屏工作台使用原生 HSplitView，与管理页采用同一分栏方式；原文与结果各自滚动，底部学习仍常驻，窄屏保留上下排列。

T42 浮窗：原文摘要与结果使用系统 glassEffect；状态条和原文组合操作用 SwiftUI 承载的 NSSegmentedControl（momentary／fit），独立动作用 Button.glass，更多操作用 contextMenu，学习用 List 与逐条 borderless 收藏按钮；无外层玻璃覆盖透明间隙。

### T42 精确画板组件核对

仅以 [6313:31216](https://www.figma.com/design/PL0seWKhVgNHzaHLFbWLaQ/macOS-27--Community-?node-id=6313-31216) 为布局依据。以下主组件和变体均从实例详情读取，Button 已经通过 From this file 跳转 master 核对；其他画板不作为布局来源。

| 画板内实例 | 主组件／变体 | SwiftUI 对应 |
| --- | --- | --- |
| 6313:31543 原文操作；6313:31552 错误状态；6313:31628 处理中 | Segmented Control / Light / XL / Active=True；master 605:3160 | SwiftUI 承载的 NSSegmentedControl（momentary／fit），保留图标与文字，不拼装多个按钮 |
| 6313:31274、6329:31755 内容材质 | Liquid Glass - Medium / Light；master 483:9257 | 系统 glassEffect |
| 6313:31301 关闭、6313:31302 复制、6329:31761 学习 | Button / Light / XL / Idle；master 648:4854 | Button(.glass)，SF Symbols xmark、doc.on.doc、lamp.desk |
| 6313:31478 收藏 | Buttons / Over-Glass / Borderless / Idle；master 502:5872 | Button(.borderless)，bookmark／bookmark.fill |
| 6329:31758、6313:31277 | Separators | Divider |

外观跟随系统，不固定 Light；无自行绘制颜色、材质、边框、按钮样式。

T42 视觉修正：正文 Title 2 Regular（17/22），图标 SF Pro Medium 13pt，系统圆形按钮 36pt；结果与学习面板分别 257／295pt 高，动作叠在右下角。大表面使用系统 ButtonBorderShape.roundedRectangle，未手填半径。

### 原生 panel 隔离预览

完整流程、失败尝试与证据边界见 [Panel 调试、测试与截图](panel-debugging-and-testing.md)。

`python3 scripts/panel-preview.py` 使用固定选区与模拟模型，绕过系统权限请求，生词本仅在内存；主 app 的配置不变。⌘1–⌘5 切换处理中、缺配置、连接失败、成功、学习五态。

`python3 scripts/panel-preview.py --live` 从进程环境读取 `DEEPSEEK_API_KEY` 进行真实联调，密钥不落盘、不输出。`--background /绝对路径/背景.png` 可为玻璃截图提供窗口内对照背景；默认不附带或修改系统壁纸。

浮窗组合操作的 NSSegmentedControl 关闭 cell 自带边框（isBordered = false），由单层 `.glassEffect(.regular)` 提供背景；避免叠层，同时保持背景清晰。

T43：通用设置的浮窗区使用原生 Picker 选择玻璃效果；浮窗玻璃表面统一使用系统 Glass.clear／regular，默认 regular，不手写透明度或材质。玻璃强度仍不归应用：`SwiftUICore.Glass` 只有 `regular`／`clear`／`identity`，`NSGlassEffectView` 只有 `style` 与圆角／tint，没有连续强度的公开符号，所以该分组在 Picker 下只用次级 `Text` + 系统 `Link` 指向「系统设置 › 外观」（BDR-0014）。这是指向既有系统设置，不是新的 HIG 主张，本表不为它新增引用条目。

预览可用 `--screenshots /绝对路径/输出目录` 自动切换并通过系统 screencapture 导出五个主状态及收藏／取消收藏两态窗口截图，无需 computer use。AppKit cacheDisplay 会遗漏玻璃合成，不能用于材质验收；`--settings /绝对路径/输出目录` 用同一条 cacheDisplay 路径离屏导出通用设置页（无玻璃表面，故结果可用），不需要屏幕录制授权。窗口未激活时系统按钮会显示非活跃颜色。

T44：结果展开使用 SwiftUI spring 与 NSAnimationContext.animate(.spring)，窗口与内容均从顶部展开；学习行 HStack 居中，结果／学习底部动作距右边及底边24pt。

T45：学习双栏以原生 spring 与 move／opacity 过渡；词条整行使用 borderless Button，图标随 SwiftData Query 的实际收藏状态切换，不再禁用已收藏按钮。

学习左侧译文使用原生 NSTextField(wrappingLabelWithString:) 与 justified 段落对齐，17pt、行间距2pt，可选择复制，末行自然对齐。预览 `--active` 只用于对照系统控件活跃颜色，不代表鼠标 hover 或真实窗口活跃状态；底部按钮保留标准 Button.glass。

设置「语言」分组新增「读音体系」一节：有分歧的语言（日语、中文）用系统 `Picker`，其余用 `LabeledContent` 显示固定的 IPA。

## T47 查词卡组件对照（浮窗已实现，其余待实现）

行为见 [查词规格](../spec/vocabulary/features/word-lookup.feature)，决定见 [BDR-0008](../spec/vocabulary/decisions/BDR-0008-reading-word-lookup.md)。以下是实现候选，不代表已替换控件或已验收；不增加退役原型的截图／状态计数。

| 阅读区域 | 保留行为与原生承载边界 |
| --- | --- |
| 浮窗正文 | **T48 已实现**：原文 TextEditor 保留；只读结果改为 TextKit 1 只读 `NSTextView`（`LookupText`，16pt Medium、`NSColor.textColor`，学习双栏时两端对齐），浮窗内取代 `Text.textSelection` 与 `PanelJustifiedText` |
| 主窗口文本处理结果 | **T50 已实现**：结果与逐句对照两侧均为 `LookupText`（结果两端对齐 16pt Medium，逐句对照原文 Regular、译文 Medium）；原文输入框继续编辑 |
| 生词本详情 | **T50 已实现**：表达（22pt semibold）、原句语境与润色前／后为 `LookupText`；润色前用次要色；释义保持 `Text` |
| 历史详情 | **T50 已实现**：原文（Regular）与结果（两端对齐 Medium）为 `LookupText`，取代 `PanelJustifiedText`；学习与收藏动作不变 |
| 学习表达式 | **T51 已实现**：行不再整行包一个 `Button`：书签为 `.plain` 按钮（辅助功能收藏入口），行用 `onTapGesture` 收藏并保留悬停背景；表达为 `LookupText`：⌘ 单击查词、拖拽／双击选中后工具栏、右键或 Return 查询，语境取该条原句 |

T48：选区工具栏与查词卡共用一个系统 `NSPopover`（`.transient`）。工具栏只有一个 `.plain` 的「查询」文字按钮，popover 本身即工具栏外框，不再套一层玻璃按钮，也不加悬停提示；超限时直接显示原因；卡片 320pt 宽，标题 16pt semibold 为查询词形，次级 13pt `.secondary` 依次为不同的原形、读音、词性，释义 15pt，来源／无原句用 `Label` + `.secondary`；加载为居中次要色文字，失败为居中红色 `Label` 加纯文本「重试」，「按当前语境重查」为纯文本按钮，发音为 36pt `CardButton`。右键菜单在系统菜单顶部插入「查询所选」。查词卡优先验证系统 popover，内容用系统 Text／Label、ProgressView、Button；选区动作使用原生工具栏／菜单承载，不手画控件。原形次级展示，来源、失败、禁用发音原因在内容中可读并可被辅助功能访问。

悬停仅按 [DESIGN 封闭例外](../spec/DESIGN.md#查词悬停的封闭例外2026-10-07-已确认t49-已实现)。原生验证须覆盖真实文字命中（不能仅凭最近字符索引）、中日文分词、双击／拖拽／复制、学习行收藏隔离、popover 焦点、Esc 层级、VoiceOver，以及系统语音可用／缺失。先验证首个阅读区域，再决定其他区域的最小改动，不预定五处统一替换。

T55（[BDR-0010](../spec/vocabulary/decisions/BDR-0010-collect-from-lookup.md)）：卡片标题行右侧、`发音` 左侧是一个 `CardGlassButton`（`.glass`、圆形边框、36pt、13pt 字形），与 `发音` 同一个组件，只是标本为 `bookmark`／`bookmark.fill`、已收藏取强调色；`.hoverTip` 与辅助功能值给出「加入生词本／取消收藏」（系统无可用语音时 `发音` 的原因同样走提示，不再占一行说明）。文本语言未知或未接入生词本时不出现该按钮。不用自绘控件，不加确认弹窗。
