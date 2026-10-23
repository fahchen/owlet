[English](screen-region-input.md) · [简体中文](screen-region-input.zh-CN.md)

# 屏幕区域 OCR 输入方案

状态：已实现（2026-10-23）。[BDR-0019](../spec/processing/decisions/BDR-0019-screen-region-input.md) 裁定了待定项，并推翻下文两条：框选改用系统的 `screencapture -i`，不自己画覆盖窗口；截图保留，显示在浮窗并随历史保存。本文其余部分是设计记录。

## 评审结论（2026-10-23）

- **缩略图，不放大图。** 约 38pt 高，圆角按设计图为 8pt（放大后 14pt）。紧凑原文条里、以及还没有内容时，缩略图在原文**左侧**；第一段译文到达、面板展开时，同一个缩略图随展开的弹簧动画移到**右侧**（`matchedGeometryEffect`；减少动态效果时直接切换）。分区显示下在上方原文的右上角、分割线以上，原文绕着它排（TextKit 排除区域，所以只有这个原文框是 `NSTextView`）；逐句对照下在句对区右上角。悬停显示放大镜光标；点击就地放大到占满宽度、原文隐藏，再点缩回，过程有动画。不用 popover。
- **结果的初始状态：** 设置「通用 › 浮窗 › 屏幕区域截图」可选「缩略图」（默认）或「放大」；选放大时结果直接以占满宽度、原文隐藏的状态打开，点击照样切换。
- **截图里没有文字、或截图失败：** 显示紧凑错误条「截图里没有识别出文字」或「没能截图」，出路是「重新框选」；不展开输入框，屏幕区域必须带着文字才继续。模型失败沿用选中文字的形态：原文条（缩略图与识别出的文字）下方一个小错误条。（2026-10-24 评审修订。）
- **历史：** 列表行的时间行占满整行，缩略图在译文、原文两行左侧；详情直接显示截图，图片带一道系统分隔线色的细边框，不加底色、文字或按钮，悬停显示放大镜光标，点击用 Quick Look 打开。

## 为什么先看 SDK

这个来源由系统能力决定边界，所以下面的 API 事实都读自本机 Xcode 27.0／macOS 27.0.1 的 SDK，不凭记忆。SDK 根记作 `$SDK`：

`/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk`

- `$SDK/System/Library/Frameworks/Vision.framework/Modules/Vision.swiftmodule/arm64e-apple-macos.swiftinterface`（下称 `Vision.swiftinterface`）
- `$SDK/System/Library/Frameworks/ScreenCaptureKit.framework/Headers/`、`$SDK/System/Library/Frameworks/CoreGraphics.framework/Headers/`

应用最低 macOS 26（`spec/README.md` 范围边界）。用到的接口落在 15.2—26：`SCScreenshotManager.captureImage(in:)` 是 15.2+，`RecognizeTextRequest` 是 15+，`RecognizedTextObservation.transcript` 到 26 才有。

## 两条前置结论

1. **没有可写回的选区。** `Selection` 的写回依赖 `kAXSelectedTextRangeAttribute` 与可编辑 role；OCR 拿到的是图片、没有 AX 来源，因此 `PanelController.selection` 必须保持 `nil`。结果是：面板只提供「复制结果」，不提供「替换」，这是对的而不是缺口——把译文粘回用户刚才框选的网页图片没有意义。
2. **失败按现有规则可见。** 读不到（无权限、无文字、无模型）必须落到与 `.permission`／`.unreadable` 同形的提示，并给手动输入入口；不得静默结束、不得让空输入进模型（`PanelController.accept` 现有的三条分支就是这条规则的实现）。

## SDK 事实

**一次性的区域截图有直接接口，不需要建流。** `SCScreenshotManager`（`Headers/SCScreenshotManager.h:134`）提供：

- `+captureImageInRect:completionHandler:` → Swift `SCScreenshotManager.captureImage(in:)`，macOS 15.2+（`SCScreenshotManager.h:161`）。注释写明 rect 是「屏幕空间、以点为单位、与显示器无关、支持多显示器」，正好是「拖一个矩形、抓一次」。
- macOS 26 起另有 `+captureScreenshotWithRect:configuration:completionHandler:` → `captureScreenshot(rect:configuration:)`（`SCScreenshotManager.h:179`），配 `SCScreenshotConfiguration`（`width`／`height`／`sourceRect`／`destinationRect`／`showsCursor`／`ignoreShadows`／`dynamicRange`，`SCScreenshotManager.h:46`）与 `SCScreenshotOutput`（`sdrImage`／`hdrImage`，`SCScreenshotManager.h:118`）。区域截图用前一个就够，`SCScreenshotConfiguration` 只在需要显式尺寸或 HDR 时才有意义。

**不需要 `SCShareableContent`／`SCStream`。** 那一套（`SCShareableContent.getShareableContent...`、`SCContentFilter`、`SCStream`＋`SCStreamOutput`、`SCStreamConfiguration.sourceRect`）是为「先选一个窗口／显示器，再持续出帧」准备的；`SCShareableContent.h:152`、`SCStream.h:507`、`SCStream.h:289`。矩形区域截图走 `captureImage(in:)` 时没有 filter、没有 stream、没有 `SCStreamOutput` 回调，少一层生命周期与错误面。

**选窗器里没有区域模式。** `SCContentSharingPickerMode` 只有 `SingleWindow`／`MultipleWindows`／`SingleApplication`／`MultipleApplications`／`SingleDisplay`（`Headers/SCContentSharingPicker.h:19`）。所以矩形框必须由应用自己画；不能指望系统给一个「框选区域」的 picker。

**旧路径已经作废。** `CGWindowListCreateImage` 与 `CGWindowListCreateImageFromArray` 带 `SCREEN_CAPTURE_OBSOLETE(10.5,14.0,15.0)`（`CGWindow.h:271`、`CGWindow.h:280`），宏展开是 `availability(macos, introduced, deprecated, obsoleted, message="Please use ScreenCaptureKit instead.")`（`CGWindow.h:223`）：macOS 14 起废弃、macOS 15 起 obsoleted。不要用。

**OCR 是新版 Swift Vision，不是 `VNRecognizeTextRequest`。** `Vision.swiftinterface`：

- `RecognizeTextRequest`（macOS 15+，`:2591`），`Result = [RecognizedTextObservation]`；`init(_ revision: RecognizeTextRequest.Revision? = nil)`（`:2604`）。
- `RecognizeTextRequest.Revision` 在本 SDK 的公开枚举里只有 `case revision3`（`:2593`），`supportedRevisions` 是静态属性（`:2635`）。
- `RecognitionLevel`：`case accurate`／`case fast`（`:2605`）；可设 `recognitionLanguages: [Locale.Language]`、`automaticallyDetectsLanguage: Bool`、`usesLanguageCorrection: Bool`、`customWords: [String]`、`minimumTextHeightFraction: Float`、`regionOfInterest: NormalizedRect`（`:2621`—`:2633`）；`supportedRecognitionLanguages: [Locale.Language] { get }`（`:2627`）是实例属性，运行时才知道这台机器有哪些语言。
- `ImageRequestHandler`（`:2179`）接受 `URL`／`CGImage`／`CIImage`／`CVPixelBuffer`／`CMSampleBuffer`／`Data`（`:2180`—`:2185`）；`perform(_:) async throws -> T.Result`（`:2186`）。截图给的是 `CGImage`，所以 `ImageRequestHandler(image)` 直接可用，中间不需要落盘。
- `RecognizedTextObservation` 有 `transcript: String`（macOS 26+，`:1450`）、`topCandidates(_:) -> [RecognizedText]`（`:1476`）、`boundingRegion`／四角点／`confidence`（`:1462`—`:1470`）；`RecognizedText.string`／`confidence`（`:1862`、`:1865`）。拼阅读顺序时用 observation 的坐标，不要假设数组已经是行序。

**Vision 在本机算。** 请求暴露 `supportedComputeStageDevices` 与 `setComputeDevice(_:for:)`（`:2630`、`:2639`），即推理落在本地 CoreML 设备上；接口里没有任何网络或服务器参数。这不等于「识别一定准」，准确率见末节。

## 用户流程

1. 用户按快捷键（第二个快捷键，或在设置里给现有快捷键选「来源：选中文字／屏幕区域」）。
2. 先 `CGPreflightScreenCaptureAccess()`（`CGWindow.h:300`）。为假时只调一次 `CGRequestScreenCaptureAccess()`（`:308`）触发系统授权；仍为假就显示提示，动作按钮打开「系统设置 › 隐私与安全性 › 屏幕录制」，并提供手动输入。不读屏、不发模型请求。
3. 全屏覆盖窗口画选框：拖拽出矩形、可再调整、Esc 取消、松开即确认。覆盖窗口不复用浮窗（`FloatingPanel` 是面板语义，不是全屏遮罩）。
4. 用屏幕点坐标调 `captureImage(in:)`，得到 `CGImage`。
5. `RecognizeTextRequest` 走 `ImageRequestHandler`，把 `[RecognizedTextObservation]` 按坐标拼成一段文本。
6. 文本进入现有路径：设 `model.input`，再 `PanelController.processCurrentText()`；`selection` 保持 `nil`。

## 已在评审确定

### 区域选择：只由应用自己画

**不接入 `SCContentSharingPicker`。** 它没有区域模式（`SCContentSharingPickerMode` 只有窗口／应用／显示器，`SCContentSharingPicker.h:19`），保留它只会多出「先选窗口、再框区域」的两步交互。用户自己拖一个矩形就够了：一次交互、一次截屏，屏幕上任意矩形都能框。因此唯一的区域来源是应用自己画的覆盖窗口。

### OCR 语言：自动检测

请求打开 `automaticallyDetectsLanguage`（`Vision.swiftinterface:2621`—`:2633`），不预先钉 `recognitionLanguages`：用户框一段日文，就不该先让他去设置里声明语言。

检测是 SDK 内部行为，接口只给一个 `Bool`，**没有语言置信度可读**，所以检测错时应用无从判断；错误只会以「译文不对」的形式出现。规则沿用现有的诚实失败：用户看到错的结果，改原文或重新框选重试；应用不猜、不静默换语言。

钉死语言（设置里指定 `recognitionLanguages`）保留为**后续可选项**，本轮不做：它的价值只在自动检测失败之后，而「哪种区域会检测错」目前没有数据。是否值得做、放在哪一层，取决于末节的实测。

### 阅读顺序：模型兜底，应用不做分栏几何

SDK 只给坐标与 `transcript`（`:1450`、`:1462`—`:1470`），不给阅读顺序。应用只按坐标做最基本的拼接（自上而下），**不检测分栏、不猜段落结构**：分栏是屏幕排版、不是语言事实，写死几何规则会在下一次排版变化时错。拼接出的整段文本交给模型，由模型按标点与语义排出顺序。

代价要写清楚：模型拿到的是文本、没有坐标，所以栏间顺序错了不会当场暴露，而是在译文里以「顺序不对」的形式出现。因此面板必须一直显示并可编辑本次 OCR 的原文（`model.input` 本身就是这个位置），让用户能对着译文核对；应用不替用户判断顺序对不对。

### 截图不保留

截图只存在于内存：`captureImage(in:)` → `CGImage` → `ImageRequestHandler` → 识别完即丢，不落盘、不进历史、不进调试日志。没有文件要清理，也没有像素可泄漏；代价是用户事后无法「查看原图」核对识别结果，所以「重试」是重新框选一次，而不是重跑上一张图。

### 如果所选模型本身能读图：可选路径

[`BDR-0013` §9](../spec/settings/decisions/BDR-0013-local-agent-provider.md) 已经把「模型层携带图片」记为一个计划中的扩展点（`ModelTurn` 将来加内容分片，文本今天、图片以后，由各 backend 各自映射）。在这个扩展点落地后，当配置的 provider 声明接受图片时，可以不走本地 OCR：把区域图直接交给模型，由模型同时认字与翻译。这条路要求模型层能携带 image，并且**只在所选 provider 确实接受图片时才出现在界面上**；否则不显示这个选项，也不发图片。

两条路的差别要写清楚：本地 OCR 那条路的原文来自 Vision，可在面板里逐字改；模型读图那条路的原文来自模型自己返回的 `source`（现有契约本来就要求返回并做拼接校验，见 [LLM 返回契约](../spec/llm/contract.md)），用户改的是模型认出来的字、不是屏幕上的字。两条路都保留「原文可见可编辑」，也都不保留图片。

未验证，设计不假设：

- 本机支持的 provider 里今天到底哪些接受图片输入（OpenAI 兼容端点、DeepSeek、Claude Code、Codex CLI 各自的情况）。
- 本地 agent CLI 有没有传图通道：`BDR-0013` §9 只说到「以后加」，没说怎么加。
- 模型读图与本地 OCR 在中文／日文小字上的准确率差多少。

在实测之前，这条路径只作为「provider 声明支持时的可选项」，不写进产品定义，也不作为默认。判断 provider 是否支持沿用现有的厂商能力开关（`ServicePreset`，经 `ServiceConfig` 到达请求；DeepSeek 只支持 `json_object` 就是这么表达的），新增一个「接受图片」的能力位；能力位今天只能按预设手写，值从实测来。

## 失败在哪一步可见

| 失败 | 呈现 |
|---|---|
| 无屏幕录制权限 | 提示 + 「打开屏幕录制设置」+ 手动输入；不启动覆盖窗口 |
| 用户 Esc 取消 | 直接关闭，不产生提示（与 `stop()` 的取消同形） |
| 区域过小／全黑／截图报错 | 提示 + 手动输入 |
| OCR 返回空 | 按 `.unreadable` 同形提示 + 手动输入；不请求模型 |

截图与 OCR 都可能返回「有图但没文字」，这与「没读到选区」是同一类用户体验，不要新造一种静默状态。

## 接入与新增 seam

- `RegionCapture`：`(CGRect) async throws -> CGImage`。测试注入固定 `CGImage`，不碰屏幕。
- `TextRecognizer`：`(CGImage) async throws -> String`。测试注入固定字符串，不碰 Vision；本轮实现只打开 `automaticallyDetectsLanguage`，不读 `recognitionLanguages`，`supportedRecognitionLanguages`（`:2627`）留到钉死语言成为可选项时再用。
- 覆盖窗口只负责产出 `CGRect`，不读像素；它是唯一必须在真机上人工验证的一层。
- `PanelController` 增加一个与 `accept(.success)` 同形的入口（导入文本、清 `selection`、`processCurrentText()`），不改现有读取分支。
- 「模型读图」路径若落地，改动落在模型层的能力开关与 `ModelTurn` 的内容分片上，不新增第二个读取分支。

## 权限与隐私

| 能力 | usage-description | 用户可见授权 | 沙盒 |
|---|---|---|---|
| ScreenCaptureKit `SCScreenshotManager.captureImage(in:)` | **本机 SDK 中不存在 `NSScreenCaptureUsageDescription`**（已在 `$SDK/System/Library/Frameworks/` 下全文搜索，无匹配） | TCC「屏幕录制」；由 `CGRequestScreenCaptureAccess()` 触发，已被拒绝的进程不会再次弹出，只能去系统设置里打开（`CGWindow.h:303`—`:305`） | 沙盒下需要屏幕录制相关 entitlement，SDK 不含其名称；本应用不沙盒，故直接走 TCC |

`spec/README.md` 的范围边界写明本应用「本机签名自用，不启用 App Sandbox」，所以授权直接走 TCC。沙盒下不是「做不到」，而是还多一道 entitlement；本机 SDK 不包含 entitlement 名称表，无法在此证实，因此那一列只标出差异、不写具体键名。屏幕像素与识别出的文本都不进诊断日志；这是现有「仅在用户触发时读取」隐私约定的自然延伸。

## 仍未定

- 快捷键形态：加第二个快捷键，还是给现有快捷键加「来源：选中文字／屏幕区域」。
- 「模型读图」选项的粒度（全局开关还是按 provider 记忆），以及它与本地 OCR 是并列还是先后。
- 钉死语言的落地时机与入口位置（方向已定：后续可选项）。

## 必须实测（SDK 不回答的部分）

- Vision 在中文、日文、竖排、小字号与截图缩放下的真实准确率与错字形态。
- 自动语言检测在「中英混排」「只出现几行英文」这类区域上的实际选择——接口只给 `Bool`，没有置信度可读。
- 多栏排版下「按坐标自上而下拼接 + 模型兜底」的实际效果与顺序错误率。
- 本机支持的 provider 里今天哪些接受图片输入，以及本地 agent CLI 的传图通道。
- 模型读图与本地 OCR 在中文／日文小字上的准确率差距。
- 屏幕录制 TCC 提示在 macOS 27 上的确切文案与系统设置里的分组名称（SDK 只写到旧名称「Screen Recording」）。
- 沙盒下屏幕录制需要的 entitlement 名称。

以上都是「必须实测」，不是「预期如此」；在实测之前不得写进 `spec/`，也不得在界面上承诺。
