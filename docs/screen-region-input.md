[English](screen-region-input.md) · [简体中文](screen-region-input.zh-CN.md)

# Screen Region OCR Input Proposal

Status: implemented (2026-10-23). [BDR-0019](../spec/processing/decisions/BDR-0019-screen-region-input.md) settles the open items and overrides two decisions below: the region is drawn in the system's `screencapture -i` instead of an overlay of our own, and the screenshot is kept — shown in the panel and stored with the history record. The rest of this document is the design record.

## Review outcome (2026-10-23)

- **Thumbnail, not a large picture.** About 38pt high, with corners concentric with what holds it (the outer radius less the inset: a capsule in the bar, 10pt in the open panel). In the compact bar, and when there is no text yet, it leads the source on the **left**; when the first piece of the translation arrives and the panel opens, the same thumbnail moves to the **right** with the opening spring (`matchedGeometryEffect`; Reduce Motion switches without the move). In Source / Result Sections it sits at the source's top trailing corner, above the rule, and the source text wraps around it (TextKit exclusion paths, so this one field is an `NSTextView`); in Sentence by Sentence at the top right of the pairs. Hovering shows the zoom-in pointer; a click zooms it in place to the full width with the source hidden, and a second click shrinks it back, both animated. No popover.
- **No text in the screenshot:** the source bar becomes the empty field (BDR-0018) with the thumbnail on the left, the placeholder "No text was found in the screenshot. Type what it says, then press ⌘↩", and a Select Another Region button.
- **History:** the list row's time line spans the row and the thumbnail leads the result and source lines; the detail shows the screenshot directly, with a hairline `.separator` border and no background, text or button: the zoom pointer shows on hover and a click opens it in Quick Look.

## Why read the SDK first

The system's capabilities set the boundaries of this source, so every API fact below was read from the local Xcode 27.0 / macOS 27.0.1 SDK, not from memory. The SDK root is written as `$SDK`:

`/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk`

- `$SDK/System/Library/Frameworks/Vision.framework/Modules/Vision.swiftmodule/arm64e-apple-macos.swiftinterface` (hereafter `Vision.swiftinterface`)
- `$SDK/System/Library/Frameworks/ScreenCaptureKit.framework/Headers/`, `$SDK/System/Library/Frameworks/CoreGraphics.framework/Headers/`

The app's minimum is macOS 26 (scope boundary in `spec/README.md`). The APIs used fall within 15.2 to 26: `SCScreenshotManager.captureImage(in:)` is 15.2+, `RecognizeTextRequest` is 15+, and `RecognizedTextObservation.transcript` only arrives in 26.

## Two preconditions

1. **There is no selection to write back to.** Write-back of a `Selection` depends on `kAXSelectedTextRangeAttribute` and an editable role; OCR yields an image with no AX source, so `PanelController.selection` must stay `nil`. As a result the panel offers only "Copy Result", not "Replace". This is correct, not a gap: pasting a translation back into the web-page image the user just boxed makes no sense.
2. **Failures are visible under the existing rules.** A failed read (no permission, no text, no model) must land on a prompt of the same shape as `.permission` / `.unreadable`, with a manual input entry; it must not end silently and must not send empty input to the model (the three existing branches of `PanelController.accept` implement exactly this rule).

## SDK facts

**One-off region capture has a direct API; no stream is needed.** `SCScreenshotManager` (`Headers/SCScreenshotManager.h:134`) provides:

- `+captureImageInRect:completionHandler:` → Swift `SCScreenshotManager.captureImage(in:)`, macOS 15.2+ (`SCScreenshotManager.h:161`). Its comment says the rect is "in screen space, in points, display-independent, multi-display aware", which is exactly "drag a rectangle, capture once".
- From macOS 26 there is also `+captureScreenshotWithRect:configuration:completionHandler:` → `captureScreenshot(rect:configuration:)` (`SCScreenshotManager.h:179`), paired with `SCScreenshotConfiguration` (`width` / `height` / `sourceRect` / `destinationRect` / `showsCursor` / `ignoreShadows` / `dynamicRange`, `SCScreenshotManager.h:46`) and `SCScreenshotOutput` (`sdrImage` / `hdrImage`, `SCScreenshotManager.h:118`). The former is enough for region capture; `SCScreenshotConfiguration` only matters when explicit dimensions or HDR are needed.

**`SCShareableContent` / `SCStream` are not needed.** That stack (`SCShareableContent.getShareableContent...`, `SCContentFilter`, `SCStream` + `SCStreamOutput`, `SCStreamConfiguration.sourceRect`) is designed for "pick a window / display first, then keep producing frames"; see `SCShareableContent.h:152`, `SCStream.h:507`, `SCStream.h:289`. Capturing a rectangle with `captureImage(in:)` involves no filter, no stream and no `SCStreamOutput` callback, which removes one layer of lifecycle and error surface.

**The picker has no region mode.** `SCContentSharingPickerMode` has only `SingleWindow` / `MultipleWindows` / `SingleApplication` / `MultipleApplications` / `SingleDisplay` (`Headers/SCContentSharingPicker.h:19`). So the rectangle must be drawn by the app itself; there is no system "select a region" picker to rely on.

**The old path is obsolete.** `CGWindowListCreateImage` and `CGWindowListCreateImageFromArray` carry `SCREEN_CAPTURE_OBSOLETE(10.5,14.0,15.0)` (`CGWindow.h:271`, `CGWindow.h:280`), and the macro expands to `availability(macos, introduced, deprecated, obsoleted, message="Please use ScreenCaptureKit instead.")` (`CGWindow.h:223`): deprecated from macOS 14 and obsoleted from macOS 15. Do not use them.

**OCR uses the new Swift Vision API, not `VNRecognizeTextRequest`.** From `Vision.swiftinterface`:

- `RecognizeTextRequest` (macOS 15+, `:2591`), `Result = [RecognizedTextObservation]`; `init(_ revision: RecognizeTextRequest.Revision? = nil)` (`:2604`).
- In this SDK's public enum, `RecognizeTextRequest.Revision` has only `case revision3` (`:2593`); `supportedRevisions` is a static property (`:2635`).
- `RecognitionLevel`: `case accurate` / `case fast` (`:2605`). Settable: `recognitionLanguages: [Locale.Language]`, `automaticallyDetectsLanguage: Bool`, `usesLanguageCorrection: Bool`, `customWords: [String]`, `minimumTextHeightFraction: Float`, `regionOfInterest: NormalizedRect` (`:2621` to `:2633`). `supportedRecognitionLanguages: [Locale.Language] { get }` (`:2627`) is an instance property, so which languages this machine supports is only known at runtime.
- `ImageRequestHandler` (`:2179`) accepts `URL` / `CGImage` / `CIImage` / `CVPixelBuffer` / `CMSampleBuffer` / `Data` (`:2180` to `:2185`); `perform(_:) async throws -> T.Result` (`:2186`). The capture yields a `CGImage`, so `ImageRequestHandler(image)` works directly with nothing written to disk.
- `RecognizedTextObservation` has `transcript: String` (macOS 26+, `:1450`), `topCandidates(_:) -> [RecognizedText]` (`:1476`), and `boundingRegion` / the four corner points / `confidence` (`:1462` to `:1470`); `RecognizedText.string` / `confidence` (`:1862`, `:1865`). Use the observations' coordinates to build reading order; do not assume the array is already in line order.

**Vision runs on device.** The request exposes `supportedComputeStageDevices` and `setComputeDevice(_:for:)` (`:2630`, `:2639`), meaning inference runs on local CoreML devices; the API has no network or server parameter. That does not mean recognition is always accurate; see the last section for accuracy.

## User flow

1. The user presses a shortcut (a second shortcut, or a "source: selected text / screen region" option on the existing shortcut in settings).
2. First call `CGPreflightScreenCaptureAccess()` (`CGWindow.h:300`). If false, call `CGRequestScreenCaptureAccess()` (`:308`) once to trigger the system prompt; if still false, show a prompt whose action button opens "System Settings › Privacy & Security › Screen Recording", and offer manual input. Do not read the screen or send a model request.
3. A full-screen overlay window draws the selection box: drag out a rectangle, adjust it, Esc cancels, releasing confirms. The overlay does not reuse the floating panel (`FloatingPanel` has panel semantics, not a full-screen mask).
4. Call `captureImage(in:)` with screen-point coordinates to get a `CGImage`.
5. Run `RecognizeTextRequest` through `ImageRequestHandler` and join `[RecognizedTextObservation]` into one text by coordinates.
6. The text enters the existing path: set `model.input`, then `PanelController.processCurrentText()`; `selection` stays `nil`.

## Settled in review

### Region selection: drawn only by the app

**Do not integrate `SCContentSharingPicker`.** It has no region mode (`SCContentSharingPickerMode` only covers windows / applications / displays, `SCContentSharingPicker.h:19`), and keeping it would only add a two-step "pick a window, then box a region" interaction. Letting the user drag a rectangle is enough: one interaction, one capture, any rectangle on screen. So the only region source is the overlay window the app draws itself.

### OCR language: automatic detection

The request enables `automaticallyDetectsLanguage` (`Vision.swiftinterface:2621` to `:2633`) and does not pin `recognitionLanguages` up front: a user boxing a passage of Japanese should not first have to declare the language in settings.

Detection is internal SDK behaviour and the API exposes only a `Bool`; **there is no language confidence to read**, so the app cannot tell when detection is wrong; errors only show up as "the translation is wrong". The existing honest-failure rule applies: the user sees the wrong result and edits the source or reselects to retry; the app does not guess and does not silently switch languages.

Pinning the language (specifying `recognitionLanguages` in settings) is kept as a **later optional feature** and is not part of this round: its value only appears after automatic detection fails, and there is no data yet on which regions get misdetected. Whether it is worth doing, and at which layer, depends on the measurements in the last section.

### Reading order: model as fallback, no column geometry in the app

The SDK gives only coordinates and `transcript` (`:1450`, `:1462` to `:1470`), not reading order. The app does only the most basic coordinate-based joining (top to bottom) and **does not detect columns or guess paragraph structure**: columns are screen layout, not a fact of the language, and hard-coded geometry rules will break on the next layout change. The joined text goes to the model, which orders it by punctuation and meaning.

The cost must be stated: the model receives text without coordinates, so a wrong column order is not exposed on the spot; it shows up in the translation as "the order is wrong". The panel must therefore always show this OCR run's source text and keep it editable (`model.input` is exactly that place), so the user can check it against the translation; the app does not judge whether the order is right on the user's behalf.

### Captures are not kept

The capture exists only in memory: `captureImage(in:)` → `CGImage` → `ImageRequestHandler` → discarded after recognition; it is not written to disk, history or debug logs. There are no files to clean up and no pixels to leak. The cost is that the user cannot "view the original image" afterwards to check recognition, so "retry" means selecting the region again, not re-running the previous image.

### If the selected model can read images: an optional path

[`BDR-0013` §9](../spec/settings/decisions/BDR-0013-local-agent-provider.md) already records "carrying images in the model layer" as a planned extension point (`ModelTurn` will later gain content parts: text today, images later, each backend mapping them its own way). Once that extension point lands, when the configured provider declares it accepts images, local OCR can be skipped: the region image goes straight to the model, which both reads and translates the text. This path requires the model layer to carry images, and **only appears in the UI when the selected provider actually accepts images**; otherwise the option is not shown and no image is sent.

The difference between the two paths must be stated: on the local OCR path the source text comes from Vision and can be edited character by character in the panel; on the model-reads-image path the source text is the `source` the model itself returns (the existing contract already requires it to be returned and checked by concatenation; see the [LLM response contract](../spec/llm/contract.md)), so the user edits what the model recognised, not what was on screen. Both paths keep the source "visible and editable", and neither keeps the image.

Unverified; the design does not assume:

- Which of the locally supported providers accept image input today (OpenAI-compatible endpoints, DeepSeek, Claude Code, Codex CLI, each separately).
- Whether the local agent CLIs have a channel for images: `BDR-0013` §9 only says "added later", not how.
- How much model image reading and local OCR differ in accuracy on small Chinese / Japanese text.

Until measured, this path is only "an option when the provider declares support"; it is not written into the product definition and is not the default. Whether a provider supports it follows the existing vendor capability flags (`ServicePreset`, reaching the request via `ServiceConfig`; this is how "DeepSeek only supports `json_object`" is expressed), with a new "accepts images" capability bit; today that bit can only be hand-written per preset, with values from measurement.

## Where each failure is visible

| Failure | Presentation |
|---|---|
| No Screen Recording permission | Prompt + "Open Screen Recording settings" + manual input; the overlay is not started |
| User presses Esc | Close directly with no prompt (same shape as cancellation in `stop()`) |
| Region too small / all black / capture error | Prompt + manual input |
| OCR returns nothing | Prompt shaped like `.unreadable` + manual input; no model request |

Both capture and OCR can return "an image but no text". That is the same user experience as "no selection was read"; do not invent a new silent state.

## Integration and new seams

- `RegionCapture`: `(CGRect) async throws -> CGImage`. Tests inject a fixed `CGImage` and never touch the screen.
- `TextRecognizer`: `(CGImage) async throws -> String`. Tests inject a fixed string and never touch Vision. This round's implementation only enables `automaticallyDetectsLanguage` and does not read `recognitionLanguages`; `supportedRecognitionLanguages` (`:2627`) waits until pinning the language becomes an option.
- The overlay window only produces a `CGRect` and reads no pixels; it is the one layer that must be verified by hand on real hardware.
- `PanelController` gains an entry point shaped like `accept(.success)` (import the text, clear `selection`, `processCurrentText()`), without changing the existing read branches.
- If the model-reads-image path lands, its changes sit in the model layer's capability flags and in `ModelTurn` content parts; it adds no second read branch.

## Permissions and privacy

| Capability | usage-description | User-visible authorization | Sandbox |
|---|---|---|---|
| ScreenCaptureKit `SCScreenshotManager.captureImage(in:)` | **`NSScreenCaptureUsageDescription` does not exist in the local SDK** (full-text search under `$SDK/System/Library/Frameworks/`, no match) | TCC "Screen Recording", triggered by `CGRequestScreenCaptureAccess()`; a process that was already denied is not prompted again and must be enabled in System Settings (`CGWindow.h:303` to `:305`) | Under the sandbox a screen-recording entitlement is needed, and the SDK does not contain its name; this app is not sandboxed, so it goes straight through TCC |

The scope boundary in `spec/README.md` states that this app is "locally signed for personal use, without App Sandbox", so authorization goes straight through TCC. Under the sandbox it is not "impossible", just one more entitlement; the local SDK has no table of entitlement names, so this cannot be confirmed here, and that column only marks the difference without naming a key. Neither screen pixels nor recognised text enter diagnostic logs; this is a natural extension of the existing "read only when the user triggers it" privacy rule.

## Still open

- Shortcut shape: a second shortcut, or a "source: selected text / screen region" option on the existing shortcut.
- Granularity of the "model reads image" option (a global switch or remembered per provider), and whether it sits alongside local OCR or runs before/after it.
- When and where pinning the language lands (direction settled: a later optional feature).

## Must be measured (what the SDK does not answer)

- Vision's real accuracy and error patterns on Chinese, Japanese, vertical text, small font sizes and scaled captures.
- What automatic language detection actually picks on regions such as "mixed Chinese and English" or "only a few lines of English"; the API gives only a `Bool`, with no confidence to read.
- The actual effect and ordering error rate of "join top to bottom by coordinates + model fallback" on multi-column layouts.
- Which locally supported providers accept image input today, and the image channel of the local agent CLIs.
- The accuracy gap between model image reading and local OCR on small Chinese / Japanese text.
- The exact wording of the Screen Recording TCC prompt on macOS 27 and the group name in System Settings (the SDK only uses the old name "Screen Recording").
- The entitlement name needed for screen recording under the sandbox.

All of the above are "must be measured", not "expected to be so"; until measured they must not be written into `spec/` or promised in the UI.
