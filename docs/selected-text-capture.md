[English](selected-text-capture.md) · [简体中文](selected-text-capture.zh-CN.md)

# macOS Selected Text Capture

Status: the AX main path is implemented (`96f8f2e`, `ef8682e`, `671ebd3`); compatibility on real apps is still to be verified. Applies to Owlet's native app on macOS 26+.

## Goals and boundaries

When the user triggers translate, polish, or translate and replace with a recorded shortcut, the selected text in the external app is read before the floating panel takes focus. Without valid source text, no model request is sent; instead a permission settings entry or a manual input entry is offered.

This design focuses on the Accessibility (AX) main read path. It adds no dependencies and does not cover OCR, continuous selection monitoring or the replacement algorithm. Shortcuts keep using the existing recording setting; no default combination is specified.

The read order is AX first, then simulated copy: when no selection is found on the focused element, its ancestors, its subtree or the window, step 7 below synthesizes ⌘C to copy the selection and puts the clipboard back once the text is taken. In other words, the read path touches the clipboard only when AX comes up empty, while the write-back path always goes through the clipboard.

## Where it lives

- [SelectionBridge.swift](../Owlet/Selection/SelectionBridge.swift): `read(completion:)` reads following the flow below; the `LatestPendingSerialQueue` worker queue; an injectable AX attribute reader. Write-back and clipboard handling live in [SelectionWriteback.swift](../Owlet/Selection/SelectionWriteback.swift).
- [PanelController.swift](../Owlet/App/Panel/PanelController.swift): `processSelection` assigns the operation ID, receives the read result asynchronously and presents errors depending on whether the toolbar is expanded.
- Tests: [SelectionBridgeTests.swift](../OwletTests/Selection/SelectionBridgeTests.swift), [LatestPendingSerialQueueTests.swift](../OwletTests/Selection/LatestPendingSerialQueueTests.swift), [PanelControllerTests.swift](../OwletTests/App/Panel/PanelControllerTests.swift).

## Read flow

1. As soon as the shortcut fires, invalidate the old operation, cancel the old model request and assign an ID to this operation.
2. On the main thread, check `AXIsProcessTrusted()` and record `NSWorkspace.shared.frontmostApplication` and its PID. If not authorized, return `.permission`; if there is no frontmost app or the source is Owlet itself, return `.unreadable`.
3. On the dedicated serial worker queue, create `AXUIElementCreateApplication(pid)`; all further reads are confined to this app. Set the AX messaging timeout, then read `kAXFocusedUIElementAttribute`.
4. Check the returned object's type and read `kAXSubroleAttribute`. If it is `kAXSecureTextFieldSubrole`, return `.secure` immediately; text and selection contents must not be read. If a required attribute cannot be confirmed, treat it as a read failure.
5. Read the selection. First check the focused element's own `kAXSelectedTextAttribute`; Safari exposes web page selections only through `kAXSelectedTextMarkerRangeAttribute` plus `kAXStringForTextMarkerRangeParameterizedAttribute`, so the text marker range is tried on the same element as well. Only strings are accepted; emptiness is judged on a trimmed copy, while the original whitespace and line breaks are kept.
6. When the focused element has no selection, search outward: first walk up `kAXParentAttribute` at most 8 levels (web selections often sit on `AXWebArea`), then run a breadth-first search starting from the focused element's subtree and ending at its window, visiting at most 400 nodes (a PDF reader's text layer lives in child nodes). Every element gets the AX messaging timeout set before it is messaged, and all reads share one per-trigger budget; once the budget is spent, reads return nil and the search ends.
7. If nothing is found, copy the selection: save the clipboard, synthesize ⌘C, poll at most 20×20ms for a clipboard change, and put the clipboard back as soon as non-empty text is taken; if nothing new arrives, still return `.unreadable`. Password fields already returned `.secure` at step 4 and never reach this step.
8. The selection range (`SelectedRange`) is read only when panel placement needs to follow the selection: decode `kAXSelectedTextRangeAttribute` after CF type and AXValue type checks. A missing range only affects placement, not translation.
9. Back on the main thread, accept the result only if the operation has not expired, has not been cancelled and the frontmost app still has the original PID. On success, first store the `Selection` and import the input, then show the panel and start the corresponding model request.

A successful text read does not mean a successful write-back. Write-back does not compare the text and selection range captured earlier, and it goes **only** through paste: Accessibility writes "report success but change nothing" in these apps (the element has often gone stale once the panel takes focus), so that path was removed. The order is fixed:

1. Use the element's `AXRole` to decide whether the selection sits on editable text (`AXTextField` / `AXTextArea` / `AXComboBox`). When it is clearly none of these, return `.unwritable` without sending a single key: typing the translation into a terminal prompt or a read-only web page is not what the user wants. When the app does not report a role, treat it as editable, because "cannot ask" does not mean "cannot edit".
2. The panel first calls `orderOut` to give up the keyboard. The panel holds the keyboard while shown, and synthesized keys follow the keyboard, so it must step aside first; if write-back fails it comes back on screen, because that is when the user needs to copy the result.
3. Put the result on the clipboard, bring the owning app to the front, and wait 150ms for the keyboard to move over.
4. Synthesize one complete sequence at the HID level: ⌘ down, V down, V up, ⌘ up.
5. Wait 300ms for the target app to read the clipboard (only then is the user's original content put back), then keep polling the element's `AXValue` until 600ms in total have passed: if it differs from before the paste, the result is `.pasted`; if the element does not report its text, it is also `.pasted` (the paste went to wherever the app really has focus, and being unable to read it is no evidence of failure); only text that really did not change is `.refused`. When the result equals the source text it counts as `.pasted` directly: replacing a passage with itself cannot be observed and needs no change.

Only a missing Accessibility permission, an app that has quit, an app that cannot be brought forward, a selection that is clearly not editable, or text that really did not change count as not written back; the panel then stays on screen and offers "Copy Result". A successful copy or write-back closes the panel either way.

## Response time and concurrency

- Current parameters: a per-call AX messaging timeout of **150 ms** (`messagingTimeout`) and a total budget of **900 ms** from the trigger (`budget`). The budget exists so that the one read during which a browser builds its accessibility tree on demand can complete; it is an engineering value, not a system guarantee.
- The total budget covers queueing and all AX reads; each step checks whether it has expired before starting, so waits from several calls do not add up one by one.
- When the total budget is reached, the recovery entry is shown as `.unreadable`; a synchronous AX call already in flight may still return later. The total timeout only stops accepting results; it does not claim to have terminated the system call.
- The serial queue holds at most one running read and one latest pending operation; a new trigger replaces the old pending one, so repeated shortcuts do not build an unbounded queue.
- `PanelController`'s operation ID mechanism governs both reads and model requests. A new trigger, closing with Esc, or cancelling all invalidate the old ID; late results must not change the input, pop up the panel, request the model or restore the replace intent. The panel does not close when it loses keyboard focus, and losing focus does not invalidate the current operation; only Esc, an explicit close (done) or a click outside the panel closes it.
- UI state is updated only on the main thread. The worker queue owns the AX objects internally; the implementation follows Swift concurrency isolation rules and does not casually add `@unchecked Sendable` to pass objects across executors.

## Electron compatibility

Some Electron apps do not build their accessibility tree proactively; the app's AX object can be given `AXManualAccessibility = true` before reading the focused control.

This attribute is an app compatibility convention, not a public AX attribute every app supports. Failure to set it does not on its own mean the read failed; the standard read is still attempted. The accessibility tree may also not be ready right after the first set. In that case the read exits under the timeout policy and the user triggers it again; no fixed sleep or background polling is added.

Compatibility boundary: the current implementation unconditionally tries to set this attribute on every frontmost app (non-Electron apps return an error, which is ignored), then follows the standard read. It has not been tested on a real Electron app; the supported range will be recorded after testing on real hardware.

## Permissions, errors and privacy

| Result | Handling |
|---|---|
| `.permission` | Show the Accessibility permission prompt with a System Settings entry; do not pop the authorization dialog on every read |
| `.secure` | Do not access text content; the UI presents it as unreadable |
| `.unreadable` | No selection, unsupported app, attribute error, source changed or timeout; no request without source text is sent |
| Success | Only the currently valid operation imports the text and runs the corresponding processing |

While the toolbar is not yet expanded, a compact prompt is shown; once expanded, the content area is kept and the error is shown. When the user chooses manual input, the full window opens, and that input does not inherit the external selection's write-back permission. The exact interaction follows the [product definition](../spec/product.md) and the [error presentation decision](../spec/processing/decisions/BDR-0002-preserve-open-toolbar-on-error.md).

Reads happen only when the user triggers them; the selected text, document paths and AX attribute contents are not recorded in diagnostic logs. The `AXUIElement` and source context are kept only for the current operation and are not persisted as a recoverable write-back permission. Both the copy fallback and paste write-back temporarily overwrite the clipboard, and each puts the user's original content back when done.

## Implementation order (done)

1. **Fix the capture order and source consistency**: keep `SelectionBridge`; check for password fields before reading text; find the focused control through a fixed PID; add return type checks; reuse the source text from one read.
2. **Make the read bounded and non-blocking for the UI**: change the `PanelController.read` interface to complete asynchronously; wire in the worker queue, the total budget and operation IDs; keep the existing failure presentation.
3. **Verify app compatibility**: add Electron's on-demand compatibility handling and record the supported range after testing; do not build an app adapter framework in advance.

Each step changes only the relevant part of the read chain and adds the necessary tests; this design does not extend write-back, history or shortcut configuration.

## Acceptance

Automated checks (covered):

- [x] Password field: attribute calls are recorded, and the test asserts text and selection were never requested (`secureFieldNeverReadsTextOrRange`).
- [x] Text is read only once, and the selection range is decoded after type checks (`textIsReadOnceAndTheRangeIsDecoded`).
- [x] The selection is found on the focused element, an ancestor, the subtree and a web text marker range; a blank selection is not treated as a selection (`searchFindsSelectionOnAnAncestor`, `searchFindsSelectionInADescendant`, `searchReadsSelectionThroughAWebKitMarkerRange`, `searchSkipsBlankSelections`, `searchWithoutAnySelectionIsNil`).
- [x] The copy fallback runs only when the search comes up empty, is never triggered for password fields, and the clipboard is put back (`copyFallbackReadsWhenTheSearchFindsNothing`, `copyFallbackIsSkippedForASecureField`, `copyFallbackIsSkippedWhenTheSearchSucceeds`, `copyFallbackRestoresThePreviousPasteboard`, `copyFallbackWithoutANewCopyIsNil`).
- [x] Write-back only pastes, sends not a single key to a read-only selection, and refuses without permission or when the app cannot be brought forward (`pasteReplacesTheSelectionAndRestoresTheClipboard`, `readOnlySelectionIsNeverTypedInto`, `onlyEditableTextRolesTakeAPaste`, `unknownRoleStillPastes`, `pasteRefusesWithoutFrontingTheApp`, `replaceRefusesWithoutAccessibilityPermission`).
- [x] Text that really did not change is reported as a failure, while unreadable text and replacing with identical text are not mistaken for failures (`pasteThatTheAppIgnoresIsRefused`, `unreadableElementIsNotEvidenceOfFailure`, `replacingWithTheSameTextCountsAsPasted`).
- [x] The key is sent only after the owning app is in front, and bringing it forward is requested even if it is already frontmost (`theAppComesForwardBeforeTheKeyIsPressed`, `comingForwardIsAlwaysAskedFor`).
- [x] Write-back first gives up the keyboard, and on failure the result stays on screen (`writeBackReleasesTheKeyboardThenCloses`, `refusedWriteBackKeepsTheResult`, `readOnlySelectionIsReportedAsUnwritable`).
- [x] After a successful write-back the panel closes directly, without lingering for confirmation (`successfulWriteBackClosesThePanel`, `pastedWriteConsumesTheSelection`).
- [x] Losing focus neither closes the panel nor cancels the write; a click outside the panel closes it while a click inside does not; the outside-click monitor is installed and removed with visibility (`losingKeyNeitherClosesNorCancelsTheWrite`, `mouseDownOutsideDismissesButInsideDoesNot`, `mouseMonitorFollowsVisibility`).
- [x] The synthesized key is a complete ⌘-bracketed sequence, not a single key carrying only flags (`commandPressBracketsTheKey`).
- [x] A timeout only shows a prompt first: a late but valid read still takes effect, while a read arriving after close is discarded (`readPastBudgetShowsUnreadableThenAcceptsTheLateAnswer`, `lateReadAfterCloseIsIgnored`).
- [x] Repeated triggers accept only the latest operation, and pending reads do not accumulate (`rapidTriggersAcceptOnlyLatestRead`, `keepsOneRunningAndLatestPending`).
- [x] Missing values, wrong types and blank selections fail safely, and whitespace and Unicode are preserved (`wrongTypesFailSafely`, `blankOrMissingIsUnreadable`, `missingFocusedElementIsUnreadable`).

To do:

- [ ] Switching the frontmost app during capture is rejected: the code already compares the PID on the main thread, but there is no automated test yet.
- [ ] Clipboard contents and `changeCount` are unchanged before and after the ⌘C fallback when AX comes up empty: `copyFallbackRestoresThePreviousPasteboard` covers the flattened logic, but an end-to-end check against the real clipboard is still missing.
- [ ] Real hardware: TextEdit, Safari, Chrome and at least one Electron editor; record for each whether the read succeeds, the fallback to manual input, retry after first authorization, and focus switching; also verify password fields, no authorization, no selection and an unresponsive target app. Tested by hand: reading and replacing inside a Safari input field both succeed (2026-09-27). The 150 / 900 ms parameters are adjusted with testing.

Passing unit tests do not replace cross-app testing; the list of supported apps is based on real testing.
