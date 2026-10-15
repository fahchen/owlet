[English](BDR-0009-learning-lemma.md) · [简体中文](BDR-0009-learning-lemma.zh-CN.md)

# BDR-0009: The study contract separates surface form and lemma

Status: Accepted (2026-10-11). Source: study recommendations from a real DeepSeek call failed with `.format`. The model returned the dictionary form, the context contained an inflected form, and the local verbatim match judged it a failure.

## Problem

The study contract's `text` was asked to do two things at once: be the expression saved to the notebook, and appear verbatim in `context`. In Japanese, a sentence contains the inflected form while the form worth saving is the dictionary form, and the two differ literally:

| `text` returned by the model | Actual form in the context | Verbatim match |
| --- | --- | --- |
| `跳ね上がる` | `跳ね上がっている` | ❌ |
| `史上最高値をつける` | `…をつけて` | ❌ |
| `拍車がかかる` | `…がかかっている` | ❌ |
| `受け渡し`／`現物`／`需給逼迫` | same form | ✅ |

`LearningResult.parse` uses `localizedStandardContains` for a literal check, so the whole study response was judged a `format` failure. The user saw "the returned structure does not match the contract" even though the main result itself was fine. Chinese and English noun phrases usually have the same form, so the defect reproduced reliably only when reading Japanese.

## Decision

- **`text` uses the form in the context.** `text` must be the literal text actually in this run's source or result (inflected and conjugated forms both count), and it must still appear verbatim in `context`. This keeps "which sentence, and where, this recommendation came from" verifiable, and preserves the boundary held since T48 that "the reply's correspondence to the request can be checked locally".
- **A new `lemma` field stores the dictionary form.** It is given only when the dictionary form differs from `text` and can be determined; otherwise it is `null`. The model is not required to force one when unsure, nor to give a base form for a whole sentence.
- **The notebook expression stays the form the user saved.** The entry's `expression` stores `text` (the inflected form), and `lemma` is stored as secondary information. The reasoning matches [BDR-0008](../../vocabulary/decisions/BDR-0008-reading-word-lookup.md): the lookup card uses the looked-up form as its title and the base form as secondary information, and a notebook entry does not change what the user saved at the time.
- **No local semantic check beyond "the form must appear in the context".** This is the defect actually fixed here: the old rule had smuggled "the base form must equal the surface form" into the shape check.
- **The rest of the contract is unchanged.** The meaning language, the `kind` values, `items` being allowed to be empty, and the same contract doubling as the meaning fill-in after a manual save all stay as they were.

### Alternatives rejected

- **Drop the verbatim check and keep only non-empty and shape checks.** Simpler, but it also loses the verifiability of "which sentence the recommendation came from". The rule that `context` must come from the source or result already had no local check, so dropping `text` too would leave only the shape. Rejected.
- **Change the prompt to force the inflected form and leave the contract alone.** It would pass validation, but the notebook would collect conjugated forms such as `跳ね上がっている`, and pronunciation and later lookups would all land on the inflected form. Rejected: it shifts the convenience of local validation onto the quality of the user's data.
- **Have the model give both forms, but put the base form in `text` and the surface form in a new field.** This contradicts the lookup card's "surface form as title", and what the notebook shows by default would differ from what the user actually saw. Rejected.

## Consequences

- `spec/llm/responses.schema.json`: `$defs.learning.items` gains a nullable `lemma`, listed in `required`.
- Study section of `spec/llm/contract.md`: the example adds `lemma`, and the division of roles between `text` and `lemma` is spelled out.
- `Owlet/LLM/ModelResponse.swift`: `LearningResult.Item` gains `lemma`; `parse` checks that the nullable field is not blank and does not duplicate `text`.
- `Owlet/LLM/ModelClient.swift`: the study and meaning fill-in prompts add a `lemma` description and example.
- `Owlet/Vocabulary/`: entries and context snapshots carry `lemma`; the notebook detail shows it as secondary text under the expression; export includes the field (`version` goes to 2).
- Follow-up: the base form on lookup cards and notebook entries is currently provided independently by the lookup request. The notebook's own `lemma` is used only for display and does not yet take part in lookups or reuse keys.
