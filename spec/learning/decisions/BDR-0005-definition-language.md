[English](BDR-0005-definition-language.md) · [简体中文](BDR-0005-definition-language.zh-CN.md)

# BDR-0005: The meaning language follows the translation target

Status: Accepted (2026-10-04), Implemented. **§3 revised on 2026-10-12**: the meaning language is now "computed from the mapping at generation time" and is no longer frozen per entry; the language field on an entry now records "the actual language of the stored meaning". Source: user request "the meaning should not always be Chinese, it should be the target language".

Supersedes "`meaning` uses Chinese" in the [LLM contract](../../llm/contract.md) and "explained in Chinese" in `spec/product.md`. The structure of recommendations, the study toggles, and having no separate meaning language picker (`recommendations.feature`) are unchanged.

## User value and motivation

Today three prompts hard-code Simplified Chinese: `ModelClient.swift:130` "give a Simplified Chinese meaning", `:190` "explain the meaning and usage in Simplified Chinese", and `:196` "meaning is Simplified Chinese". That is right when reading English or Japanese. But the user also works in the "write Chinese, translate to English" direction: when a Chinese expression is saved, the model is asked to explain Chinese in Chinese and can only produce a roundabout meaning with the English equivalent mixed in, which is of no use for practicing English writing.

With the meaning language following the translation target, the meaning language at save time matches the language the user was practicing. This follows the same idea as [BDR-0003](../../settings/decisions/BDR-0003-translation-target-mapping.md): the direction follows the text, and the user does not have to maintain any state.

## Decision

### 1. Translation: meaning = this run's target language, strictly

Whether the expression comes from the source text or the translation, the meaning uses this translation's target language. After a Chinese-to-English translation, an English phrase saved from the translation gets an English meaning. English explained in English can happen, and that is accepted.

Rejected alternative "the opposite side's language" (explain in Chinese if the expression is English, and vice versa): it requires deciding which side of the translation pair an expression belongs to, which is unreliable when a fragment is picked by hand from the translation (the fragment may be mixed). "= target language" is a single rule with no judgment involved.

### 2. Polishing: look up the source language in the target mapping, falling back to the fallback target

Polishing has no target language (result language = source language), so it reuses the mapping and fallback target from BDR-0003: polishing English looks up "en → ?" and gets Chinese; polishing Chinese looks up "zh-Hans → ?" and gets English; a source language not in the mapping uses the fallback target (Chinese by default). No new setting is added.

Rejected alternative "polishing always uses Chinese": polishing Chinese would then get a Chinese meaning, which is useless for the writing direction and inconsistent with the translation rule.

### 3. Generation and regeneration both use the current mapping

The first meaning is generated in the language computed from the mapping at that time. Later, "Fill In Meaning" or regenerating in the notebook **still computes from the current mapping**, rather than reading the old language recorded on the entry. If the mapping changes, an explicit regeneration by the user switches the language. That is the outcome the user wants, since changing the mapping is exactly how they change the practice direction.

Entries still keep a language field, but it records **the actual language of the stored meaning**. It is used for display and for deciding "does this need regenerating", and is no longer an input to the request.

Not recomputing automatically is deliberate: re-sending requests in bulk whenever the mapping changes would make one settings change trigger N model calls, and partial failures would have to be handled. Instead, the detail offers a "regenerate with the current settings" entry, one entry at a time.

Saving from the history detail follows the same rule: a translation record's `language` is the target language, and a polish record's `language` is the source language. Each existing field happens to be exactly the one needed, so history does not need to store the source language as well.

### 4. No setting, no picker, no backfill

- No "meaning language" setting: already rejected when choosing among three options; a single global setting cannot serve two-way use. **Note**: the later "Native Languages" setting ([BDR-0012](BDR-0012-native-language.md)) is not a meaning language setting. It only decides which items study content includes and takes no part in computing the meaning language.
- The study area has no separate meaning language picker (the existing rule in `recommendations.feature` stays).
- Entries from before the upgrade are not backfilled: their content is untouched and their meaning language is recorded as Simplified Chinese, which matches their actual language.

## Consequences

- `spec/learning/features/definition-language.feature` (new): scenarios for the rules above.
- `spec/learning/features/recommendations.feature`: remove "in Chinese" from the polish study scenario.
- `spec/vocabulary/features/collection.feature`: remove "Chinese" from "Chinese contextual meaning" and "fill in the Chinese meaning".
- `spec/llm/contract.md`: rewrite the `meaning` language rule; the request must carry the meaning language, and validation can check the reply against the language tag.
- `spec/product.md`: rewrite "explained in Chinese".
- Terminology: drop "Chinese" from the definition of "study content"; extend the definition of "meaning" with the language rule (to be confirmed).
- Data: entries gain a meaning language field (`definitionLocale`, see `Owlet/Vocabulary/VocabularyEntry.swift`); old data defaults to `zh-Hans`.
- Implementation: the three prompts inject the language instead; `LearningRequest` already carries `targetLanguage`, and for polishing it now passes the language looked up from the mapping; `CollectionAction.fillMeaning` reads the entry field instead of a constant.

## Out of scope

- No meaning language setting.
- No language picker in the study area.
- No backfill of old entries.
- History does not store the source language as well.
