[English](BDR-0004-editable-notebook.md) · [简体中文](BDR-0004-editable-notebook.zh-CN.md)

# BDR-0004: The notebook is editable

Status: Accepted (2026-10-04, not yet implemented). Source: user request. The user wants to build their own notebook with Owlet, and saved items that cannot be edited cannot become study material.

Supersedes the editing part of two statements in the first version of `spec/product.md`: "the notebook offers no way to edit" and "no export, copy or edit buttons". Export and copy are still not offered. Saving is unchanged: "clicking Add to Notebook saves it, no form is required". Editing happens after saving.

## User value and motivation

The first version defined the notebook as a read-only list: saving stores an item, and afterwards it can only be viewed or deleted. That is enough for collecting, not for studying. The model's meaning is sometimes off and sometimes wrong, and the user cannot correct it. There is nowhere to write down one's own understanding of a word. Once the list grows, there is no way to find items by topic. The first version kept the core interaction simple, but the cost of that simplicity landed on what the user does most often: going back to their own words.

With editing, the notebook stops being a record of saved results and becomes material the user maintains. The user decides the final content of every entry; the model only provides a starting point.

## Decision

### 1. Editable fields

Meaning, expression, language, notes, tags and starred. The context (the source sentence and the polish before/after pair) is not editable. It is the actual record of the moment the item was saved; once edited, it is no longer a record.

### 2. The meaning can always be overwritten by regeneration

A meaning the user has edited is overwritten unconditionally by the model's result when the user triggers "Regenerate meaning". There is no confirmation and no lock.

Reason: the notes field already plays the role of "never touched by automatic flows". If the meaning were protected too, there would be two safe areas, and the user would have to remember which one gets overwritten. The rule fits in one sentence: **the meaning belongs to the model, the notes belong to you**. To keep your own wording, write it in the notes.

Rejected alternatives: "confirm before overwriting" and "lock once edited". The first adds a step that buys nothing; the second needs extra state and an unlock control.

### 3. Expression and language are editable; a change that collides with an existing entry in the same language is rejected

If changing the expression or the language makes the entry identical to an existing entry in the same language, the change is rejected and the old value is kept. Contexts are not merged automatically.

Reason: a wrong language is a common result of language detection (Japanese kanji words detected as Chinese), so it must be correctable. A wrong expression is usually extra punctuation picked up when saving. A collision is more likely a typo than an intent to merge, and merging cannot be undone.

### 4. Edits take effect immediately; there is no save button

This matches editing the API Key and the prompts in Settings: a change is a change. There is no "unsaved changes" state and no cancel. The one edit with consequences (changing the expression) is covered by the rejection rule in item 3.

### 5. No tag management

Tags are free text. While typing, previously used tags appear as suggestions. A tag that no entry uses simply disappears. There is no page to rename, merge or delete tags: a tag is an attribute of an entry, not an entity of its own. Near-duplicate tags ("work" vs "work terms") are mitigated by suggestions, not by management.

### 6. Concurrent edits are not protected

If the floating panel fills in a meaning for an entry while the user is editing the same entry in the main window, the last write wins. On a single machine with a single user this path is extremely rare, and a state machine for it is not worth it. This is consistent with item 2.

## Impact

- `spec/vocabulary/features/editing.feature` (new): scenarios for the rules above.
- `spec/vocabulary/features/notebook.feature`: "no export, copy or edit buttons" becomes "no export or copy buttons"; the filter rules add tags and starred, combined with the language filter.
- `spec/product.md`: the matching sentences in the "Personal notebook" and "Study content and saving" sections are updated.
- Glossary: adds "meaning", "notes", "tags" and "starred".
- Data: meaning, notes, tags and starred each need a persistent field; the uniqueness constraint on expression plus language is unchanged. See the SwiftData models in `Owlet/Vocabulary/` for the fields.

## Explicitly out of scope

- The context is not editable.
- No export or copy buttons (same as the first version).
- No tag management page.
- No edit history or undo.
- No meaning lock or overwrite confirmation.
