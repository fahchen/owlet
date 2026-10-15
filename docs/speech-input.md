[English](speech-input.md) · [简体中文](speech-input.zh-CN.md)

# Continuous Speech Input Proposal

Status: design proposal, not implemented, **out of scope for this round**. This document only covers "how speech becomes input". It does not change the `SelectionBridge` read path, the floating panel, the translation contract or the learning contract; no user-visible strings enter `strings/translations.json`. Screen region input has been split out into the [screen region OCR input proposal](screen-region-input.md).

## Why read the SDK first

The system's capabilities set the boundaries of this source, so every API fact below was read from the local Xcode 27.0 / macOS 27.0.1 SDK, not from memory. The SDK root is written as `$SDK`:

`/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk`

- `$SDK/System/Library/Frameworks/Speech.framework/Modules/Speech.swiftmodule/arm64e-apple-macos.swiftinterface` (hereafter `Speech.swiftinterface`)
- `$SDK/System/Library/Frameworks/AVFoundation.framework/Headers/` (`AVCaptureDevice.h`)

The app's minimum is macOS 26 (scope boundary in `spec/README.md`). The new Speech API starts exactly at macOS 26; the exceptions are `CaptureInputSequenceProvider` and `AnalyzerInputConverter`, which only exist in macOS 27. On the minimum version you either produce `AnalyzerInput` yourself with `AVAudioEngine` (macOS 26's `init(buffer:)`) or add `if #available(macOS 27, *)`.

## Two preconditions

1. **There is no selection to write back to.** Write-back of a `Selection` depends on `kAXSelectedTextRangeAttribute` and an editable role; speech yields text with no AX source, so `PanelController.selection` must stay `nil`. As a result the panel offers only "Copy Result", not "Replace".
2. **Failures are visible under the existing rules.** A failed read (no permission, no text, no model) must land on a prompt of the same shape as `.permission` / `.unreadable`, with a manual input entry; it must not end silently and must not send empty input to the model (the three existing branches of `PanelController.accept` implement exactly this rule).

## What STT on macOS looks like today

The SDK has **two generations** of API, both still present:

- **New (macOS 26+, pure Swift, no network path in the API)**: `SpeechAnalyzer` is an `actor` (`Speech.swiftinterface:228`) with an `async` API; its modules are `SpeechTranscriber` (`:346`) and `DictationTranscriber` (`:70`, unavailable on tvOS). Models are on-device assets managed by `AssetInventory` (`:33`).
- **Old**: `SFSpeechRecognizer` (`Headers/SFSpeechRecognizer.h:78`). **It is not marked deprecated in this SDK**: the only `API_DEPRECATED` in the Speech headers are two methods at `SFSpeechLanguageModel.h:58` and `:62`. Its documentation states plainly that "some languages require a network connection" (`SFSpeechRecognizer.h:54`, `:83`), and `requiresOnDeviceRecognition` is honoured only when `supportsOnDeviceRecognition` is true; when false, "recognition requires a network" (`Headers/SFSpeechRecognitionRequest.h:63`). Continuous audio uses `SFSpeechAudioBufferRecognitionRequest`: keep appending with `appendAudioPCMBuffer:` and stop only at `endAudio` (from `SFSpeechRecognitionRequest.h:148`).

The choice leans toward the new API: it is `async` / `AsyncSequence`, consistent with this project's Swift 6 strict concurrency, and its asset status and `progress` make it possible to state clearly that "the model is not installed yet"; the old API's network behaviour would make "is there a network" part of the product state.

Key symbols in the new API:

- `SpeechAnalyzer.init(modules:options:)`, `start(inputSequence:)`, `analyzeSequence(_:) -> CMTime?`, `finalize(through:)`, `finalizeAndFinishThroughEndOfInput()`, `cancelAndFinishNow()`, `volatileRange` (`:229` to `:248`). `Options` carries `priority` and `modelRetention` (`.whileInUse` / `.lingering` / `.processLifetime`, `:451` to `:472`); a long session has to decide here whether the model stays loaded.
- `SpeechTranscriber.isAvailable` (`:408`), `supportedLocales` / `installedLocales` (both `get async`, `:411`, `:415`), `supportedLocale(equivalentTo:)` (`:414`); `ReportingOption`: `volatileResults` / `alternativeTranscriptions` / `fastResults` (`:377`); `TranscriptionOption.etiquetteReplacements` (`:365`); `ResultAttributeOption`: `audioTimeRange` / `transcriptionConfidence` (`:393`); presets include `progressiveTranscription` and `timeIndexedProgressiveTranscription` (`:350` to `:354`). `Result`'s `isFinal` comes from the `SpeechModuleResult` extension (`:333`).
- `DictationTranscriber` adds `punctuation` / `emoji`, `frequentFinalization` and `ContentHint.shortForm` / `farField` / `atypicalSpeech` (`:91` to `:135`), i.e. acoustic scene hints. For transcribing long speech look at it first; for transcribing terminology look first at `SpeechTranscriber`'s `alternativeTranscriptions`.
- `AssetInventory`: `status(forModules:) async -> Status` (`.unsupported` / `.downloading` / `.supported` / `.installed`, `:44` to `:56`), `assetInstallationRequest(supporting:)` → `AssetInstallationRequest.downloadAndInstall()` and `progress` (`:57`, `:509`), `reserve(locale:)` / `release(reservedLocale:)` and `maximumReservedLocales` (`:34` to `:43`). **The SDK has no byte count or size property**, so asset size must be measured.
- Continuous audio: `AnalyzerInput.init(buffer:)` (`:14`) feeds `SpeechAnalyzer.analyzeSequence`; results are an `AsyncSequence` with a volatile tail, and `volatileRangeChangedHandler` says which part is still changing (`:230`, `:249`). macOS 27 adds `CaptureInputSequenceProvider.providerWithSession(from:compatibleWith:priority:)`, which produces microphone `analyzerInputs` directly (`:719` to `:734`), plus `AnalyzerInputConverter` (`:518`) for format conversion and `SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith:)` (`:254`) for choosing a format; if you would rather not touch `AVCaptureSession`, you can still use `AVAudioEngine` yourself.
- `SpeechDetector` (`:267`) is a standalone `SpeechModule` with `DetectionOptions(sensitivityLevel:)` (`low` / `medium` / `high`) and `Result.speechDetected` (`:303`). For "break the sentence on a pause", use it instead of guessing with a timer.
- Explicit error codes: `SFSpeechError.Code` adds `noModel`, `assetLocaleNotAllocated`, `tooManyAssetLocalesAllocated`, `cannotAllocateUnsupportedLocale`, `audioDisordered`, `unexpectedAudioFormat`, `incompatibleAudioFormats`, `insufficientResources` (`:683` to `:715`). These map neatly to three different prompts: "model not installed", "locale limit exceeded" and "wrong audio format".
- `AnalysisContext.contextualStrings` (`:484`) can feed words from the vocabulary book to the recognizer as bias.

**Offline and languages**: the new API has no server or network switch, and models are on-device `AssetInventory` assets, so with assets installed no network is needed, while `downloadAndInstall()` itself needs the network when they are not. The SDK only provides the `supportedLocales` / `installedLocales` lists at runtime; it **does not statically list supported languages** and gives no latency figures.

## User flow

1. The user presses a shortcut to start a session (press again to stop). The first time requires two system authorizations: microphone and speech recognition.
2. Choose a locale: from `SpeechTranscriber.supportedLocales`, pick the one closest to the source language the current target mapping needs (`supportedLocale(equivalentTo:)`).
3. Check assets: `AssetInventory.status(forModules: [transcriber])`. If not `.installed`, call `assetInstallationRequest(supporting:)` → `downloadAndInstall()`, show progress with `progress` and allow cancelling; `.unsupported` is shown directly as "this Mac does not support this language", without pretending to listen.
4. `SpeechAnalyzer(modules: [transcriber], options:)`; use `CaptureInputSequenceProvider` (or `AVAudioEngine`) to turn the microphone into `AnalyzerInput`, with `analyzeSequence` running continuously.
5. In the result stream, volatile segments are shown as "listening" and final segments are appended to the input text; when to trigger translation is one of the decision points below.
6. On stop, call `finalizeAndFinishThroughEndOfInput()`, wait for the last final segment to land, then enter the existing `model.process(to:)` and learning request.

## Where each failure is visible

| Failure | Presentation |
|---|---|
| Microphone not authorized | Prompt + "Open microphone settings" + manual input; no session is created |
| Speech recognition not authorized / `NSSpeechRecognitionUsageDescription` missing | Prompt; a missing key crashes immediately (`SFSpeechRecognizer.h:108`), so the key must be in `Info.plist` first |
| No model / `.unsupported` | "This language is not supported" prompt + manual input; do not enter "listening" |
| `downloadAndInstall()` fails | Prompt + retry; the SDK does not promise that already-downloaded parts are kept, so treat it as a retry |
| No speech detected for a long time | Not a failure: stay in "listening" and offer an explicit stop |
| Recognizer error | Prompt classified by `SFSpeechError.Code` + manual input; never silently drop a segment |

## Integration and new seams

- `SpeechInput`: an `AsyncSequence<SpeechEvent>` whose elements are `.volatile(String)` / `.final(String)` / `.failed(Error)`. Tests inject a fake sequence and need no microphone, no real model and no real assets.
- `SpeechAssets`: `() async -> AssetState` (`.installed` / `.downloadable` / `.unsupported`) plus an injectable download function, so tests never touch `AssetInventory`.
- Text still enters the existing path only through `model.input`; the session itself does not write back and produces no `Selection`. The panel needs a new visible "dictating" state (alongside `.translating`), otherwise the user cannot tell "listening" from "stuck".

## Decisions (for a person to make, not scheduling)

- Is one session one translation, or is each final segment translated separately? The former merges several sentences into one input with better context; the latter is real-time but keeps interrupting reading and learning.
- Translate while speaking, or wait for a pause (`SpeechDetector.speechDetected == false`)? This sets the request frequency and translation jitter, and whether the panel keeps updating or settles segment by segment.
- Keep the audio buffer? Keeping it allows replay and correction; not keeping it is the cleanest for privacy. The SDK does not require keeping it; this is a product choice.
- When the speech model and the language model disagree on the source language, which one wins? The existing target mapping (BDR-0003) depends on the detected source language, so when the two models disagree there must be a priority.
- Are the UI language, native language and speech locale the same thing? The speech locale is "what the machine is listening for" and is unrelated to the UI language; settings may need a separate item for it.
- Does text produced by speech go into history? Existing history records the source per operation, and a speech session has no "source app".

## Permissions and privacy

| Capability | usage-description | User-visible authorization | Sandbox |
|---|---|---|---|
| Speech recognition `SpeechAnalyzer` / `SpeechTranscriber` | `NSSpeechRecognitionUsageDescription` (`SFSpeechRecognizer.h:105`, `:108`; calling without the key crashes) | The old API prompts via `+requestAuthorization:` (`SFSpeechRecognizer.h:115`); **the new Swift API has no authorization API**, so when the prompt appears must be measured | Under the sandbox a speech recognition entitlement is needed, and the SDK does not contain its name |
| Microphone `AVCaptureDevice` / `AVAudioEngine` | `NSMicrophoneUsageDescription` (the SDK headers do not list this key; it is a system requirement) | `AVCaptureDevice.requestAccessForMediaType:` (`AVCaptureDevice.h:2174` to `:2190`) | Under the sandbox a microphone entitlement is needed; the SDK does not contain its name, check Apple's documentation |

The scope boundary in `spec/README.md` states that this app is "locally signed for personal use, without App Sandbox", so both authorizations go straight through TCC. Under the sandbox neither is "impossible", each just needs one more entitlement; the local SDK has no table of entitlement names, so this cannot be confirmed here, and that column only marks the difference without naming keys. Neither microphone audio nor recognised text enters diagnostic logs; this is a natural extension of the existing "read only when the user triggers it" privacy rule.

## Must be measured (what the SDK does not answer)

- Which locales `SpeechTranscriber` / `DictationTranscriber` actually support on this machine, and the initial value of `installedLocales`.
- The **real asset size** and download time of the speech model: the SDK only has `Progress`, with no byte count property.
- End-to-end latency: from speaking to the first volatile result, and from a pause to the final result settling.
- Accuracy / word error rate, and behaviour with mixed Chinese and English speech.
- Whether first use of the new `SpeechAnalyzer` on macOS 27 shows the `NSSpeechRecognitionUsageDescription` prompt at all, and what triggers it.
- The entitlement names needed under the sandbox for speech recognition and the microphone.

All of the above are "must be measured", not "expected to be so"; until measured they must not be written into `spec/` or promised in the UI.
