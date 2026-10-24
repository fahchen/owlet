[English](panel-debugging-and-testing.md) · [简体中文](panel-debugging-and-testing.zh-CN.md)

# Panel 调试、测试与截图记录

记录日期：2026-10-07。对应实现提交：`cb2717d`。范围为浮窗；主窗口学习流程不变，通用设置新增浮窗玻璃效果选择。

## 已沉淀的设计偏好

用户明确表达的通用原则与 panel 具体要求已归入 [视觉与交互规则](../spec/DESIGN.md#2026-10-07-用户确认的设计倾向)：原生组件、检查组件详情、忠实字号和状态、玻璃可读性、对齐与留白、连续过渡、即时收藏，以及真实状态截图验证。该节覆盖旧原型中相冲突的 panel 描述，不扩展主 app 范围。

## 先核对设计组件，再修改实现

唯一布局来源是 [Figma 画板 6313:31216](https://www.figma.com/design/PL0seWKhVgNHzaHLFbWLaQ/macOS-27--Community-?node-id=6313-31216)。通过 computer use 选中实例，查看右侧 Design 面板的组件名、变体、尺寸与字体，并跳转 master 核对。不能根据截图外观猜组件，也不能引用其他页面作为布局依据。

实例与 master 的对应表保存在 [Liquid Glass 组件对照](liquid-glass-components.zh-CN.md#t42-精确画板组件核对)。此次关键发现：

- 状态条及组合操作是 Segmented Control，不能用多个 Button 拼装。
- 独立动作是原生玻璃 Button，收藏行是 borderless Button。
- 正文为 17pt regular、设计行高22pt；动作图标13pt medium，圆形按钮36pt。
- panel 宽773pt，结果高257pt，学习高295pt；正文与底部动作共用24pt边界。
- Figma 大表面圆角34pt；当前使用系统默认 roundedRectangle，并未完全复现该半径。

## 分开验证行为、布局与材质

| 验证层 | 方法 | 能证明什么 | 不能证明什么 |
| --- | --- | --- | --- |
| 行为回归 | Swift Testing、注入依赖、隔离存储 | 取消、收藏切换、设置持久化等契约 | 玻璃、hover、动画观感 |
| 状态截图 | 原生预览 + 系统窗口截图 | 字号、边界、分隔、不同状态内容与静态材质 | 实际鼠标点击、动画连续性、完整 app 路径 |
| 交互验收 | 解锁后的真实窗口操作、录屏或 UI 自动化 | hover、按下、焦点、窗口变化与动画 | 仅靠截图不能替代此层 |
| 模型联调 | 预览的 `--live` | 当前供应商响应及本地契约校验 | 固定响应的稳定回归 |

`mise run check` 运行 lint、工程生成与测试，不等同于 XCUITest 或视觉验收。本轮没有完成 XCUITest 截图、真实 hover／按下截图或动画录屏。

## 可复现的原生预览

工具为 [panel-preview.py](../scripts/panel-preview.py) 和 [PanelPreview.swift](../scripts/PanelPreview.swift)。需要 macOS 26、Xcode 工具链；编译产物在 `.build/panel-preview/`，不提交。

```sh
# 查看参数
python3 scripts/panel-preview.py --help

# 固定内容、模拟模型的交互预览
python3 scripts/panel-preview.py

# 自动导出七个状态；不需要 computer use
python3 scripts/panel-preview.py --screenshots /tmp/owlet-panel-states

# 同背景对比材质；背景为自行准备的本地文件
python3 scripts/panel-preview.py --screenshots /tmp/owlet-panel-states --background /绝对路径/背景.png

# 仅对照系统控件的活跃外观
python3 scripts/panel-preview.py --screenshots /tmp/owlet-panel-active --active

# 离屏渲染「通用」设置页；不需要屏幕录制权限
python3 scripts/panel-preview.py --settings /tmp/owlet-settings-pane

# 主窗口生词本、历史两页（窗口后垫纯色窗口，只截主窗口）与语言设置页（离屏），供官网用
python3 scripts/panel-preview.py --app-shots /tmp/owlet-app-shots

# 屏幕区域翻译的 10 个状态，在真实 PanelController／FloatingPanel 上逐个跑出并按窗口截图
python3 scripts/panel-preview.py --region /tmp/owlet-region-states

# 录制真实 PanelController／FloatingPanel 从翻译中到结果的过渡（.mov，约 4 秒）
python3 scripts/panel-preview.py --transition /tmp/owlet-panel-transition.mov
```

屏幕区域（`--region`，BDR-0019）：截图、OCR、屏幕录制权限和模型全部是夹具，不碰屏幕、Vision 或服务。截图是进程里画的两行英文，OCR 直接给出这两行，模型按请求的目标语言回复，也可以模拟连接失败、未配置与格式错误。依次导出 `01-permission`、`02-capture-failed`、`03-no-text`、`04-translating`、`05-result`、`06-result-aligned`、`07-result-zoomed`、`08-connection-failure`、`09-missing-config`、`10-format-failure`。逐句对照那一张通过预览进程自己的 UserDefaults 设置显示方式，结束时清除。截图用 `screencapture -l` 按窗口截，需要屏幕亮着、终端有屏幕录制权限；预览进程不带本地化资源，界面是英文。

过渡录制走生产展开路径，模拟模型延迟 1.5 秒返回；用 `ffmpeg -i <mov> -vf fps=30 f%03d.png` 拆帧逐帧检查。录制进程独立结束，主线程不等待它，否则动画会被阻塞。

查词交互（T48）用真实控制器：`--panel` 以 accessory 应用打开真正的 `PanelController`／`FloatingPanel`（隔离 suite 固定目标为 en），夹具查词延迟 1.2 秒，“frost”首次返回违约内容以驱动失败与重试；`--no-voice` 模拟没有系统语音；`--target ja|zh-Hans` 换结果语言，`--appearance dark|contrast|darkContrast` 只改预览进程外观；`--main` 用夹具与内存存储打开主窗口的文本处理、生词本、历史三页。合成鼠标键盘需要终端已有辅助功能权限；不改系统外观或语音设置。

交互预览使用 ⌘1–⌘5 切换：处理中、未配置模型、连接失败、成功、学习。预览窗口固定1030×550pt，截图实际像素随屏幕缩放变化。

自动导出：

| 文件 | 状态 |
| --- | --- |
| `processing.png` | 翻译中及停止操作 |
| `missing-config.png` | 缺配置及设置操作 |
| `connection-failure.png` | 连接失败及重试操作 |
| `success.png` | 结果及学习／复制操作 |
| `learning.png` | 学习双栏、未收藏 |
| `learning-selected.png` | 第一词条已收藏 |
| `learning-deselected.png` | 第一词条取消收藏 |

后两张通过直接调用正式的 `CollectionAction.setCollected` 切换，并检查存储成员状态。它们是状态截图，不是鼠标按下截图，也未覆盖真实点击命中区域。每态等待1秒再截图是渲染缓冲，不是生产加载耗时或动画性能指标。

设置页离屏导出（`--settings`）：把 `GeneralSettingsPane` 用 `NSHostingView` 装进固定 620×660pt 画布，`cacheDisplay(in:to:)` 画进 2x 位图后写 PNG，不打开窗口、不申请任何权限，因此**不需要屏幕录制授权**（`--screenshots` 仍然需要）。`ImageRenderer` 在本机渲染同一视图是**全白空图**（`Form` 分组、`Picker`、`Toggle` 都没画出来），所以没有采用它。默认值写在隔离 suite `dev.fahchen.owlet.panel-preview`，导出前后不触碰主 app 的设置；末尾会移除临时写入的键。设置页是普通分组 `Form`、没有玻璃表面，所以离屏绘制与窗口一致；浮窗的 Liquid Glass 由窗口服务器合成，这条路子**不能**替代 `--screenshots` 的材质验收。模型页（`settings-model-deepseek`／`-anthropic`／`-responses`）在一次真实的测试运行后导出：`ModelSettingsPane.runTest` 走真实的 `ModelClient` 与契约校验，只把网络换成 fixture，它按各协议的信封、延迟后作答，所以图上的耗时与回复是测出来的，不是手填的。设置页拿到的是假的读 Key 函数，导出不会读钥匙串（存过 Key 的服务会被钥匙串授权框卡住）。

| 文件 | 状态 |
| --- | --- |
| `settings-general-off.png` | 浅色，Panel 段新增开关关闭（默认） |
| `settings-general-on.png` | 浅色，同一开关打开 |
| `settings-general-off-dark.png` | 深色，开关关闭 |
| `settings-general-on-dark.png` | 深色，开关打开 |

预览复用生产 View，但未走完整 PanelController／FloatingPanel 展开路径，因此不能用预览静态截图认定真实窗口 spring 已验收。

### 隔离权限、存储与密钥

- 使用固定原文，不读取用户真实选区，不请求辅助功能等权限。
- 默认注入模拟 ModelClient，无真实模型调用；收藏使用内存 SwiftData。
- UserDefaults 使用独立 suite `dev.fahchen.owlet.panel-preview`，与主 app 隔离；该 suite 会持久化，并非每次启动自动清空。
- `--active` 等预览参数仅传给子进程，不修改系统或共享测试配置。
- 真实联调用 `python3 scripts/panel-preview.py --live`，从既有进程环境读取 `DEEPSEEK_API_KEY`；不要把值写进命令、日志、文档或仓库。常规回归无需 Key。
- 本轮真实翻译通过；真实学习响应未通过结构校验，按错误处理。这不是成功的学习联调，也不能以模拟成功截图替代。

## 截图与玻璃调试的经验

### 系统合成截图才保留玻璃

曾尝试 AppKit `cacheDisplay`，但结果遗漏玻璃合成与部分按钮效果，不能作为材质验收依据。最终使用：

```sh
/usr/sbin/screencapture -x -l <windowNumber> /绝对路径/状态.png
```

预览脚本从自身窗口取得 windowNumber，调用系统截图并检查退出码。`--background` 将参考背景放入同一预览窗口，便于比较玻璃对背景的处理，不修改系统壁纸。

本机本轮 computer use 在锁屏时不可用，但上述窗口截图仍成功。因此“computer use 不可用”不代表“所有截图方式不可用”；这个结果也不能推广成所有机器、权限状态或 XCUITest 都可在锁屏下工作。

### 一层玻璃，保留原生控件

NSSegmentedControl 采用 momentary／fit；关闭 cell 自带边框，由外围单层 glassEffect 提供材质，修复翻译中双层背景。独立按钮保留标准 Button.glass，不用手绘背景、边框或自定义 ButtonStyle。

更透明／更高对比度对应系统 Glass.clear／regular，默认 regular；不靠自定义 alpha 模拟玻璃。

曾试过调整外层玻璃所在层级、改为 borderless + interactive glass，截图没有证明改善，均已撤回。不要将试验截图当作最终实现证据。

### 图标颜色要设置在标签内

只给 Button 外层加 `.foregroundStyle(.primary)`，本轮截图中图标仍然偏淡。改为给 Button 内的 Label 设置系统主前景色后，关闭、复制图标明显加深；保持深浅色适配与原生玻璃样式。

`--active` 仅覆盖预览的 controlActiveState，用于诊断活跃／非活跃颜色；它不是真实窗口激活、hover 或按下状态，也未解决用户提出的所有玻璃观感差异。

### 排版与动画的检查点

- 底部按钮右边界与正文共用24pt inset，不能只凭外轮廓目测。
- 学习分隔线上下内缩24pt；收藏图标随整行内容垂直居中。
- 学习译文用原生 NSTextField justified 段落对齐，末行自然对齐。曾开启断词导致大量连字符，已移除。
- SwiftUI 内容与 NSAnimationContext 窗口使用同一 spring；减少动态效果时直接定位。仍需真实窗口录屏确认连续性。

## 检查命令与失败处理

```sh
mise run format
mise run check
mise run dev
```

以退出码判断成败，不能只 grep `error:`；Xcode 的 `Failing tests:`／`TEST FAILED` 可能漏检。最终实现及提交钩子的完整检查均通过。

`mise run dev` 曾构建成功，但 `open` 返回 LaunchServices `-600`；不能因此报告整个命令成功。确认构建成功后，重试新实例启动成功：

```sh
open -n .build/Build/Products/Debug/Owlet.app
```

不要在预览 swiftc 编译期间改源文件，否则可能出现 input file modified during build；等待编译完成后再改再跑。避免同时运行多个同 bundle 的预览。

回归覆盖包括取消后迟到结果、原生控件与分隔尺寸、玻璃设置隔离持久化、收藏反复切换／去重／其他词条保留。独立 AppStorage 实例不能替代挂载中的 SwiftUI 视图：持久化测试验证重开后的值，不据此声称已测试跨视图即时刷新。

## 尚待验收

- Figma 34pt 圆角与系统默认圆角的差异；遵守原生组件约束，不擅加手写圆角。
- 底部玻璃按钮在真实活跃窗口的材质观感、hover 和按下状态。
- 真实 panel 从处理中到结果、从结果到学习的动画连续性。
- 深色模式及系统减少透明度／增强对比度的视觉组合。
- 错误分段文字与 Figma 红色的差异；当前原生 NSSegmentedControl 尚未实现逐段红色。

临时截图保存在 `/tmp`，不保证长期保留。本轮最终图标截图目录为 `/tmp/owlet-panel-icon-primary/`；长期复现应使用上述脚本重新生成，并记录系统外观、玻璃设置、是否使用 --active 及背景来源。T42 仍为待视觉复核，不能把测试通过写成完全设计对齐。
