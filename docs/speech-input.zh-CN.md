[English](speech-input.md) · [简体中文](speech-input.zh-CN.md)

# 连续语音输入方案

状态：设计提案，未实现，**本轮不做**。本文件只讨论「说话怎么变成输入」，不改变 `SelectionBridge` 的读取路径、浮窗、翻译契约与学习契约；没有用户可见字符串进入 `strings/translations.json`。屏幕区域输入已拆到 [屏幕区域 OCR 输入方案](screen-region-input.zh-CN.md)。

## 为什么先看 SDK

这个来源由系统能力决定边界，所以下面的 API 事实都读自本机 Xcode 27.0／macOS 27.0.1 的 SDK，不凭记忆。SDK 根记作 `$SDK`：

`/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk`

- `$SDK/System/Library/Frameworks/Speech.framework/Modules/Speech.swiftmodule/arm64e-apple-macos.swiftinterface`（下称 `Speech.swiftinterface`）
- `$SDK/System/Library/Frameworks/AVFoundation.framework/Headers/`（`AVCaptureDevice.h`）

应用最低 macOS 26（`spec/README.md` 范围边界）。新版 Speech 接口正好从 macOS 26 起；例外是 macOS 27 才有的 `CaptureInputSequenceProvider` 与 `AnalyzerInputConverter`，在最低版本上要自己用 `AVAudioEngine` 产出 `AnalyzerInput`（macOS 26 的 `init(buffer:)`），或加 `if #available(macOS 27, *)`。

## 两条前置结论

1. **没有可写回的选区。** `Selection` 的写回依赖 `kAXSelectedTextRangeAttribute` 与可编辑 role；语音拿到的是没有 AX 来源的文字，因此 `PanelController.selection` 必须保持 `nil`。结果是：面板只提供「复制结果」，不提供「替换」。
2. **失败按现有规则可见。** 读不到（无权限、无文字、无模型）必须落到与 `.permission`／`.unreadable` 同形的提示，并给手动输入入口；不得静默结束、不得让空输入进模型（`PanelController.accept` 现有的三条分支就是这条规则的实现）。

## macOS 的 STT 今天是什么样

SDK 里有**两代**接口，都还在：

- **新版（macOS 26+，纯 Swift，接口里没有网络路径）**：`SpeechAnalyzer` 是 `actor`（`Speech.swiftinterface:228`），`async` 接口；模块是 `SpeechTranscriber`（`:346`）与 `DictationTranscriber`（`:70`，tvOS 不可用）。模型以本机资产形式由 `AssetInventory`（`:33`）管理。
- **旧版**：`SFSpeechRecognizer`（`Headers/SFSpeechRecognizer.h:78`）。**在本 SDK 里没有被标记废弃**——Speech 头文件里仅有的 `API_DEPRECATED` 是 `SFSpeechLanguageModel.h:58`、`:62` 的两个方法。它的文档明说「有些语言需要联网」（`SFSpeechRecognizer.h:54`、`:83`），且 `requiresOnDeviceRecognition` 只有在 `supportsOnDeviceRecognition` 为真时才被采纳，为假时「需要网络才能识别」（`Headers/SFSpeechRecognitionRequest.h:63`）。连续音频用 `SFSpeechAudioBufferRecognitionRequest`，`appendAudioPCMBuffer:` 持续追加、`endAudio` 才停（`SFSpeechRecognitionRequest.h:148` 起）。

选型倾向新版：接口是 `async`／`AsyncSequence`，与本项目的 Swift 6 严格并发一致，且有资产状态与 `progress` 可讲清楚「模型还没装好」；旧版的网络行为会让「有没有网」成为产品状态的一部分。

新版关键符号：

- `SpeechAnalyzer.init(modules:options:)`、`start(inputSequence:)`、`analyzeSequence(_:) -> CMTime?`、`finalize(through:)`、`finalizeAndFinishThroughEndOfInput()`、`cancelAndFinishNow()`、`volatileRange`（`:229`—`:248`）；`Options` 带 `priority` 与 `modelRetention`（`.whileInUse`／`.lingering`／`.processLifetime`，`:451`—`:472`），长时间会话要在这里表态模型留不留。
- `SpeechTranscriber.isAvailable`（`:408`）、`supportedLocales`／`installedLocales`（均为 `get async`，`:411`、`:415`）、`supportedLocale(equivalentTo:)`（`:414`）；`ReportingOption`：`volatileResults`／`alternativeTranscriptions`／`fastResults`（`:377`）；`TranscriptionOption.etiquetteReplacements`（`:365`）；`ResultAttributeOption`：`audioTimeRange`／`transcriptionConfidence`（`:393`）；预设含 `progressiveTranscription` 与 `timeIndexedProgressiveTranscription`（`:350`—`:354`）。`Result` 的 `isFinal` 来自 `SpeechModuleResult` 扩展（`:333`）。
- `DictationTranscriber` 多出 `punctuation`／`emoji`、`frequentFinalization` 与 `ContentHint.shortForm`／`farField`／`atypicalSpeech`（`:91`—`:135`），有声学场景提示；转写长语音优先看它，术语转写优先看 `SpeechTranscriber` 的 `alternativeTranscriptions`。
- `AssetInventory`：`status(forModules:) async -> Status`（`.unsupported`／`.downloading`／`.supported`／`.installed`，`:44`—`:56`）、`assetInstallationRequest(supporting:)` → `AssetInstallationRequest.downloadAndInstall()` 与 `progress`（`:57`、`:509`）、`reserve(locale:)`／`release(reservedLocale:)` 与 `maximumReservedLocales`（`:34`—`:43`）。**SDK 没有任何字节数或体积属性**，资产多大必须实测。
- 连续音频：`AnalyzerInput.init(buffer:)`（`:14`）喂进 `SpeechAnalyzer.analyzeSequence`；结果是一条带 volatile 尾部的 `AsyncSequence`，`volatileRangeChangedHandler` 说明哪一段还在改（`:230`、`:249`）。macOS 27 新给 `CaptureInputSequenceProvider.providerWithSession(from:compatibleWith:priority:)`，直接产出麦克风的 `analyzerInputs`（`:719`—`:734`），以及 `AnalyzerInputConverter`（`:518`）做格式转换、`SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith:)`（`:254`）选格式；不想碰 `AVCaptureSession` 时仍可自行 `AVAudioEngine`。
- `SpeechDetector`（`:267`）是独立 `SpeechModule`，`DetectionOptions(sensitivityLevel:)`（`low`／`medium`／`high`），`Result.speechDetected`（`:303`）——想要「停顿即断句」就用它，而不是拿计时器猜。
- 明确的错误码：`SFSpeechError.Code` 扩了 `noModel`、`assetLocaleNotAllocated`、`tooManyAssetLocalesAllocated`、`cannotAllocateUnsupportedLocale`、`audioDisordered`、`unexpectedAudioFormat`、`incompatibleAudioFormats`、`insufficientResources`（`:683`—`:715`）。这些正好可以分成「没装模型」「locale 超限」「音频格式不对」三类不同提示。
- `AnalysisContext.contextualStrings`（`:484`）可把生词本里的词喂给识别器做偏置。

**离线与语言**：新版接口里没有服务器或网络开关，模型是 `AssetInventory` 的本机资产，所以资产已装时无网络可用、未装时 `downloadAndInstall()` 本身需要网络。SDK 只在运行时给出 `supportedLocales`／`installedLocales` 列表，**不静态列举支持哪些语言**，也不给延迟数字。

## 用户流程

1. 用户按快捷键开始会话（再按一次停止）。首次进入要过两道系统授权：麦克风与语音识别。
2. 选 locale：从 `SpeechTranscriber.supportedLocales` 里选与当前目标映射所需源语言最接近的（`supportedLocale(equivalentTo:)`）。
3. 查资产：`AssetInventory.status(forModules: [transcriber])`。非 `.installed` 就 `assetInstallationRequest(supporting:)` → `downloadAndInstall()`，用 `progress` 显示进度并允许取消；`.unsupported` 直接按「这台机器不支持该语言」呈现，不要假装在听。
4. `SpeechAnalyzer(modules: [transcriber], options:)`，用 `CaptureInputSequenceProvider`（或 `AVAudioEngine`）把麦克风转成 `AnalyzerInput`，`analyzeSequence` 常驻运行。
5. 结果流里 volatile 段显示为「正在听」，final 段追加成输入文本；何时触发翻译见下面的决策点。
6. 停止时 `finalizeAndFinishThroughEndOfInput()`，等最后一段 final 落地，再进入现有 `model.process(to:)` 与学习请求。

## 失败在哪一步可见

| 失败 | 呈现 |
|---|---|
| 麦克风未授权 | 提示 + 「打开麦克风设置」+ 手动输入；不建会话 |
| 语音识别未授权／缺 `NSSpeechRecognitionUsageDescription` | 提示；缺 key 会直接崩溃（`SFSpeechRecognizer.h:108`），所以 key 必须先进 `Info.plist` |
| 无模型／`.unsupported` | 「该语言不支持」提示 + 手动输入，不进入「正在听」 |
| `downloadAndInstall()` 失败 | 提示 + 重试；已下载部分不清空的说法 SDK 未承诺，按重试处理 |
| 一直没检测到语音 | 不是失败：保持「正在听」，给显式停止 |
| 识别器报错 | 按 `SFSpeechError.Code` 分类提示 + 手动输入，不静默丢段 |

## 接入与新增 seam

- `SpeechInput`：一条 `AsyncSequence<SpeechEvent>`，元素是 `.volatile(String)`／`.final(String)`／`.failed(Error)`。测试注入假序列，不需要麦克风、不需要真模型，也不需要真资产。
- `SpeechAssets`：`() async -> AssetState`（`.installed`／`.downloadable`／`.unsupported`）+ 一个可注入的下载函数，测试不碰 `AssetInventory`。
- 文本仍然只从 `model.input` 进入现成路径；会话本身不写回、不产生 `Selection`。面板需要新增「听写中」这一可见状态（与 `.translating` 并列），否则用户无法区分「在听」和「卡住」。

## 决策（要人定，不是排期）

- 一次会话等于一次翻译，还是逐 final 段多次翻译？前者把几句话合成一个输入、上下文更好；后者实时但会连续打断阅读与学习。
- 边说边翻，还是等停顿（`SpeechDetector.speechDetected == false`）再翻？这决定请求频率与译文抖动，也决定面板是一直更新还是分段落定。
- 是否保留音频缓冲？保留能重放与纠正，不保留隐私最干净；SDK 不要求保留，这是产品选择。
- 语音模型与语言模型对源语言判断不一致时以谁为准？现有目标映射（BDR-0003）依赖检测到的源语言，两个模型各说一套时必须有优先级。
- 界面语言、母语与语音 locale 是不是同一件事？语音 locale 是「机器在听什么」，与界面语言无关，设置里可能需要单独一项。
- 语音产生的文本进历史吗？现有历史按操作记录来源，语音会话没有「来源 App」。

## 权限与隐私

| 能力 | usage-description | 用户可见授权 | 沙盒 |
|---|---|---|---|
| 语音识别 `SpeechAnalyzer`／`SpeechTranscriber` | `NSSpeechRecognitionUsageDescription`（`SFSpeechRecognizer.h:105`、`:108`，缺 key 调用即崩溃） | 旧接口由 `+requestAuthorization:` 弹（`SFSpeechRecognizer.h:115`）；**新版 Swift 接口没有授权 API**，何时弹提示须实测 | 沙盒下需语音识别 entitlement，SDK 不含其名称 |
| 麦克风 `AVCaptureDevice`／`AVAudioEngine` | `NSMicrophoneUsageDescription`（SDK 头文件没有列出该键，属系统要求） | `AVCaptureDevice.requestAccessForMediaType:`（`AVCaptureDevice.h:2174`—`:2190`） | 沙盒下需麦克风 entitlement，SDK 不含其名称，须查 Apple 文档 |

`spec/README.md` 的范围边界写明本应用「本机签名自用，不启用 App Sandbox」，所以上述授权都直接走 TCC。沙盒下两者都不是「做不到」，而是各自还多一道 entitlement；本机 SDK 不包含 entitlement 名称表，无法在此证实，因此那一列只标出差异、不写具体键名。麦克风音频与识别文本都不进诊断日志；这是现有「仅在用户触发时读取」隐私约定的自然延伸。

## 必须实测（SDK 不回答的部分）

- `SpeechTranscriber`／`DictationTranscriber` 在本机实际支持哪些 locale、`installedLocales` 初值是什么。
- 语音模型的**真实资产体积**与下载时长：SDK 只有 `Progress`，没有字节数属性。
- 端到端延迟：从说话到 volatile 首次出现、从停顿到 final 落定的时间。
- 准确率／词错误率，以及中英混说时的表现。
- macOS 27 首次使用新版 `SpeechAnalyzer` 时到底弹不弹 `NSSpeechRecognitionUsageDescription` 提示、由谁触发。
- 沙盒下语音识别与麦克风各自需要的 entitlement 名称。

以上都是「必须实测」，不是「预期如此」；在实测之前不得写进 `spec/`，也不得在界面上承诺。
