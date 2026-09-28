# Owlet · macOS 26 Liquid Glass 组件对照

状态：`design/index.html` 有 58 个状态（对应 `design/screenshots/`）：42 个对应 `Owlet/` 已实现的功能，设计图与实现一致；16 个是尚未实现功能的提案画面，画面上带“未实现”徽标、总览里各自成区，逐条见 [docs/unimplemented-features.md](unimplemented-features.md)。对照对象是截图中每一个可见组件，目标是把它们逐一换成 macOS 26（Tahoe）原生 SwiftUI / AppKit 组件，不再手写控件，不再自定义颜色、圆角、边框、渐变与阴影。

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
| 3 | 面板浮玻璃重做、错误入口改按钮、焦点环交给系统 | 两层渐变 + 四道内阴影 + 双层描边；错误恢复是玫瑰色下划线链接；`2px` 玫瑰色 outline 偏移 4px | 系统 `NSGlassEffectView` 的默认外观（默认圆角、regular 变体），不叠自绘边框与投影；玻璃外面套一层按同一圆角遮罩的容器，`NSPanel.hasShadow = true` 的阴影因此跟着圆角走，而不是照着方形 frame 投出矩形；恢复入口改为 `.glass` 按钮（`StatusNote`、`NoticeStrip` 与面板动作行）；3px 强调色光晕 + 强调色描边 | `liquid-glass.md › Review checklist` #2：**Restraint.** "Glass stacked on glass blurs the hierarchy the material was meant to create."；`buttons.md › Content`：按钮要能被一眼认出是按钮；`focus-and-selection.md`：**Rely on system-provided focus effects.** |
| 4 | 设置页改为 inset grouped 表单 | 每行一条贯穿分隔线 | 分组圆角容器 + 行内分隔线，容器随分组结束 | `boxes.md › Best practices`：**Consider using padding and alignment to communicate additional grouping within a box.** |
| 5 | 状态总览改按窗口／面板分组 | 按流程分 16 条泳道，用箭头连线 | 按 surface 分 14 个横向分区（已实现的 7 区：文本处理 8 / 快捷键 3 / 设置 5 / 紧凑条 10 / 直接替换紧凑提示 6 / 展开 8 / 菜单栏 2；提案的 7 区：生词本 4 / 历史记录 3 / 学习表达区块 5 / 逐句对照 1 / 直接替换完成 1 / Prompt 1 / 窄窗口 1），分区竖向堆叠，同一面板内状态横向换行 | 原型工具；分组后一次能看到同一 surface 的全部状态，与本文的对照表一致 |

### 2.2 建议但当前未采纳

以下决定 `design/index.html` 与 `Owlet/` 都没有采用，保留为后续任务（编号见 [docs/unimplemented-features.md](unimplemented-features.md)）的设计输入。

| # | 建议 | 依据 | 实现现状 |
| --- | --- | --- | --- |
| 6 | 底部动作栏删除，动作上移工具栏 | `windows.md › Desktop (macOS)`：**Avoid putting critical information or actions in a bottom bar…** | 保留 `.safeAreaBar(edge: .bottom)` 底部操作栏（`翻译文本` / `复制` / `保存设置`）。 |
| 7 | 快捷提示不再画在按钮里 | `toolbars.md › Desktop (macOS)`：**Make every toolbar item available as a command in the menu bar.** | 原文标签仍是 `⌘ V 粘贴`，面板底部仍有 `快捷键未设置` / `Esc 取消` 提示行。 |
| 8 | 按钮改用纯动词 | `writing.md › Best practices`：**Build language patterns.** | 仍写 `翻译文本`、`保存设置`，宾语留在按钮里。 |
| 9 | 处理中的整圈边框呼吸 | `motion.md › Providing feedback`：**Aim for brevity and precision in feedback animations.** | 只用 `ProgressView`；玻璃条边缘不做呼吸（T24）。 |
| 10 | 文本处理页 720pt 响应式双栏 | `layout.md › Adaptability`；`split-views.md › Desktop (macOS)` | 单列 `VStack`，原文与译文上下排列（T22）。提案画面 `workspace-narrow` 画的是窄窗口下的堆叠分支，宽窗口并排尚未出图。 |
| 11 | 设置改为独立 `Settings` 窗口 | `settings.md › Desktop (macOS)`：**Include a settings item in the App menu.** | `设置` 是主窗口侧栏的一个 `Page`，应用里没有 `Settings` scene（T19）；细节见 §6。 |
| 12 | 面板动作行删除提示文字，leading 端放 `收藏选中内容` | `layout.md › Visual hierarchy`；`writing.md`：**Be action oriented.** | 提示文字仍在，`收藏选中内容` 属未实现功能（T08）；提案画面见 `learning`／`saved`。 |

### 2.3 文案规则（曾拟采用，设计图与实现均未采纳）
1. **动作区只放动作。** 工具栏、动作行里不放解释性文字；状态由内容区、`.help()` 或菜单栏承担。
2. **界面不展示快捷键。** 快捷键的唯一出处是菜单栏（`.keyboardShortcut`）与悬停提示（`.help()`）；不把 `⌘↵` 画进按钮，也不写"快捷键未设置"。
3. **按钮用动词，宾语留给上下文。** 同一屏的控件已把宾语说清楚（分段控件已选"翻译"），按钮就不再重复它；只有宾语会歧义时才保留，例如设置里的 `恢复默认`。同一动作叫法要一致：`复制` 就一直是 `复制`，不在一处叫 `复制译文`。

## 3. 组件对照总表

按 Apple HIG 的组件分类（<https://developer.apple.com/design/human-interface-guidelines/components>）排列；只列 58 个状态（含 16 张提案画面）中真实出现的东西。

### 3.1 组件 › 布局与组织
- 主窗口骨架（侧栏 + 内容）→ `NavigationSplitView` + `List(selection:)` + `.listStyle(.sidebar)`，桌面端不用 `TabView`，分隔线用系统自带 divider，永不自绘 1px 竖线；侧边栏本体、`Section` 分组与选中态由 `List` 的 sidebar 外观与系统 source list 选中态负责；显示／隐藏用系统侧栏切换工具栏项 + `⌃⌘S`（`sidebars.md`：**Consider letting people hide the sidebar.**）；设置分区用 `Form` + `Section`（`.formStyle(.grouped)`），设置仍是主窗口侧栏页面，见 §6。

### 3.2 组件 › 菜单与操作
- 顶部工具栏 → `.toolbar { ToolbarItem(placement:) }` + `.navigationTitle`，跨整窗、位于侧栏之上；`简体中文` → `Picker(.menu)`，`翻译｜润色` → `Picker(.segmented)`（段标签用名词）；底部操作栏的 `翻译文本` / `保存设置` / `复制` → `.glass` / `.glassProminent` + `.keyboardShortcut(.return, modifiers: .command)`，宾语保留在按钮里（§2.2 #8）；面板头部（重试 / 设置）与底部动作行（`复制 ⌘⇧C` / `替换 ⌘↩` / `取消`）用 `Button(.glass)` 包在 `GlassEffectContainer` 中，提示文字仍在（§2.2 #7）；菜单栏常驻图标用 `MenuBarExtra` + `Menu`（`the-menu-bar.md`：**Display a menu — not a popover — when people click your menu bar extra.**）。

### 3.3 组件 › 导航与搜索
- 侧栏导航（文本处理／快捷键／设置）→ `List(selection:)` 绑定 `enum Page`，导航不等于动作，收敛后只有三个页面；快捷键页的“全局／面板内”分组用 `Form` + `Section`；生词本与历史的列表只有提案画面（`book-list`、`history-list`），工具栏搜索与筛选、行内删除、列表→详情层级均未落地（见 [docs/unimplemented-features.md](unimplemented-features.md)）。

### 3.4 组件 › 呈现
- 浮动工具条窗口 → `NSPanel`（`.borderless`, `.nonactivatingPanel`, `.floating`）+ `NSGlassEffectView`，玻璃由 window server 绘制，保留其默认圆角与样式，不叠自绘边框与内阴影；窗口的 `contentView` 是按玻璃圆角遮罩的容器，`hasShadow = true` 的投影因此跟随玻璃形状——浅色背景上也需要它来分辨浮层边界；紧凑处理条（`loading` / `polish-loading` / `direct-loading`）用同款玻璃容器 + `Text` + `ProgressView` + 玻璃停止按钮，整圈呼吸是未采纳建议（§2.2 #9、T24）。
- 紧凑提示条（失败／权限／未配置／取消／未能写回）→ 同上容器 + `Label` + 一个恢复按钮，失败态另给重试图标按钮（见 §7 例外 1）；展开态内联状态行（`result-notice`）用 `Label(systemImage:)` + 恢复按钮放进内容流，不收起面板；权限未授权引导用 `AXIsProcessTrustedWithOptions` 打开系统设置，不用自绘弹窗。

### 3.5 组件 › 选择与输入
- 原文输入区 → 多行 `TextEditor`、单行 `TextField(axis: .vertical)`，聚焦态交给系统焦点环；服务设置用 `Form` 行内的 `TextField` / `SecureField` / `Picker(.menu)`（`entering-data.md`：永不预填密码；`pickers.md`：短列表用弹出式按钮）；快捷键录制控件**无系统组件**，实现用 `Button` + `.glass`，录制中换 `.glassProminent`，注册走 Carbon / `NSEvent`（§7 例外 2）；`⌘ V 粘贴` / `⌘ ↵` / `Esc` 提示在设计图与实现里都保留（§2.2 #7）。

### 3.6 组件 › 内容与状态
- 译文／润色结果 → `Text` + `.textSelection(.enabled)` 与语义字号（`labels.md`：**Make useful label text selectable.**），分区标签行用 `LabeledContent` 或 `Section` 头 + `.secondary`；处理中骨架屏用 `.redacted(reason: .placeholder)` 作用在真实内容上，不手绘灰条。
- 处理中指示 → `ProgressView().controlSize(.small / .mini)` + 状态文字,状态文字是动效之外的载体(整圈呼吸未采纳,T24)；内联提示用 `StatusNote`（`Label` + 恢复 `Button`）就地反馈；学习区块、生词本与历史的提案画面（`learning*`、`saved`、`book-*`、`history-*`）复用同一批系统组件，尚未落地，见 [docs/unimplemented-features.md](unimplemented-features.md)。

### 3.7 系统体验
- 菜单栏常驻入口 → `MenuBarExtra` + `Menu`（`the-menu-bar.md › Menu bar extras`）；全局快捷键没有系统 API 提供"用户可录制"的 UI，注册用 Carbon `RegisterEventHotKey`（§7 例外 2）；应用图标由 `project.yml` 的 `ASSETCATALOG_COMPILER_APPICON_NAME` 指定（当前值 `OwletIcon` 与目录里的 `AppIcon.appiconset` 不一致，`AppIcon.appiconset` 也没有 `appearances` 条目，即没有深色／着色变体，见未实现清单），含 light / dark / tinted 变体。
- 菜单栏与面板的 Owlet 标记 → `Image("OwletMark")`，彩色标记图（紫色眼睛、橙色喙、粉色腮红）；资源必须保持 `template-rendering-intent: original`，改成 `template` 会把它压成单色剪影、丢掉标记的颜色。

## 4. 逐屏对照

与 `design/index.html` 的“状态总览”同一分组：先 7 个已实现分区（应用窗口的文本处理、快捷键、设置，浮动面板的紧凑条、直接替换紧凑提示、展开，菜单栏），再 7 个提案分区（标题以“提案（未实现）”开头）；共 58 个状态、14 个窗口／面板。

| 截图 | 已落到设计里的系统组件 |
| --- | --- |
| `workspace*.png`（结果、空输入、已输入、处理中、润色结果、请求失败、服务未配置、侧栏收起） | 统一工具栏（跨整窗）· 侧栏切换 · 弹出式按钮 `简体中文` · 分段控件 `翻译｜润色` · `TextEditor` · 结果区 `.redacted` 占位 · 行内 `StatusNote` · 底部操作栏 `复制` / `翻译文本`；收起态与展开态共用同一套工具栏 |
| `shortcuts.png` / `shortcuts-recording.png` / `shortcuts-conflict.png` | `Form` 的两个 `Section`（`全局` 录制器 / `面板内` 固定键）· 录制按钮（例外 2）· `清除` · 每个分组的 footer 承载说明与冲突提示；页面没有底部操作栏 |
| `settings.png` / `settings-openai.png` / `settings-saved.png` / `settings-models.png` / `settings-models-loading.png` | inset grouped `Form` · 弹出式按钮／输入框／`SecureField` · 分组容器 · 底部 prominent `保存设置` · 模型列表失败时就地提示与 `重试`（在名称行下方，不替换控件）· 读取中只在页脚给出指示 |
| `loading.png` / `polish-loading.png` / `direct-loading.png` | 紧凑玻璃条 · `ProgressView` · 状态文字 · 玻璃停止按钮；Esc 取消 |
| `error.png` / `format-error.png` / `cancelled.png` / `permission.png` / `unconfigured.png` / `selection-error.png` / `unwritten.png` | 紧凑玻璃条 · 一行说明 · 一个恢复按钮（服务设置／提示词设置／权限设置／手动输入／配置服务／复制结果／重新处理），失败态另有重试图标按钮 |
| `direct-selection-error.png` / `direct-permission.png` / `direct-unconfigured.png` / `direct-error.png` / `direct-format-error.png` / `direct-cancelled.png` | 与上一行逐像素相同：直接替换流程复用同一条紧凑玻璃条与同一套恢复入口，仅快捷键发起的流程不同 |
| `result.png` / `polish.png` / `long.png` / `result-loading.png` / `result-unwritten.png` / `result-notice.png` / `result-cancelled.png` / `menubar.png` / `menubar-menu.png` | `NSGlassEffectView` 面板 · 头部 `Picker(.menu)` + 玻璃图标按钮 · 可选中结果文本 · 底部提示行 + `复制 ⌘⇧C` / `替换 ⌘↩` · 内容区 `StatusNote`；复制结果或写回成功后关闭面板；`MenuBarExtra` 菜单（非 popover） |
| `empty.png` | 已展开且原文为空：`canRetry` 为假，`PanelHeader` 不传 `retry`、`PanelFooter` 默认分支没有按钮，只留快捷键提示；原文栏仍可编辑 |
| `success.png` | 写回成功确认：展开结果内确认替换、动作行以 `完成` 关闭；应用行为为写回成功直接关闭浮窗，此画面仍是原型提案 |
| `book-list.png` / `book-detail.png` / `book-empty.png` / `no-results.png`（提案 · 未实现） | 统一工具栏 · 搜索框 · 弹出式按钮 `全部语言` · `导出…` · `List` 行 · `ContentUnavailableView` 空状态（拟用，未落地） |
| `history-list.png` / `history-detail.png` / `history-empty.png`（提案 · 未实现） | 同构工具栏 · 类型筛选 · 破坏性 `清空历史` · 详情可复制与收藏 |
| `learning.png` / `learning-loading.png` / `learning-error.png` / `learning-empty.png` / `saved.png`（提案 · 未实现） | 展开结果内的独立区块 · `ProgressView`／`.redacted` 占位 · 就地重试 · 可勾选列表与 `收藏所选` · 动作行 leading 端 `收藏选中内容` |
| `aligned.png`（提案 · 未实现） | 逐句对照：配对视图内的系统 `Text`，复制与替换仍只输出译文（§7 例外 3） |
| `settings-prompts.png`（提案 · 未实现） | `Form` 内的 Prompt 分组 · 文本编辑 · `查看默认 Prompt` / `恢复默认` · JSON 返回示例 |
| `workspace-narrow.png`（提案 · 未实现） | 窄窗口（内容区 < 720pt）下的单列堆叠分支；宽窗口并排尚未出图 |

旧原型的 40 个状态现已全部覆盖：`stale` 由 `unwritten` 承载、`settings-shortcuts` 由 `shortcuts-recording` 承载，其余 38 个各有画面（其中 16 个为提案，带“未实现”徽标，逐条记录在 [docs/unimplemented-features.md](unimplemented-features.md)）。

### 4.1 每个状态的实现位置

58 个状态与 `Owlet/` 的对应关系（按实现文件分组；后 16 个是提案，尚无实现文件）：

| 状态 | 实现位置 |
| --- | --- |
| `workspace`、`workspace-empty`、`workspace-input`、`workspace-loading`、`workspace-polish`、`workspace-error`、`workspace-unconfigured` | `Owlet/Processing/TranslationView.swift`（含 TranslationModel 状态机）· `Owlet/App/OwletApp.swift`（窗口与侧栏） |
| `workspace-collapsed` | `Owlet/App/OwletApp.swift`（MainView 的 NavigationSplitView 侧栏） |
| `shortcuts`、`shortcuts-recording`、`shortcuts-conflict`（`ShortcutController.registrationError` 的冲突文案） | `Owlet/Shortcuts/ShortcutSettingsView.swift` · `Owlet/Shortcuts/ShortcutController.swift` |
| `settings`、`settings-openai`、`settings-saved`、`settings-models`、`settings-models-loading` | `Owlet/Settings/ServiceSettingsView.swift` · `Owlet/Settings/SettingsStore.swift` |
| `loading`、`polish-loading`、`direct-loading` | `Owlet/App/PanelController.swift`（ProcessingStrip） |
| `error`、`format-error`、`cancelled`、`permission`、`unconfigured`、`selection-error`、`unwritten` | `Owlet/App/PanelController.swift`（Notice、NoticeStrip、recover）· `Owlet/Selection/SelectionBridge.swift`（权限与读取失败来源） |
| `direct-selection-error`、`direct-permission`、`direct-unconfigured`、`direct-error`、`direct-format-error`、`direct-cancelled` | `Owlet/App/PanelController.swift`：“翻译并替换”复用同一 `Notice`／`NoticeStrip`，与 `selection-error`／`permission`／`unconfigured`／`error`／`format-error`／`cancelled` 同屏 |
| `result`、`polish`、`long`、`result-loading` | `Owlet/App/ExpandedPanel.swift`（PanelHeader／PanelBody／PanelFooter）· `Owlet/App/PanelController.swift`（展开时机） |
| `result-notice`（失败）、`result-cancelled`（取消） | `Owlet/App/ExpandedPanel.swift`（StatusNote）· `Owlet/App/PanelController.swift`（inlineNotice）；失败与取消时 `hasResultSection` 为假，结果区不渲染 |
| `result-unwritten` | `Owlet/App/PanelController.swift`（`writebackRefusal` → `inlineNotice` 返回 `.unwritten`／`.unwritable`）· `Owlet/App/ExpandedPanel.swift` |
| `empty` | `Owlet/App/ExpandedPanel.swift`（`canRetry` 与 `PanelFooter` 默认分支）· `Owlet/App/PanelController.swift`（空原文时 `translate()` 置 `.idle`，展开态保留） |
| `menubar`、`menubar-menu` | `Owlet/App/OwletApp.swift`（MenuBarExtra、MenuContent、MenuBarLabel） |
| `book-list`、`book-detail`、`book-empty`、`no-results` | 提案（T08、T09、T11）：`Owlet/Vocabulary/VocabularyView.swift` 等尚未创建 |
| `history-list`、`history-detail`、`history-empty` | 提案（T15、T16、T17）：`Owlet/History/HistoryView.swift` 等尚未创建 |
| `learning`、`learning-loading`、`learning-error`、`learning-empty`、`saved` | 提案（T10、T13）：`Owlet/Learning/LearningView.swift` 等尚未创建 |
| `aligned` | 提案（T14）：`Owlet/Processing/TranslationView.swift` 只拼接输出译文，没有配对视图 |
| `settings-prompts` | 提案（T12）：`Owlet/LLM/DefaultPrompts.swift` 只有内置默认值，没有编辑界面 |
| `workspace-narrow` | 提案（T22）：`Owlet/Processing/TranslationView.swift` 是单列 `VStack` |
| `success` | 提案（未实现）：原型画写回完成确认；应用 `Owlet/App/PanelController.swift` 的 `performReplace` 在写回成功后直接关闭浮窗 |

## 5. 设计令牌退役表

`spec/DESIGN.md` 的配色表与 `RoseGlass` 已从 `Owlet/` 删除；下表保留为迁移依据。

| 现令牌 | 现用途 | 替换为 |
| --- | --- | --- |
| `RoseGlass.accent` / `ink` / `muted` / `paper` / `line` / `selectedNav` / `tint` / `keyFill` | 主按钮与焦点、正文与标题、次要文字、内容底、分隔线、侧栏选中、录制底色与键帽 | 应用 `AccentColor` 资源（唯一允许的品牌色出口）；`.primary` / `.secondary` / `.tint(nil)`；系统窗口纸张与列表材质；`Divider()` |
| `RoseGlass.errorFill` / `errorText` / `green` / `skeleton` / 粉色渐变呼吸描边 | 错误块、成功、骨架屏、处理中装饰 | `StatusNote`（`Label` + `.secondary`）、`.green`、`.redacted(reason: .placeholder)`；呼吸未采纳，实现只用 `ProgressView`（T24） |
| `RoseGlass.window` / `sidebar` / `footerFill` | 窗口／侧栏／底栏底 | 系统窗口背景、`List` sidebar 外观、底部 safe area bar 材质 |
| `MainButtonStyle` / `MainLabelStyle` / `FieldBox` / `SelectField` / `KbdChip` / `GroupTitle` / `FormRow` / `PageFooter` / `PageHeader` / `SectionLabel` / `NavRow` / `ProcessingStrip` / `NoticeStrip` | 自绘按钮、输入框描边与焦点环、自绘下拉、键帽、自绘窗口与紧凑条零件 | `.bordered` / `.borderedProminent` / `.glass` / `.glassProminent`；`Form` 行内系统 `TextField` + 系统焦点环；`Picker(.menu)`；快捷键归菜单栏与 `.help()`（设计图仍画 `⌘ ↩`，§2.2 #7）；`Form` + `Section`、`.toolbar`、`List`；紧凑条保留玻璃容器，内部只用 `ProgressView`、`Text`、`Label`、`Button(.glass)`、`StatusNote` |

## 6. 关于设置窗口的建议（未改动设计图）

设计图把设置画成主窗口的一个页面，实现也保持这样（§2.2 #11）。若将来采纳 `settings.md › Desktop (macOS)` 要求的**独立窗口**：从应用菜单（`⌘,`）打开，工具栏分栏且按钮常驻不可自定义，最小化与缩放按钮置灰，窗口标题跟随分栏。

1. 设置改为 `Settings` scene + 分栏 `TabView`：**通用**（翻译显示方式、浮窗位置）· **显示** · **提示词** · **服务**（Base URL、API Key、模型）。
2. 侧栏不再出现 `设置` 行；工具栏也不放设置按钮（`settings.md`：**Include a settings item in the App menu.**）。

`settings.png` 的**内容**（inset grouped 表单）与实现一致，差异只在承载窗口，记录在 [docs/unimplemented-features.md](unimplemented-features.md)（T19）。Prompt 编辑分组的提案画面为 `settings-prompts.png`（未实现，T12）。

## 7. 判断与例外

macOS 26 没有提供系统对应物的三处必须自定义；例外 3 对应尚未实现的功能，当前实现还没走到它。

| 例外 | 做法 |
| --- | --- |
| 1 · 内联提示行 | macOS 没有系统 banner，而 `feedback.md` 要求状态反馈就近呈现。做法：`Label(systemImage:)` + 一个恢复 `Button` 放进内容流；失败态另给符号，不靠颜色单独表意。 |
| 2 · 全局快捷键录制控件 | 没有任何系统 API 提供"点击后录制组合键"的 UI，Carbon 的 `RegisterEventHotKey` 只负责注册。实现中录制按钮用 `.glass`，录制中换成 `.glassProminent`（`Owlet/Shortcuts/ShortcutSettingsView.swift`），并保留 `Esc` 取消、`Delete` 清除、冲突提示与 `accessibilityLabel` / `accessibilityValue`。这是本项目唯一不可避免的自定义控件。 |
| 3 · 逐句对照布局（建议，未实现，T14） | 没有系统组件表达“原文／译文按语义句子配对”。做法：`LazyVStack` 内的配对视图，子元素全部是系统 `Text`；配对关系由模型返回，不按显示行推断。提案画面为 `aligned.png`（未实现）。 |

**其余判断（我的判断，不是 Apple 的条文）：**

- 粉色保留为应用强调色。`color.md › App accent colors` 允许应用指定 accent；只要它只出现在强调色、prominent 按钮、选中态与状态指示，就符合 `liquid-glass.md › Color on glass`。**不要**把它散布到每个视图的 tint。
- `本地` 角标删除（它不承载可操作信息，数据存放位置写在设置的"服务"分栏）；`已复制` toast 建议删除（结果已经在界面上）；面板头部的 Owlet 标记改用可着色符号或 template 图像，避免白色 PNG 在浅色玻璃上不可见。

## 8. 验收清单

1–7、9 已随实现落地；8 未达成（菜单栏只有打开主界面、三个快捷键状态、设置与退出，没有覆盖每个工具栏项）；11–12 与 §2.2 的未采纳建议绑定，需要先决定是否采用。

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
11. **适应宽度（未采纳，§2.2 #10）。** 从最小宽度到满宽连续拖动，文本处理页在 720pt 处切换并排／堆叠，无跳变、无截断、无重排抖动。
12. **文案（未采纳，§2.2 #7／#8／#12）。** §2.3 的三条文案规则无例外；界面里找不到快捷键字块与空心提示。

`design/index.html` 控制台里有两个自动检查：

- `checkDesignStates()` → 58 个状态（含提案画面）逐个渲染过一遍：应用窗口状态必须有工具栏与内容区（文本处理页还要有底部操作栏）；浮窗状态必须是浮动面板，紧凑条要有紧凑条元素、展开态要有面板头部与动作行，且动作行不被裁切；`menubar` 只校验状态存在。
- `checkFlowBoard()` → 58 个状态全部出现在总览上、无重复，分区数与定义一致（14 个窗口／面板）；返回 `{states, frames, panels}`。

## 9. 迁移顺序

按影响面从小到大，每一步都可独立验证。

1. 删除 `RoseGlass` 与自绘按钮样式，全部换成系统语义色与系统按钮（已落地）。
2. 主窗口改 `NavigationSplitView`（侧栏可收起）并把工具栏就位：`navigationTitle` + 弹出式按钮（左）+ 分段控件（右）（已落地）。
3. 设置改为 `Settings` scene + 分栏，侧栏与工具栏移除入口（未采纳，T19）。
4. 删除底部动作栏，动作迁入工具栏与内容区；文本处理页在内容区 ≥720pt 时两栏并排（均未采纳，实现保留 safe area bar 与单列 `VStack`，T22）。
5. 列表换 `List` + `.searchable` + `ContentUnavailableView` + 上下文菜单（随生词本／历史一并未实现）；浮动面板的呼吸动画与 `收藏选中内容` 动作行未采纳（紧凑条与动作行已落地）。
6. 菜单栏补全并收口文案（`⌘,` 已接，文案未收口）；辅助功能与外观终检见 §8。

## 10. 参考

HIG 参考资料位于 `.pi/skills/apple-design/references/hig/`：`liquid-glass.md`（`Where the material belongs` / `Which variant` / `Color on glass` / `Review checklist`）、`materials.md`、`color.md`、`layout.md`、`designing-for-macos.md`、`sidebars.md`、`toolbars.md`、`windows.md`、`panels.md`、`split-views.md`、`settings.md`、`the-menu-bar.md`、`buttons.md`、`segmented-controls.md`、`pop-up-buttons.md`、`menus.md`、`search-fields.md`、`lists-and-tables.md`、`boxes.md`、`labels.md`、`text-views.md`、`toggles.md`、`pickers.md`、`progress-indicators.md`、`feedback.md`、`writing.md`、`accessibility.md`、`focus-and-selection.md`、`dark-mode.md`、`generative-ai.md`。组件分类依 Apple 官方目录：<https://developer.apple.com/design/human-interface-guidelines/components>
