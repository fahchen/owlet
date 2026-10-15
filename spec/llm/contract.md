[English](contract.md) · [简体中文](contract.zh-CN.md)

# System Prompt and LLM Response Contract

Status: JSON fields, validation rules and custom prompt requirements confirmed (2026-09-27).

## User Settings

Translate and Polish each have their own System Prompt; Translate and Replace reuses the translation prompt. The editor always shows the prompt currently in effect (the built-in default when not customized). At the end of the title row is a "Restore Default" icon button in a fixed position; it is disabled when the editor content equals the built-in default of that operation, and otherwise clicking it fills the editor back with the built-in default. Restore Default applies only to its own operation. Blank content cannot take effect. The default texts live together with each task's instructions and examples in `Owlet/ModelPrompts.json` (shipped in the bundle, read by name in code); translations into Chinese and other languages are in `strings/translations.json`.

The settings window has no page-level Save button: each editor commits when it loses focus (every setting applies immediately). A commit affects only later requests, never requests already sent, existing results or history. Restore Default first fills the editor, and takes effect once committed.

## Request Composition and Fixed Format

The app uses the user's chosen prompt as behavioural guidance and appends the fixed response contract, the current operation, the target language and the context. The source text goes in a separate data message and is never concatenated into the System Prompt. The user prompt cannot lift the JSON structure, source matching, target language or safe write-back constraints.

Only one complete JSON object is accepted, with no extra fields. When the whole message is wrapped in exactly one Markdown code fence (optionally tagged `json`), the fence is removed before parsing; any explanatory text outside the fence, multiple JSON objects, or the need to extract a fragment all count as a format error. The JSON is parsed from the content of the model message; the vendor's HTTP response envelope is not this contract.

Services that support structured output may be constrained with a response schema. The schema sent to the vendor drops keywords it does not support (such as `minLength`, which OpenAI strict mode does not support), and the dropped constraints are still validated locally. Other compatible services (such as DeepSeek, which supports only `json_object`) are asked for JSON through an explicit prompt, and the exact same local validation still applies. After a validation failure the raw text must never be written back as a fallback. Vendor-specific format parameters are decided from each vendor's documentation during native integration.

Reasoning effort is a user-controlled request parameter and not part of this contract. The app offers unified levels (automatic / off / low / medium / high / max), mapped per model to the `reasoning_effort` that model accepts: the level table comes from the vendor documentation, a level the model does not support falls to the nearest lower level, models that take no reasoning parameter (such as gpt-4o) do not get the field, and unknown models get the value as is. The default (automatic) sends nothing and leaves it to the vendor and model; whatever the value, it must not relax the JSON structure or the local validation above. DeepSeek takes `none` / `low` / `high` / `max` and folds `medium` into `high`.

## Translate and Polish Results

Validated against `$defs.result` in [responses.schema.json](responses.schema.json):

```json
{
  "source_language": "en",
  "target_language": "zh-Hans",
  "segments": [
    {"source": "Good morning. ", "target": "早上好。"},
    {"source": "Let's begin.", "target": "我们开始吧。"}
  ]
}
```

- Languages use BCP 47 tags, such as en, ja, zh-Hans; there is no fixed list of languages.
- Each segment is the source and result of one semantic sentence group; a group may hold several sentences when needed, and the two languages are not assumed to have the same number of full stops.
- Concatenate all `source` values in order and compare with the submitted source: both sides are first normalized to Unicode NFC, then runs of whitespace (spaces, tabs, newlines) are collapsed to a single space and leading and trailing whitespace is trimmed; the results must be equal. Separators belong to their segment; nothing is realigned by the number of displayed lines. The relaxed comparison affects validation only; copy, replace and history all use the concatenated `target`.
- Concatenating all `target` values gives the full result for copy, replace and history. The model should keep appropriate spaces / newlines at the end of segments; the app inserts no extra spaces. This requirement is written into the default prompt; it cannot be validated reliably on device and is covered by multi-sentence fixed-response tests.
- A translation must return the requested target language; a polish must return the source language as its target. Language tags compare only the primary language subtag; Chinese also compares the script (`zh-Hans` / `zh-Hant`; `zh-CN` and `zh-SG` count as Hans, `zh-TW` and `zh-HK` as Hant, and no script counts as Hans). `en` and `en-US` are treated as equal. None of this guarantees the semantic quality of the model output.
- A single segment's `source` and `target` must not be blank. A polish with no changes may have both equal.
- The main response contains only the result and the pairs, no study suggestions. Source and polished result are each shown as plain text without diff markup; when study is on, changes worth learning are explained there.

## Study Content

A study request uses the behavioural context of the matching translate / polish prompt, plus the study task and the `$defs.learning` contract. It is made only when study is on or explicitly expanded this time; the main result is shown / written back first and never waits for study to finish.

```json
{
  "items": [
    {
      "text": "take a step back",
      "language": "en",
      "kind": "phrase",
      "meaning": "退一步重新审视；适合在讨论中建议换个角度。",
      "context": "Let's take a step back.",
      "lemma": null
    }
  ]
}
```

`text` is the actual form in this source or result: copy it from whichever sentence uses it, including inflected and conjugated forms, and it must appear verbatim in `context`. `lemma` is given only when the dictionary form differs from `text` and is certain (for example Japanese `text` `跳ね上がっている` with `lemma` `跳ね上がる`); when they are equal, not applicable or unknown it is `null`. A dictionary form is not required for whole sentences, and `text` must not be repeated just to fill the field (see [BDR-0009](../learning/decisions/BDR-0009-learning-lemma.md)). `meaning` uses the definition language the request specifies: for translation, this operation's target language; for polish, the source language looked up in the target mapping, with the fallback target when there is no row; enrichment and regeneration after manual collection compute the definition language from the mapping as it is now (see [BDR-0005](../learning/decisions/BDR-0005-definition-language.md)). Reading and part of speech are filled by a separate on-demand request: it carries the expression, language and reading notation and returns `pronunciation` and `part_of_speech`; "Fill in missing" requests only the empty fields, and a single "Regenerate" requests only that field; whole sentences never trigger this request (see [BDR-0006](../vocabulary/decisions/BDR-0006-on-demand-enrichment.md)). For polish, this is where the reasons for improvements are explained, distinguishing grammar errors from style preferences. `context` must come from this source or result. Items are not padded; `items: []` is allowed. The same contract is used to fill in meanings after manual collection, and turning study off never prevents the user from collecting on their own.

## Reading Lookup

Lookup uses its own `$defs.lookup` and reuses the existing model client, vendor capabilities, local validation and hidden debug page; it does not extend the study suggestion response. The behaviour is based on [BDR-0008](../vocabulary/decisions/BDR-0008-reading-word-lookup.md).

The request carries the actual looked-up text, the local context captured by the app with the relative selection range, any known text language hint, and an explicit definition language and reading notation. The context covers the whole selection; when there is no source sentence, the absence is stated explicitly and no sentence is invented. The looked-up text and the context go in the data message as `{"text", "context", "selection_start", "language"}`, where `context` / `selection_start` / `language` may be `null`; the definition language and reading notation are written in the system message. The dictionary form is not a required input, and no extra model request is made to look up the cache.

Length limits (set in T48): the looked-up text is at most 300 characters (counted as Swift `Character`s). Beyond that, "Look Up" is unavailable and explains "The selection is longer than 300 characters; shorten it to look it up"; the selection is never truncated. The local context is the whole sentences the selection touches; beyond 1200 characters it becomes a 1200-character excerpt centred on the selection that fully contains it. A selection of only whitespace or punctuation cannot be looked up.

Validated against `$defs.lookup` in [responses.schema.json](responses.schema.json):

```json
{
  "text": "running",
  "language": "en",
  "definition_language": "zh-Hans",
  "meaning": "在这句话中指正在跑步。",
  "lemma": "run",
  "pronunciation": "ˈrʌnɪŋ",
  "part_of_speech": "动词"
}
```

- Every field must be present. When the text language is unknown, `language` is `null`; a dictionary form, reading or part of speech that does not apply or is uncertain is `null`. Non-null strings must not be whitespace only, and extra fields are not accepted.
- `text` must match this lookup's text, using the NFC and whitespace-collapsing comparison above. The relative range must match the actual looked-up text in the local snapshot; the range and source are kept by the app, and a source generated by the model is never trusted.
- `definition_language` must match this request, using the language tag comparison above. The definition language follows BDR-0005, while the text language is identified separately; the two must not be merged. When the text language is known, a non-null returned language must match it too; a contradiction or a missing known language is a format error.
- With a source sentence, `meaning` explains only the in-context meaning, with any necessary usage; without one it gives the general meaning and the card shows "No source sentence". A list of senses is not required.
- A dictionary form is provided only when applicable and certain. The reading notation follows the per-language rules of BDR-0006. Whether the text is a whole sentence is judged by the model; for a whole sentence `pronunciation` and `part_of_speech` should be `null`, and the app makes no whole-sentence judgment of its own and does not validate on that basis (confirmed in review 2026-10-11). System TTS reads the actual looked-up text and never reads the phonetic field; JSON validation cannot guarantee that the sense, dictionary form or reading is correct.
- Structural errors are `format`, a wrong definition language is `targetMismatch`, and a mismatch with the looked-up text or the local selection is `sourceMismatch`. `format`, `targetMismatch` and `sourceMismatch` all get one correction first, as described above (a missing nullable key, and a meaning written in the text's own language, are the two most common causes). The existing request / response diagnostics are reused, and the API Key is never recorded.
- Exact reuse depends on the looked-up text, the local context, the relative range, the definition language, the reading notation, the version of the model / request configuration that affects the result, and the known text language; case is preserved and no secrets are included. A cross-sentence candidate must have a real source context, the same known text language, the same form and the same explanation settings; the old source is shown and the app waits for the user to explicitly look up again, never passing it off as the current sentence's result. A general explanation without a source sentence is reused only exactly, under the no-context condition.
- Only a capacity-bounded in-memory record is kept. Identical in-flight requests are merged; a failure is kept as an explicitly retryable state and never cached as a success. A late response cannot overwrite a newer lookup or reopen a closed card; a failed re-query still keeps the usable old meaning and its source. Lookup itself never writes to the notebook: a failure affects only the card and never changes the text or the processing result. Only when the user explicitly chooses "Add to Notebook" in the card is an entry written from this result (see [BDR-0010](../vocabulary/decisions/BDR-0010-collect-from-lookup.md)).

## Local Agent as a Service

A local agent (Claude Code, Codex CLI) is just "another way to reach a model service": for each request the app starts a process, asks for one answer, and ends it. It does not act as a coding agent: tools, skills, MCP, project context and session persistence are all off, and the working directory is a throwaway empty directory (Codex does not read the user's configuration, so its MCP servers are not connected and user hooks do not run). See [BDR-0013](../settings/decisions/BDR-0013-local-agent-provider.md).

Request and delivery are two layers. `ModelRequest` (model name, system prompt, a number of user / assistant turns, response format, reasoning effort) is the app's single request value; `ModelBackend` is the delivery: an HTTP service builds an OpenAI-style body from it and POSTs it, and a local agent translates it into arguments and standard input. The behavioural prompt and the fixed contract are delivered through each agent's channel (a system prompt argument, or combined with the source text over standard input). **The user's source text always goes through standard input, never through command-line arguments** (`ps` shows them to other processes on the same machine).

An agent that can constrain the shape gets the same schema as above: Codex through `--output-schema`, Claude Code through `--json-schema`. Services that only support `json_object` (such as DeepSeek) have no such switch, and the shape is carried by the prompt. Local validation, the corrective retry and "never fall back to writing the raw text after a validation failure" are the same for every provider.

A local agent's answer is the text the process prints, with no response envelope around it: truncation and refusal exist only in the HTTP service envelope, and empty output is treated as empty content. Failures count as connection failures: not executable, a non-zero exit and exceeding the timeout all report that the local agent failed to run, along with that agent's own error output (standard error first, falling back to standard output when it is empty). Cancelling must end the child process, and late output must never be written back. The debug page records the actual command line and prompt (the command line never contains the source text anyway) and the model's raw reply; records never contain any secret.

## Failure Handling

When the vendor truncates for a length limit (such as `finish_reason: "length"`) the app shows "The result was cut off for being too long."; when it refuses on content policy (such as a `refusal` field or `finish_reason: "content_filter"`) it shows "The service refused to process this text.". Neither is treated as a format error, and neither is written back or saved as successful history.

When JSON parsing fails, fields are missing or of the wrong type, the result is empty, the source concatenation does not match, or the target language does not match, the app shows that the reply does not match the required format, keeps the source and allows a retry. It never copies the model's raw reply as the translation, never replaces, and never writes successful history. Do not extract the first curly-brace fragment with a regex and pass it off as a valid response.

When a study or lookup response does not qualify, the app asks once more: the second request includes the model's own rejected reply and the specific rule it broke, so the model fixes only what needs fixing. Correctable failures are structure mismatch, source concatenation mismatch and target language mismatch: each can be explained in one sentence. Truncation, refusal, empty responses and transport errors are not contract failures and do not trigger the correction; a reply that is not even a JSON object gets no correction either, since there is no rule to point at. The correction happens once only; if the corrected reply still does not qualify, the original error is handled as usual. Both round trips are recorded on the debug page, with the title marked "(corrected)".

A study JSON failure affects only the study area and can be retried on its own; the main result already received stays usable. Even if a custom user prompt asks for non-JSON, these boundaries do not change.

## Current Implementation Scope

Translate / polish and study have a Swift model client with local validation; remaining work is listed in the [roadmap](../../docs/roadmap.md). The lookup request, decoding and local validation are implemented (`ModelClient.lookup`, `LookupResult`), with the panel result as the first consumer (T48). The reading notation is read at request time from the per-language configuration in the "Languages" settings group (`SettingsStore.pronunciationSystem`); when the text language is unknown, the model uses each language's default. The study contract's `lemma` is implemented; the definition language is computed from the current mapping, and the entry records the language of the stored meaning (T53, see [BDR-0009](../learning/decisions/BDR-0009-learning-lemma.md) and [BDR-0005](../learning/decisions/BDR-0005-definition-language.md)).
