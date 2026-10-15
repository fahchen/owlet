[English](BDR-0006-on-demand-enrichment.md) · [简体中文](BDR-0006-on-demand-enrichment.zh-CN.md)

# BDR-0006: Reading and part of speech are filled in on demand

Status: Accepted (2026-10-04). Item 6, the per-language reading notation setting, is implemented (2026-10-11, reviewed together with word lookup while reading); on-demand filling on the detail page is not yet implemented. Source: user request. The notebook needs fields such as phonetic transcription and part of speech, and will gain more later.

Scope: where a notebook entry's reading and part of speech come from, how they are refreshed, and how the notation is chosen. The saving flow is unchanged (still "Add to Notebook saves it", [BDR-0004](BDR-0004-editable-notebook.md)), and so are the meaning language rules ([BDR-0005](../../learning/decisions/BDR-0005-definition-language.md)).

## User value and motivation

The reading is what language learners look up most often, and the part of speech decides how a word is used. Neither is needed at the moment of saving, though. Saving has to be fast, and for most entries the user never goes back to check the reading. Filling them in on demand on the detail page means saving does not pay the cost, and one click adds them when the user wants them.

## Decision

### 1. Nothing is requested when saving; the detail page fills in on demand

Saving stores only the expression, language and context, and fills in the meaning under the existing rules. The reading and part of speech are triggered by the user on the detail page.

Rejected: "the LLM returns them together when saving". It extends the learning contract with two more fields on every save, and most entries never use them. Also rejected: "manual editing only". Nobody can type IPA by hand.

### 2. Two actions: "Fill In Missing" and a per-field "Regenerate"

- **Fill In Missing**: one request fills every empty field (whichever of meaning, reading and part of speech are empty) and never touches existing content, including values the user edited. It is unavailable when all three are present.
- **Regenerate**: one each for meaning, reading and part of speech. It overwrites only that field, without confirmation.

Filling in adds; regenerating overwrites. In the user's words: "they can be separate buttons, but there can also be one button that fills in what is missing". Rejected: "one button refreshes all three". One button cannot carry both meanings.

Filling in the meaning automatically when saving has the same meaning as "Fill In Missing" (only fill what is empty); it does not get a separate rule.

### 3. A failure leaves existing content alone and can be retried; a partial success keeps what succeeded

Same as the existing rule for filling in a meaning. If "Fill In Missing" gets the reading but fails on the part of speech, the reading is saved and the part of speech can be retried.

### 4. Whole-sentence entries have no reading or part of speech

A sentence has no part of speech, and nobody reads a sentence-long transcription. The detail page does not show these two fields for a sentence, and "Fill In Missing" only fills in the meaning. To get the kana of a Japanese sentence, save the phrase rather than the whole sentence. How "whole sentence" is detected is an implementation detail.

### 5. Reading and part of speech are editable; regenerating overwrites them

Same as the meaning rule in BDR-0004: they belong to the model, the user can edit them, and regenerating overwrites them.

### 6. The reading notation is set per language in Settings and saved with the reading

It lives in the existing "Languages" group from [BDR-0003](../../settings/decisions/BDR-0003-translation-target-mapping.md): one notation per language. Defaults: IPA for English, kana for Japanese, pinyin for Chinese, IPA for everything else. The request specifies the notation; the model only returns a string.

The notation is stored on the entry together with the reading. Changing the setting affects only later fills and does not backfill existing readings, the same principle as "changing the mapping does not backfill meanings".

Rejected: "hard-code it per language". Kana versus romaji for Japanese is a real disagreement. Also rejected: "the model reports its own notation". The same language could end up with two notations.

## Impact

- `spec/vocabulary/features/enrichment.feature` (new): scenarios for the rules above.
- `spec/product.md`: "Personal notebook" gains an item on filling in on demand; the "Languages" group gains the reading notation.
- `spec/llm/contract.md`: a separate request and response fields for on-demand filling.
- `spec/README.md`: the settings domain description adds the reading notation.
- Glossary: adds "reading" and "part of speech" (to be confirmed).
- Data: entries gain reading, reading notation and part of speech fields, see the SwiftData models in `Owlet/Vocabulary/`; settings gain a per-language reading notation.
- Implementation: `ModelClient` gains an on-demand request; the detail page gains "Fill In Missing" and three "Regenerate" actions; one heuristic decides whether an entry is a whole sentence.

## Explicitly out of scope

- No reading or part of speech request when saving.
- No reading or part of speech for whole sentences.
- No refresh-everything button.
- Changing the notation setting does not backfill.
- Separate readings for multiple senses (the schema leaves room; the behaviour waits until multiple senses actually appear).
