[English](product.md) · [简体中文](product.zh-CN.md)

# macOS Translation and Polishing Tool: First-Version Product Definition

## Positioning

A macOS tool with a Raycast-style floating panel: select text, press a shortcut to translate or polish it, and manually collect words, phrases and whole sentences worth learning into a personal notebook.

It serves personal use first. The user's native language is Chinese and they mainly use English and Japanese, but the product is not tied to any particular language or content domain; it covers everyday reading, writing and work communication.

## System Support

Minimum macOS Tahoe 26.0 (the release that introduced Liquid Glass); earlier systems are not supported.

## Core Flows

### Translate

Select text → translate shortcut → the panel shows the translation → copy the result or explicitly replace the original selection → collect if wanted.

- Before sending the request, the app detects the source language locally, then picks the target from the user's "source language → target language" mapping. When the mapping has no row for that source language, or the language cannot be detected reliably, the fallback target language is used (Simplified Chinese by default). See the [target mapping decision](settings/decisions/BDR-0003-translation-target-mapping.md).
- The "Languages" group in settings maintains a language subset (Simplified Chinese, English and Japanese by default). The target language, the fallback target and the mapping table only offer languages from that subset, instead of picking among hundreds; source languages outside the subset still use the fallback target. Each language also has a reading notation (by default IPA for English, kana for Japanese, pinyin for Chinese, IPA for others; Japanese can switch to romaji, Chinese to zhuyin), used when filling in readings in the notebook and when looking words up while reading.
- The translation display can be switched on the "General" settings page between "Source / Result Sections" (default) and "Sentence by Sentence". The choice is persisted and shared by the full window and the panel. Sections show the full source and the full translation separately; sentence-by-sentence groups each sentence with its source above and its translation below, and line breaks do not change the pairing. In both modes copy and replace output only the translation, and switching the display does not call the model again.
- The target language defaults to "Automatic", decided by the mapping. The user can also pick a language explicitly; that choice overrides the mapping persistently, survives a restart, and stays until switched back to "Automatic".
- When reading the selection fails, a compact notice appears with a manual input entry ("Enter Text"); choosing it opens the full window, where the text can be typed or pasted.

### Translate and Replace

Select text → "Translate and Replace" shortcut → translate into the current target language → locate the original selection → write back directly, with no extra click on Replace.

- Uses its own configurable global shortcut. It follows the translation target mapping; if the user explicitly chose a target language, that choice is used.
- Writes back only to an original selection that was read and can be located reliably. Without a valid selection it shows a compact notice with an inline manual input entry and does not expand the input UI automatically; the user can enter text after opening the full window, but nothing is replaced elsewhere automatically. Esc closes and cancels.
- Nothing is written back when translation fails, the request is cancelled, or a newer operation supersedes it; when write-back is impossible the translation is kept for copying.
- After a successful write-back the panel closes immediately without a confirmation step; if write-back fails the panel stays, shows the reason and keeps the translation for copying.
- Copying the result counts as a completed interaction just like write-back, so the panel closes after copying.
- History is saved as for a normal translation; if the translation succeeds but replacement fails, the translation record is still kept.
- Uses the translation study setting; generating study content does not block replacement and never triggers automatic collection.

### Polish

Select text → polish shortcut → the panel shows the source and the polished result separately → copy the result or explicitly replace the original selection → collect if wanted.

- Keeps the source language and meaning; fixes grammar and improves naturalness.
- Gives one result by default, with no multiple versions or tone presets. Source and result are each shown once as plain text, with no diff background colours, strikethrough or change-comparison toggle.
- Distinguishes grammar fixes from style improvements and does not describe style preferences as errors.

### Two Interface Forms

- App form: a menu bar icon is always present and the app also has a Dock icon; after the main window is closed or hidden, clicking the Dock icon brings it back.
- The four shortcuts (Translate, Polish, Translate and Replace, Polish and Replace) all summon the same compact floating toolbar in the visual style of macOS Spotlight and enter the matching mode: no sidebar, no full app chrome; results and study content expand on demand, and Esc dismisses it.
- The first quick operation shows a source summary bar with a separate status bar below it, with a transparent gap between them; the source bar offers Close and the status bar offers Cancel. On failure the source is kept and Retry and recovery entries are offered; on success the panel expands to source / result, and once Study is expanded it becomes a result / study two-column layout. Closing or Esc cancels any unfinished operation. Everything uses the system Liquid Glass; no breathing border is drawn.
- The toolbar shows the Owlet logo and the operation picker on the left, and only Refresh and Settings on the right. The main interface is opened from the menu bar icon or the Dock icon; the notebook and history are reached from the main interface.
- The full window provides a single "Translate & Polish" page, following the Figma Translate / Polish boards: the toolbar has an icon-only Translate / Polish segmented control and the mode title on the left, and language pickers on the right (Polish has only the source language). Source and result sit side by side in one glass card, stacked vertically in narrow windows. The Study and Copy buttons float at the bottom-right of the card, and Study expands the same way as in the panel. The page has no run button; ⌘↩ processes. The left side does not offer "Translate and Replace"; that action keeps its own selection shortcut.
- The notebook and history are sidebar pages of the main window. Settings is a separate settings window (opened from "Settings…" in the app menu or ⌘,), grouped into tabs internally; the sidebar no longer has a settings entry. Review is still not implemented in the first version.
- The interface language supports Simplified Chinese, Traditional Chinese, English and Japanese, following the system by default; it can be set on the "General" settings page, and the change takes effect on the next launch. **The only exception is the language picker itself**: it writes each language in its own name (简体中文 / 繁體中文 / English / 日本語) so it can be recognized before switching; elsewhere language names follow the interface language. Prompts, task descriptions and examples sent to the model stay in Simplified Chinese and do not change with the interface language (see the [interface language decision](settings/decisions/BDR-0011-interface-language.md)).
- Translate and Replace and Polish and Replace keep their own shortcuts and do not depend on opening the full management window first.

### Panel and Replacement

- Translate, Polish, Translate and Replace, and Polish and Replace each use a configurable global shortcut. Buttons in the panel and the main window all have fixed shortcuts (Copy is ⌘C, which copies the result when no text is selected); button tooltips show the key, and the Shortcuts page lists every fixed key. On the Shortcuts page, clicking the current combination records it again, with cancel, clear and conflict warnings; it takes effect once saved. There are no default combinations; an unrecorded shortcut never fires.
- Keyboard operation is supported. When a lookup card is open, Esc first closes the card and returns focus to the text; otherwise it closes the panel. The panel closes only on Esc, an explicit close ("Done"), or a mouse click outside the panel; losing keyboard focus does not close it.
- For normal Translate / Polish, the user clicks Replace to write back; the "Translate and Replace" and "Polish and Replace" shortcuts explicitly authorize writing back this result as soon as it is generated.
- If no selected text can be obtained, no model request is made. When the toolbar is not expanded, a compact notice with a manual input entry is shown; when the toolbar is already expanded, the UI stays and the problem is shown in the content area. Manual input happens in the full window and is never written back to the original selection automatically.
- When the original selection cannot be written back, the app says so and keeps the result for copying.
- History details have no Copy button and never use the original selection of a past operation to replace text.

## Study Content and Collection

- Translate and Polish each have their own study content switch, off by default.
- Manual by default: no study expressions are requested after the main result returns; expanding "Study" makes a separate request without changing the long-term setting. Content that has already returned is not requested again when collapsed and expanded.
- With "Request study expressions after translating" (or after polishing) turned on, every successful main result triggers a separate study request that does not block copy or replace; Translate and Polish are controlled separately. It suggests words, collocations or sentence patterns; the definition language follows this translation's target (Polish looks up the source language in the target mapping), and it does not pad the count. Study content **excludes native languages** (chosen on the "Languages" settings page, **multiple selection allowed**; this only affects which items are suggested, not the definition language). See the [definition language decision](learning/decisions/BDR-0005-definition-language.md) and the [native language decision](learning/decisions/BDR-0012-native-language.md).
- Polish study content explains the differences before and after the edit and why.
- Whether or not study is on, the user can select a fragment of the source or the result and collect it.
- No automatic collection. Suggested items can be checked to add them; hand-selected content can be collected directly.
- Clicking "Add to Notebook" saves immediately, with no required form; after saving, the entry can be edited in the notebook detail.
- Words, phrases and full sentences are collected the same way; the user does not need to classify them first.
- An entry keeps the expression, language, source sentence and in-context meaning; polish entries also keep the before / after comparison. Each context records its source entry point (selection / study suggestion / history) and the app the text came from; manually entered text has no source app.
- An entry also records the dictionary form and the definition language. The expression is the actual form at collection time; the dictionary form comes from the study suggestion (see [BDR-0009](learning/decisions/BDR-0009-learning-lemma.md)), and the notebook detail shows a differing dictionary form as secondary information. The definition language is computed from the current target mapping at generation and regeneration time and is **not frozen on the entry**; the entry records the language the stored meaning is actually written in. When the mapping changes, old entries are not recomputed automatically; they can be regenerated in the detail view using the current settings (see [BDR-0005](learning/decisions/BDR-0005-definition-language.md)).
- When the same expression is collected again, a new context can be appended to the existing entry; identical expressions in different languages are not merged automatically.

## Personal Notebook

- Stores what the user chose to collect, locally.
- Supports a native list / detail split, search, filtering by language / tag / starred / source app, and deletion, with each column scrolling independently. Filters sit on the left of the toolbar with previous / next as a separate group; Delete and Search are on the right. There are no export or copy buttons.
- In the detail view the meaning, expression, language, notes, tags and starred flag are editable; contexts are not. Edits apply immediately. The meaning can be overwritten by regeneration; notes are never touched by automatic flows. See the [editable notebook decision](vocabulary/decisions/BDR-0004-editable-notebook.md).
- Reading and part of speech are not requested at collection time; they are filled in on demand in the detail view. "Fill in missing" only fills empty fields and never overwrites; meaning / reading / part of speech each have their own "Regenerate", which overwrites only that field. Whole-sentence entries get no reading or part of speech. The reading notation is configured per language in the "Languages" settings group and saved with the entry. See the [on-demand enrichment decision](vocabulary/decisions/BDR-0006-on-demand-enrichment.md).
- The first version only manages and shows collected items; there is no review flow or mastery tracking.

## Looking Up Words While Reading (Step One, Implemented, Awaiting Final Acceptance)

- Covers the reading content of the panel, the text processing page, the notebook detail, the history detail and study expression rows. In read-only text, holding ⌘ and clicking a word looks it up (while ⌘ is held, the word under the pointer is highlighted and the cursor becomes a hand). Chinese, Japanese and similar languages use system word segmentation; when the split is not what the user wants, they can select text by hand. The source input field and notebook edit fields keep their editing behaviour.
- After selecting a word, phrase or whole sentence, the toolbar shows "Look Up" and the context menu keeps "Look Up Selection". Selecting does not send a request, and looking up does not widen the selection. Study rows keep their existing click-to-collect behaviour and are looked up through the selection toolbar or the context menu; a drag selection does not accidentally collect.
- The card uses the looked-up form as its title, with the dictionary form as secondary information when it differs; it explains the in-context meaning, with part of speech and usage when needed. When there is no source sentence it shows "No source sentence" and explains only the general meaning. Whole sentences show no reading or part of speech.
- The definition language follows [BDR-0005](learning/decisions/BDR-0005-definition-language.md): translation follows this operation's target, polish looks up the source language in the target mapping; history and study inherit the rule of their source, and the notebook regenerates with the current mapping. There is no separate lookup language picker.
- The reading notation follows [BDR-0006](vocabulary/decisions/BDR-0006-on-demand-enrichment.md) and may be missing when uncertain. The system voice reads the looked-up text, only when played manually; the next playback interrupts the previous one, and closing or switching the card stops it. When no voice is available, the Speak button is disabled with "No system voice available", and the meaning is not blocked.
- Identical lookup conditions reuse the existing result. When reusing across sentences, the card clearly marks that the old meaning came from another sentence, shows that source context, and offers "Look Up in This Sentence" without re-querying automatically. If the re-query fails, the usable old result and its source label are kept. A limited number of lookup results are kept only for the current app run and cleared on quit; no lookup history is saved.
- One card is shown at a time. After switching lookups, closing the card or leaving the page, an old response must not overwrite the new card or reopen a card. Lookup works with the keyboard and VoiceOver; Esc first closes the card and returns focus to the text.
- The card can explicitly add the current word to the notebook: a bookmark action labelled `Add to Notebook` / `Saved` saves the looked-up form, this context, this meaning, the definition language and any known dictionary form, without sending another request. The card stays open; clicking again removes it. It reuses the notebook's existing same-language same-expression rule, and looking up alone still never adds to the notebook (see [BDR-0010](vocabulary/decisions/BDR-0010-collect-from-lookup.md)).
- Still not done: a lookup input field, writing the card back into an existing notebook meaning, lookup history and external dictionary services; these are left for step two.

Behaviour is detailed in the [lookup spec](vocabulary/features/word-lookup.feature) and the [lookup decision BDR-0008](vocabulary/decisions/BDR-0008-reading-word-lookup.md). Lookup in all five areas is implemented and natively accepted (T48–T51); the spoken system voice, real VoiceOver and a real installed build still await final acceptance.

## History

- Automatically saves the source and result of translate and polish operations, with the operation type, language, time and the app the text came from.
- Provides a history list and detail. The list is grouped by day, newest first; it supports search and filtering by Translate / Polish, has collected items, and source app, and the filters combine. The detail lists entries collected from that record and can jump to the notebook. See the [history as a learning log decision](history/decisions/BDR-0007-history-as-learning-log.md).
- List and detail are split columns (no glass card), sized to the available width, and do not overflow when the window shrinks. The toolbar is translucent and content scrolls underneath it; a subtitle below the title shows the record count. Filters are on the left of the toolbar with previous / next as a separate group; Delete and Search are on the right. Study and Copy buttons float at the bottom-right of the detail: in study mode the source collapses, the result stays on top, the study list expands below, and clicking an item collects it immediately (as in the panel); the whole source text is never collected directly.
- Single records or multiple selected records can be deleted; after selecting all, they can be deleted in bulk. Records never expire automatically.
- History and the notebook are independent: deleting history does not delete collected entries or their source sentence contexts, and the source information on the entry is kept. After an entry is deleted, the collected list in the history detail shrinks accordingly.

## Model and Data Settings

- The user fills in the Base URL, API Key and model name of an OpenAI-compatible endpoint, or picks a provider from the list (DeepSeek, Moonshot / Kimi, Zhipu GLM, Qwen / DashScope, xAI, OpenRouter, Ollama, LM Studio). Picking one fills in that service's public Base URL and default model, which can still be edited afterwards. The "OpenAI Compatible" entry remains for any compatible service. The response format capability (JSON Schema or json_object) follows the chosen service. See the [provider presets decision](settings/decisions/BDR-0015-provider-presets.md).
- The API Key is stored in the macOS Keychain.
- Besides HTTP services, the user can choose a signed-in local agent CLI (Claude Code, Codex CLI) as the provider. Instead of an API Key, the user points to that agent's executable; the model name can be left empty to use the agent's own default. Both agents offer the model name as a dropdown whose first item is the agent's own default model: Codex runs its own listing command, and Claude Code reads the local catalogue it caches for its model menu, falling back to free text when that cannot be read. Both offer effort levels per model. The app only borrows it to get one answer: tools, skills, MCP, project context and session persistence are all off, the working directory is a throwaway empty directory, the user's text goes only through standard input, and the reply is still bound by the same JSON contract and local validation (see the [local agent decision](settings/decisions/BDR-0013-local-agent-provider.md)).
- Translate and Polish each support a custom System Prompt, showing the full default content, with edit, save and restore default; Translate and Replace reuses the translation configuration.
- The LLM must return JSON that matches the app contract. The main result contains sentence-by-sentence source / translation pairs, and study content is requested separately; a failed JSON validation must not replace the source text. See `spec/llm/contract.md`.
- History, the notebook and app settings are stored on this Mac.
- Translation, polishing, study content generation and reading lookup use the model service the user configured, and the relevant text is sent to that service. Lookup sends only the looked-up text and the local context covering the selection, not the whole text by default. Local storage does not mean offline inference. With a local agent, the text goes to that agent's own service and is subject to its sign-in state and quota.

## Not in the First Version

- Review, spaced repetition, study reminders, study plans: the first version only processes text and accumulates content.
- Automatic collection, complex proficiency assessment, mastery inference: the user decides what to save.
- Multi-device sync, accounts, social features: a complete single-machine experience comes first.
- Standalone courses, multiple polish variants, tone templates: keep the core interaction simple.

## Scope Boundary

This document defines product behaviour and the first-version scope; it does not include validation experiments or success metrics. The project is named Owlet; the technical implementation does not extend the scope above.

- The Owlet icon stays in the menu bar; clicking it opens the text processing page of the main interface. The app also has a Dock icon, which brings back a closed or hidden main window. The floating toolbar shows no Esc button; the Esc key only closes and cancels unfinished operations, and never enters any "Open Owlet" placeholder UI.

- The main interface offers no "back to floating toolbar" action; the floating toolbar is triggered by global shortcuts and the main interface stays independent.

- When Translate, Polish or Translate and Replace hits a read failure, missing permission or configuration, a connection or authentication failure, a malformed reply, a write-back failure or a cancellation while the toolbar is not yet expanded, only a compact notice with the matching inline settings / recovery entry is shown. Permission problems lead to permission settings, service problems to service settings, and format problems to the prompt settings of that operation; after a write-back failure the existing result can be copied, and after cancelling the text can be processed again. Esc closes and cancels this operation, and a failed write-back is not retried.

- When an already expanded floating toolbar processes again, it stays expanded and shows progress in the result area. Later failures, permission or configuration problems, write-back failures and cancellations are all shown in the content area with the matching inline settings / recovery entry, without collapsing back to the compact bar. The source and any still-usable result are kept; a failed request is never presented as a success. The first quick operation still uses the compact processing state.

- The full app adds a separate "Shortcuts" page in the left navigation, listing common actions, their current bindings and scope. Global bindings show the combination the user saved and can be recorded, cleared and saved directly on this page, without jumping to settings. It is not a tab alongside Translate / Polish. Shortcuts that are not implemented or not confirmed are never presented as active.

History and the notebook support system multi-selection deletion, with previous / next as a separate toolbar group.

Study in the panel uses a per-item collect button that shows Saved after a successful save; the main window keeps the existing study selection and bulk-add flow. The bottom-right of the panel offers Close and Copy; other modes, languages and replace actions are in the context menu.

"Glass Effect" in the General settings affects only the panel: More Transparent / Higher Contrast (default), applied immediately and persisted. Liquid Glass and its intensity are adjusted in "System Settings › Appearance"; this group gives a one-line explanation and an entry that opens that pane, and the app provides no intensity control of its own.

The panel expands from the processing state into the result panel with a spring animation, respecting the system Reduce Motion setting.

The panel's study view expands with a spring animation. Clicking anywhere on an item row toggles its notebook membership immediately; removing takes effect immediately, with no confirmation or submit step. The full-window study flow is unchanged.
