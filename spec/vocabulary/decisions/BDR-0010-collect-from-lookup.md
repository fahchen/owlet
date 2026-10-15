[English](BDR-0010-collect-from-lookup.md) · [简体中文](BDR-0010-collect-from-lookup.zh-CN.md)

# BDR-0010: The lookup card can explicitly add to the notebook

Status: Accepted (2026-10-11, the user asked that "a looked-up word can be added to the notebook").

Partly supersedes "lookup results are for reading on the spot, not saved" in [BDR-0008](BDR-0008-reading-word-lookup.md). A query input field, query history and writing back to a notebook meaning are still out of scope; a lookup by itself is still never saved automatically.

## Decision

- **One explicit action at the bottom of the card: `Add to Notebook` / `Saved`.** Same semantics and same bookmark icon as saving a single study expression: one click saves, another click removes. No confirmation, no navigation.
- **Everything saved comes from this lookup's result; no extra request is sent.** The expression is the queried form, the language is the text language learned from the lookup, the lemma is `lemma`, the context is this lookup's local context, the meaning is the meaning on the card, and the meaning language is this lookup's `definition_language`. The lookup has already paid for one request; requesting again just to save would be waste.
- **The card stays open.** Saving is a side action while reading, not a signal to finish. The meaning, lemma and pronunciation stay in view, and a mistaken click can be undone right away.
- **The notebook's existing rules are reused; no new set is added.** The same expression in the same language reuses the entry and appends the context; an existing meaning and existing source sentences are not overwritten; deletion is the normal entry deletion. A lookup without context does not fake a source sentence and stores only the form and the meaning.
- **The action is not offered when the language is unknown.** An entry's identity is its language plus expression; without a language there is no usable key.

### Alternatives and rejections

- **Close the card after saving.** Matches "the panel closes after copying", but users often want to compare the meaning or hear the pronunciation, and closing would force another lookup. Rejected.
- **Store only the form and context, and fill in the meaning later in the notebook.** One more action and one more request, while the meaning is right there. Rejected.
- **Save every lookup automatically.** Conflicts with the existing principle of no automatic saving, and with the user's preference for explicit actions. Rejected.

## Impact

- `spec/vocabulary/features/word-lookup.feature`: the rule "a lookup is not saving or writing back" is rewritten, adding five groups of scenarios: add, remove, append context, failure, and no context.
- `spec/product.md`: the scope sentence of "Looking up words while reading" drops "a lookup does not write back to the notebook".
- `spec/llm/contract.md`: the lookup section keeps "a lookup failure only affects the card"; saving becomes writing an entry on the user's action.
- Implementation: `CollectionAction` gains saving from a lookup result and a membership check, `VocabularyStore` gains saving from a lookup snapshot, `LookupPresenter` carries the notebook action, `LookupCard` gains an action row; `OwletApp` makes lookups in the panel and the main window share the app-level notebook.
- Still out of scope: a query input field, query history, writing back to an existing notebook meaning from the card, and using a notebook entry's own lemma for lookup reuse.
