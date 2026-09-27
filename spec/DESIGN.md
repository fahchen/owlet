# Owlet · 视觉与交互规则

## 设计规则（优先于下文）

- 全部组件使用 macOS 26 原生 SwiftUI / AppKit，不手写控件：不用自定义颜色、tint、accent token，不加自定义填充、边框、渐变、光晕、阴影、圆角样式、下划线链接或自定义 ButtonStyle。
- 组件对照见 [docs/liquid-glass-components.md](../docs/liquid-glass-components.md)。`design/screenshots/` 中的每个组件都已对应到原生组件；实现按该文执行。
- 两条判据：
  1. **Liquid Glass 只属于功能层**——工具栏、侧边栏、浮动面板、弹出视图。内容层（正文、结果、卡片、列表行、分组容器）用系统材质，绝不叠玻璃。
  2. **能用系统组件就不用自定义**——系统组件自动获得 Liquid Glass 外观、Vibrancy、焦点环、键盘与 VoiceOver 支持，以及 Reduce Transparency / Increase Contrast / Reduce Motion 适配。
- 窗口骨架用系统组件：`Window` scene + `NavigationSplitView`（侧栏可收起，`⌃⌘S`）、`.toolbar`、`List` 与 `MenuBarExtra`。独立 `Settings` scene 未实现（设置是主窗口的侧栏页面），`.searchable` 与 `ContentUnavailableView` 原本服务于生词本与历史，同样未落地，见 [docs/unimplemented-features.md](../docs/unimplemented-features.md)。
- 按钮按层选样式：工具栏项用系统工具栏按钮；动作行（应用窗口底部操作栏、设置与快捷键页脚、浮动面板底部）统一用 `.glass` / `.glassProminent`，包在 `GlassEffectContainer` 中。实现中没有使用 `.bordered` / `.borderedProminent`。
- 每屏只有一个 prominent 动作，放在 trailing 端。
- 使用系统强调色、系统语义色、系统字体与 SF Symbols。品牌玫瑰色只作为应用 `AccentColor` 资源，出现在强调色、prominent 动作、选中态与状态指示，不散布到各视图的 tint。
- 不提供应用级外观开关；浅色与深色都走系统语义色。
- `design/screenshots/` 只约束布局（元素顺序、位置、尺寸、间距）与状态，不约束组件样式。组件样式以本文与组件对照文为准。

### 文案规则（提案，尚未应用）

1. **动作区只放动作。** 工具栏与动作行里不放解释性文字；状态由内容区、悬停提示或菜单栏承担。
2. **界面不展示快捷键。** 快捷键的唯一出处是菜单栏（`.keyboardShortcut`）与悬停提示（`.help()`）；不把 `⌘↩` 画进按钮，也不写“快捷键未设置”。快捷键页面本身例外，绑定就是它的内容。
3. **按钮用动词，宾语交给上下文。** 同一屏的控件已经说清宾语时，按钮不重复它：`翻译`、`润色`、`复制`、`保存`、`收藏`、`导出…`。宾语会歧义时才保留，如 `恢复默认`、`清除筛选`。

同一动作在同一产品里只用一个叫法。

当前应用尚未采用这套规则：文本处理页在「原文」标签右侧画 `⌘ V 粘贴`，浮动面板动作行左端显示快捷键提示（`Esc 取消` / `快捷键未设置` / 已录制的全局快捷键 + ` 唤起`），按钮读作 `翻译文本` / `润色文本` / `保存设置`。差异与后续任务见 [docs/unimplemented-features.md](../docs/unimplemented-features.md)。

## 布局约束（沿用）

中性浅色界面，玫瑰粉作为品牌强调色，用于白天阅读与工作沟通中短暂唤起的语言工具。保留系统字体、紧凑布局与 Liquid Glass 材质。

- 文本处理页是单列：原文与译文始终上下堆叠（实现为单个 `VStack`）。响应式的左右并排未实现，见 [docs/unimplemented-features.md](../docs/unimplemented-features.md)。
- 译文仅比原文大 1px：浮动面板原文 12px、译文 13px；应用窗口原文 16px、译文 17px。润色结果沿用同一层级。
- 浮窗宽 560px，紧凑条 430px；应用窗口默认 1080 × 690，最小 760 × 500。
- 复制与替换只输出译文。「逐句对照／切换显示方式」未实现，见 [docs/unimplemented-features.md](../docs/unimplemented-features.md)。

## 已退役的配色令牌

下表是早期浏览器原型（`design/index.html` 的 `:root`）的取值，仅作历史记录。原生实现不定义任何自定义颜色令牌；玫瑰色的唯一出口本应是应用的 `AccentColor` 资源，**当前工程还没有该资源，也没有任何 `.tint()`**，所以 prominent 按钮与选中态实际跟随系统强调色。这条差异记在 [未实现功能清单](../docs/unimplemented-features.md)。

| 角色 | OKLCH | 原生替代 |
|---|---|---|
| 玫瑰强调 | 47% .17 350 | 应用 `AccentColor` 资源（尚未添加）；添加后系统在"多颜色"设置下采用，其它设置下被用户选择覆盖。当前无 tint，按钮用系统强调色 |
| 花瓣浅粉 | 95% .025 350 | 系统 source list 选中外观 |
| 深色正文 | 27% .008 265 | `.primary` / `NSColor.labelColor` |
| 中性次要文字 | 45% .008 265 | `.secondary` / `NSColor.secondaryLabelColor` |
| 近白底色 | 99% .003 265 | 系统窗口背景与纸张材质 |
| 分隔线 | 60% .012 350 / .17 | `Divider()` / `NSColor.separatorColor` |
| 错误填充与文字 | 96% .025 45 / 43% .1 40 | `.red` 与系统材质底 |
| 成功 | 43% .09 158 | `.green` |

粉色只负责品牌与交互强调。成功保留绿色，错误保留系统红，避免与品牌粉混淆。背景、玻璃面板与正文保持中性灰白；玫瑰色集中在强调色、prominent 动作、选中态与处理中指示。处理中的整圈边框呼吸灯仍是待做设计：动画只作用于玻璃面板自身的 `border-color` 与边缘阴影，不使用粉色渐变描边，也不新增额外图层；减少动态效果时呼吸静止为稳定亮边。应用当前只用 `ProgressView`，见 [docs/unimplemented-features.md](../docs/unimplemented-features.md)。
