[English](BDR-0012-native-language.md) · [简体中文](BDR-0012-native-language.zh-CN.md)

# BDR-0012: Study content excludes native languages

Status: Accepted (2026-10-12), Implemented. Source: user request "study content should not include my native language".

## User value and motivation

The user's native language is Chinese, and they mainly use the app to practice English and Japanese. When translating Japanese into Chinese, expressions on both the source and translation sides may be recommended: the Japanese expressions are worth learning, while Chinese collocations are of no value to them. Rather than making them ignore these every time, they declare their native language once, and study content skips it from then on.

## Decision

### 1. A native language is the fact "a language I already know", not an exclusion list

In settings the user picks "Native Languages" (**multiple choice**, unset by default), meaning "these are my languages". Expressions in any chosen language are excluded from study content.

Multiple choice is allowed because a bilingual person has more than one native language: someone bilingual in Chinese and English should not have either explained back to them as study content. It is still not called "languages not to study", because a blocklist requires the user to think of every language they will not study in advance, while "which languages I know" is a fact they can state directly.

The candidate languages are only those the app uses (`SettingsStore.languages()`), not every system language.

### 2. Placed next to the mapping on the Languages page

The candidate languages are the target mapping and fallback target defined there, so keeping them together saves the user from cross-referencing pages.

### 3. Affects only study content, not the meaning language

The meaning language is still computed by [BDR-0005](BDR-0005-definition-language.md) (translation follows this run's target; polishing looks up the source language in the mapping). Native languages take no part in that computation. Otherwise "native = Chinese, translating into Chinese" would make the meaning language something other than Chinese, disconnected from the direction the user is practicing.

### 4. Study content for both operations is constrained

Translate: items on the native-language side are skipped (Japanese to Chinese with native = Chinese recommends only Japanese expressions).
Polish: the source and the result share a language, so native-language text **produces no study content**. In that case no request is made and no study entry is shown, which saves a model call; polishing non-native text recommends as usual.

### 5. Prompt constraint plus local filtering

The request tells the model not to recommend native-language expressions, and the reply is still filtered by `item.language` after it arrives. The model is not guaranteed to comply; local filtering guarantees the effect.

## Consequences

- `spec/learning/features/recommendations.feature`: new rule and scenarios for "study content excludes native languages".
- `spec/settings/features/target-mapping.feature`: new rule "native languages affect only study content" (placement, default, edge cases, persistence).
- `spec/product.md`: the study section adds the scope of native languages.
- Data: one new setting (native languages, empty by default).
- Implementation: items are filtered by native language when the study request is built; polishing native-language text is judged as "no study content".
