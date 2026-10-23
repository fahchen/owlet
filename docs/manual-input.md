[English](manual-input.md) · [简体中文](manual-input.zh-CN.md)

# Manual Input in the Panel

Status: implemented (2026-10-23); the four open decisions are settled in [BDR-0018](../spec/processing/decisions/BDR-0018-manual-input-in-panel.md), which follows the recommendations below. The rest of this document is the design record.

## What happens today

- A trigger whose selection cannot be read (`.unreadable`, and a secure field, which maps to it) shows a compact prompt — "Could not read any text" with the action "Enter Text" (`PanelController.swift:48`, `:169`). Choosing it closes the panel and opens the main window's Translate page, where the source is an editable `TextEditor` (`PanelRootView.swift:147`, `OwletApp.swift:303`, `TextProcessingView.swift:161`).
- A missing Accessibility permission is its own compact prompt with "Permission Settings" (`PanelController.swift:165`).
- A successful read puts the text into the source, starts the request, and the panel expands — today on the first streamed piece or on the result (`PanelController.swift:150-163`).
- The expanded panel's source is already editable (`ExpandedPanelContent.swift:41`). In Sentence by Sentence, a finished result folds that source away and shows only the pairs (`ExpandedPanelContent.swift:51`).
- The product rule is explicit: a failed read shows a compact prompt with a manual input entry, and the input happens in the full window; replacement never auto-expands an input surface (`spec/product.md:23`, `:30`, `:61`). BDR-0002 adds the reason: a blocker met before expansion does not need the unusable processing interface.

## Proposal

### 1. No readable text: the panel opens as the editor

A trigger with nothing readable enters manual input mode directly, in the panel the shortcut already uses:

- The panel expands with an empty editable source, focused and ready for typing. No request is sent, `selection` stays nil.
- The content area carries the existing wording ("Could not read any text") as a note, without an action button: the editor is the way out.
- Placeholder and ⌘↩ remain the page's own (`spec/DESIGN.md:64`); ⌘↩ on an empty source does nothing, as it already does in the main window.
- Esc closes and drops the text, exactly as an unfinished panel does today.
- The replace shortcut has no selection to write back to, so it keeps today's rule: manual input never writes back (`spec/product.md:30`).

Why this does not contradict BDR-0002's spirit: the surface it refuses to show is one that waits on a setting or a retry. Here the surface *is* the fix — an input field — so showing it is the shortest path, not a dead end. Permission and configuration failures keep their compact prompts for exactly that reason.

### 2. With text: an explicit entry into the editor

- The compact source bar gains a pencil control ("Edit Text") that expands the panel and focuses the source editor with the caret at the end. Clicking the source text already does this once expanded; the control makes it discoverable and reachable before the first piece arrives.
- The expanded panel needs no new control: the source is editable there today.
- In Sentence by Sentence, a finished result folds the source away. Entering edit must show the source field again, with the text it already holds, until the text changes or the panel closes (decision 4).
- Not proposed: a "new text" action that clears the source. Clearing is destructive, ⌘A and delete already do it, and there is no evidence yet that users need it (decision 2).

## States at a glance

| Trigger result | Today | Proposed |
| --- | --- | --- |
| Nothing readable, or a secure field | Compact prompt + "Enter Text" → main window | Panel expands empty and editable; the note stays in the content area |
| No Accessibility permission | Compact prompt + "Permission Settings" | Unchanged (decision 1) |
| Selection read | Compact → request → expands on the first piece or result | Unchanged |
| User wants to change the text | Expand, then click the source; folded away in Sentence by Sentence | Pencil in the compact bar; the fold rule above |

## What does not change

- No model request for empty or blank input, and no write-back without a `Selection`.
- Manual input keeps no source app in history ([BDR-0007](../spec/history/decisions/BDR-0007-history-as-learning-log.md)).
- The shapes of failure prompts, retry, and the "keep the open toolbar on error" rule.
- The main window remains the place to read and edit long text; this proposal only removes a window switch from the empty case.

## Spec changes if accepted

- `spec/product.md:23`, `:30`, `:61`: "compact prompt and manual input entry in the full window" becomes "the panel opens as an empty editor"; the no-write-back rule stays.
- BDR-0002 gains the exception, or a new BDR records it: an editor that accepts input is not an unusable interface.
- `translation.feature` and `replacement.feature` manual-input scenarios are rewritten to the new entry.
- `Notice.actionTitle` no longer needs "Enter Text" for `.unreadable` once the prompt is gone.

## Decisions for the human

1. **Permission failure.** Keep the compact permission prompt (recommended: it has a one-click fix, and manual input is still available through the pencil), or open the editor with the permission note as well.
2. **With text.** Pencil only (recommended), or also a "new text" action that clears the source.
3. **Where manual input lives.** The floating panel (recommended), or the main window as today. If the panel wins, decide whether the main window route stays as a secondary "open in window" entry.
4. **Sentence by Sentence after a result.** Entering edit reveals the folded source (recommended), or switches this run to the sectioned layout.

## Must be checked on real hardware

- Focus after a global shortcut: the panel becomes key and the editor takes first responder without losing the shortcut or the IME state.
- Panel height and layout with an empty editor; whether the note reads as an explanation rather than an error.
- Sentence by Sentence fold/unfold while editing.
- Esc, ⌘↩, and the copy entry while the editor is empty.
- A replace trigger that lands here: the result stays copyable and nothing is written back.
