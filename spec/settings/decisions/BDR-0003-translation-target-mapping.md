[English](BDR-0003-translation-target-mapping.md) · [简体中文](BDR-0003-translation-target-mapping.zh-CN.md)

# BDR-0003: Choose the translation target from the source language

Status: Implemented (T26, 2026-10-04). Origin: user request to support source→target mapping, for example English defaults to Chinese and Chinese defaults to English.

The scope is only "how the translation target language is decided". Polish and shortcuts are unchanged: polish keeps the source language, and shortcuts are still the fixed bindings for Translate, Translate and Replace, and Polish.

## User value and motivation

The user works in both directions: Chinese when reading English or Japanese, English when writing English. Today the target language is a global session state that the user maintains by hand, so every reverse translation adds a round of "notice the direction is wrong, switch the target, trigger again", and this happens exactly when attention is already on writing. When the user forgets to switch, the result goes the wrong way (a Chinese draft translated into Chinese). The text looks unchanged, and the user can easily think the model did nothing.

This feature turns the target language from "session state the user maintains" into "a rule set once". The direction follows the text, and the user no longer has to remember the current target. The value only holds for bidirectional users: someone who only translates one way gains nothing and gets a new failure mode, "detection guessed wrong". This project's actual usage is frequent, so the value holds.

This is also the one part that a lighter solution cannot replace. A "swap direction" button solves "I noticed the direction is wrong and want to flip it", but not "I never notice the direction was wrong".

## Decision

### 1. Target = mapping table + fallback target

- **Mapping table**: `source language → target language`. One source language maps to exactly one target, with no ordering; adding the same source language again replaces the old target. **Empty initially**; the user adds rows one by one.
- **Fallback target**: a separate setting, **default `zh-Hans`**. Used when the source language is not recognized or has no row in the mapping table.
- With an empty mapping table everything uses the fallback, and behavior matches today (always translate into Simplified Chinese).

### 2. The source language is detected locally before the request is sent

The current flow is "send the request, the model reports `source_language`", but the mapping must fix the target before sending, so a local detection step is added:

- Use NaturalLanguage's `NLLanguageRecognizer` and normalize by the rules of the [LLM contract](../../llm/contract.md): compare the primary language subtag, and split Chinese further into `zh-Hans` / `zh-Hant`.
- The source side can specify the source language explicitly (default "Automatic" follows detection). An explicit choice is only used to **look up the mapping table**; the request still lets the model read the language itself.
- Failure path: not recognized, confidence too low, or result not in the mapping table → fallback target.
- Mixed text takes the language with the largest share (for example, Chinese with English terms counts as Chinese).
- Detection is **only used to choose the target**: the request still sends the resolved concrete target language; the model's returned `source_language` remains authoritative and need not match local detection; the returned `target_language` must equal the request (existing validation unchanged).
- The confidence threshold, minimum text length, and mixed-text rule are implementation parameters, calibrated on fixed samples with tests during implementation. The design only requires "low confidence goes to fallback".

Rejected alternative: "send an automatic target to the model and let it decide". It would require changing the request contract and relaxing target validation.

### 3. Language options come from the system, but only a user-chosen subset is shown

- The settings "Languages" group maintains a subset (default `zh-Hans`, `en`, `ja`). The target language control, the fallback target, and the source/target columns of the mapping table only offer languages in the subset.
- The subset comes from the system list (`Locale` ISO language codes plus localized names); the full list only appears under "Add Language". NaturalLanguage does not publish the list it can detect, so source and target languages share the same list.
- Language names follow the **interface language** (changed with i18n on 2026-10-11). The "Interface Language" picker in settings is the exception: it still writes each language in its own name, so it can be recognized before switching.
- Chinese is the only addition: the system list only has `zh`, while the contract treats Simplified and Traditional as different targets, so `zh-Hans` / `zh-Hant` are provided explicitly.
- When a language is removed, mapping rows that reference it are deleted with it; if the fallback target or a pinned target points to it, they move to the first language in the subset / back to "Automatic". The subset keeps at least one language.

### 4. Toolbar target language control

- **Default "Automatic"**: resolves by mapping + fallback; in automatic mode the control shows the resolved result (for example `Automatic (Chinese)`).
- **Explicit language choice**: persistently overrides the mapping, survives restarts, until the user switches back to "Automatic".
- Translate and Replace reuses the translation's resolved result; Polish does not show this control (current behavior).

### 5. Polish is unchanged, with one added rule for mixed text

- Polish does not use the mapping and does no local detection; its target always equals the source language (the contract's `target == source` is unchanged).
- The default prompt gains one sentence: mixed text in the original (such as Chinese with English terms) stays as is; no fragment is translated, transliterated, or normalized. This changes `polish` in `Owlet/ModelPrompts.json`.
- The local detection result is not passed to Polish as the "source language": detection is unreliable on mixed text anyway, and passing it could push the model to unify all fragments into one language.

### 6. Data and migration

- Add `translation.targetMapping` (the source→target mapping) and `translation.fallbackTarget`.
- The existing `translation.targetLanguage` is read in as the fallback target, with an empty mapping table, so users do not lose their current setting.

## Impact

- **LLM contract unchanged**: requests still carry a concrete `target_language`; the schema, validation, and Polish's `target == source` are untouched. Only the moment the target is chosen changes.
- **History and result cache**: the cache key already includes `language`; no change needed.
- **Panel and main window share one resolution**: both `PanelController.translate()` and `TranslationView.translate(to:)` go through the mapping and no longer read `translation.targetLanguage` directly.
- **Settings** gains a "Target Language" group: fallback target plus an editable mapping table.

## Explicitly out of scope

- No per-pair shortcuts; shortcuts stay as fixed bindings (since 2026-10-11 Polish and Replace was added, four in total).
- Polish does no mapping and never outputs another language.
- No leader-style shortcuts.
- No preset mapping rows.

## Values fixed during implementation

- Detection thresholds: the leading language's confidence ≥ 0.5 and its lead ≥ 0.2; only the first 400 characters are sampled. When unsure it returns "not recognized" and uses the fallback. (`LanguageDetector`, covered by fixed samples in `LanguageDetectorTests`.)
- The "Translation Target" group sits on the settings "Languages" tab, after the language subset: fallback target plus a mapping table with one row per source language, saved on change. Source language candidates hide languages already used by other rows, so duplicate source languages cannot occur.
