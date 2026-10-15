[English](README.md) · [简体中文](README.zh-CN.md)

# Product Behaviour Spec

This directory is the entry point to the product spec of this project, based on the confirmed first-version requirements. The native macOS app is implemented in `Owlet/`, with tests in `OwletTests/` (Swift Testing) run by `mise run check`; the Gherkin scenarios are not yet bound to step definitions. The early browser prototype `design/` has been retired.

- [Product definition](product.md): scope, system support and user flows.
- [Design rules](DESIGN.md): native components, the system accent colour and a neutral glass interface (the rose brand colour was withdrawn on 2026-09-29).
- [Engineering spec](engineering.md): commands, structure, style, verification and boundaries.
- [Glossary](glossary.md): shared concepts.
- `processing/features/`: translate, polish, quick entry, replacement and toolbar error presentation.
- `learning/features/`: separate switches, on-demand expansion, collecting suggestions and the definition language.
- `vocabulary/features/`: manual collection, context, notebook management and editing; [word lookup, step one](vocabulary/features/word-lookup.feature) is implemented in all five areas (T48–T51) and awaits final acceptance.
- `history/features/`: saving, viewing, searching and deleting history; grouping by day and linking the entries collected from a record.
- `settings/features/`: user-supplied model service configuration, a [local agent CLI as the model service](settings/features/local-agent.feature), custom prompts, choosing the translation target by source language, per-language reading notation, the panel glass effect, and input focus in native windows.
- [LLM response contract](llm/contract.md): default prompts, JSON Schema and failure behaviour.
- [Screen region OCR input](../docs/screen-region-input.md): an unimplemented design proposal for an input source; it does not change the existing read path.
- [Continuous speech input](../docs/speech-input.md): an unimplemented design proposal for an input source; not in this round.
- [Streaming model output](../docs/streaming-output.md): an unimplemented presentation design proposal that changes only "when it is seen", not the request contract, local validation or write-back; whether it is built depends on a human decision about the replace entry UI.
- [Replacement behaviour decision](processing/decisions/BDR-0001-explicit-replacement-intent.md).
- [Error presentation decision](processing/decisions/BDR-0002-preserve-open-toolbar-on-error.md): an expanded toolbar stays expanded on error.
- [Translation target mapping decision](settings/decisions/BDR-0003-translation-target-mapping.md): the target is looked up from the detected source language, falling back when there is no row; polish and shortcuts are unchanged.
- [Editable notebook decision](vocabulary/decisions/BDR-0004-editable-notebook.md): meaning, expression, language, notes, tags and starred are editable; the meaning can be overwritten by regeneration, and notes are the user's safe zone.
- [Definition language decision](learning/decisions/BDR-0005-definition-language.md): the meaning follows this translation's target language, polish looks up the source language in the target mapping; generation and regeneration both use the mapping as it is now.
- [On-demand enrichment decision](vocabulary/decisions/BDR-0006-on-demand-enrichment.md): reading and part of speech are filled on demand in the detail; "Fill in missing" only fills empty fields, a single "Regenerate" overwrites only that field; whole sentences get neither; the reading notation is set per language.
- [History as a learning log decision](history/decisions/BDR-0007-history-as-learning-log.md): collected items record the entry point and the app the text came from; history is grouped by day, filterable by has-collected-items and source app, and the detail links the collected entries.
- [Reading lookup decision](vocabulary/decisions/BDR-0008-reading-word-lookup.md): ⌘-click in read-only text, or look up from the selection toolbar / context menu; study rows keep click-to-collect, old cross-sentence meanings are labelled with their source, system speech is manual only, and lookups are never stored. Implemented in all five areas (T48–T51), awaiting final acceptance.
- [Study word form decision](learning/decisions/BDR-0009-learning-lemma.md): the study contract's `text` uses the actual form in the context, with the dictionary form in `lemma`; the notebook collects by form and shows the dictionary form as secondary information.
- [Collect from lookup decision](vocabulary/decisions/BDR-0010-collect-from-lookup.md): the lookup card can explicitly "Add to Notebook", saving this lookup's form, context and meaning without another request; looking up alone still never adds to the notebook.
- [Interface language decision](settings/decisions/BDR-0011-interface-language.md): the interface supports Simplified Chinese, Traditional Chinese, English and Japanese, following the system by default and overridable in settings; language names follow the interface language, except in the picker; prompts sent to the model are not localized.
- [Native language decision](learning/decisions/BDR-0012-native-language.md): "Native Languages" in settings only affects which items study content includes (both operations are constrained) and plays no part in computing the definition language.
- [Local agent decision](settings/decisions/BDR-0013-local-agent-provider.md): Claude Code and Codex CLI, as a model service, act only as a one-shot plain completion backend, with tools, skills, MCP, project context and session persistence all off; replies still go through the same contract, and configuration completeness checks the executable instead of an API Key.
- [Glass intensity decision](settings/decisions/BDR-0014-system-liquid-glass-intensity.md): Liquid Glass and its intensity are adjusted centrally in System Settings › Appearance; the app's "Glass Effect" only chooses between two glass variants, with a one-line explanation and an entry that opens that pane, and offers no intensity control of its own.
- [Provider presets decision](settings/decisions/BDR-0015-provider-presets.md): `Provider` represents only the protocol and the two local agents; HTTP vendors are a data table, `ServicePreset`, and picking one fills in the public Base URL and default model; the response format capability follows the preset, and remembered models are kept per service.

Gherkin uses English keywords; scenario text is English in the `.feature` files and Simplified Chinese in the `.zh-CN.feature` copies. The examples are concrete illustrations drawn from the confirmed rules; they do not require fixed wording from the model and are not yet bound to step definitions. Unfinished work is in the [roadmap](../docs/roadmap.md); technology choices are not domain scenarios.

## Scope Boundary

Minimum macOS Tahoe 26.0; no review, sync, accounts, automatic collection, proficiency assessment or multiple polish versions. Technical constraints such as the Keychain stay in the product definition and the [engineering spec](engineering.md).

## Left to Be Decided During Implementation

- Shortcuts have no default combination and must be recorded by the user; the app is signed locally for personal use, without App Sandbox. The project is named Owlet.
- The concrete compatibility list of external apps that support reading and write-back; where unsupported, the defined manual input / copy behaviour applies.
- When a lookup card is open, Esc first closes the card and returns focus to the text; otherwise it closes the panel and cancels the in-flight request. The panel does not close on losing focus; a click outside the panel or "Done" also closes it. History records never regain write-back permission.
- The former implementation plan suggested UTF-8 JSON export and matching expressions after trimming leading and trailing whitespace only; these are implementation defaults and do not imply a requirement for morphological normalization.

## Matching Tasks

T numbers are historical task labels; the original task list has been deleted.

| Behaviour | Implementation tasks |
|---|---|
| Service configuration, translation | T01 |
| Quick entry | T02, T04, T03a |
| Safe replacement, direct replacement | T03, T03a |
| Polish | T04 |
| History | T05, T06 |
| Manual collection, notebook | T07, T08 |
| Study suggestions | T09 |
| Appending context for a repeated expression | T10 |
| Word lookup, step one (implemented, awaiting final acceptance) | T47–T51 |

## T59: Interface Language i18n with Four Languages (Implemented)

Based on [BDR-0011](settings/decisions/BDR-0011-interface-language.md). The user asked to "implement system i18n, supporting English, Simplified and Traditional Chinese, and Japanese", and allowed it to be split across several commits.

Later change: the interface source language is now English, the string table moved to `strings/translations.json` (keyed by English), and the `sourceLanguage` of `Owlet/Localizable.xcstrings` is `en`; prompts sent to the model are not localized. The acceptance record below is kept as it was at the time.

Scope and trade-offs: interface text and user-visible error messages go into `Localizable.xcstrings` (source language Simplified Chinese, plus English / Traditional Chinese / Japanese); prompts, task descriptions and examples sent to the model stay in Chinese; the interface language follows the system by default, can be overridden in settings, and takes effect on the next launch.

Acceptance:

- [x] `project.yml` declares `developmentLanguage: zh-Hans`; the four languages produce four `lproj` folders, `en / zh-Hans / zh-Hant / ja`, in the build.
- [x] The catalog is generated from the table in `scripts/build-strings.py`, and `mise run lint` checks that the two agree; tests assert that "every entry has all four languages" and that "the source language equals the key".
- [x] The "General" settings page offers "Follow System / 简体中文 / 繁體中文 / English / 日本語", written to `AppleLanguages` and applied before views are built; `AppLanguage.resolve` is a pure function covering four kinds of input.
- [x] Language names follow the interface language; the "Interface Language" picker is the exception and uses `Text(verbatim:)` to show each language in its own name.
- [x] "Choosing the recovery entry by failure type" no longer depends on message text: `ModelError.Kind` is extended to contract / connection / service, and `Notice.failure` and `TextProcessingModel.State.failure` carry it; `DebugExchange` carries `failureKind`.
- [x] `mise run i18n` lists untranslated interface strings based on the built `en.lproj`; it currently reports full coverage in all three languages (236 strings).

Verification: `mise run check` exits 0 with 345 tests passing; parsing the build output with Foundation itself, all four languages resolve the same set of keys correctly (`界面语言／生词本／翻译／润色／取消处理／加入生词本／查询／设置…` and two interpolated strings). `scripts/check-i18n.py` reports no gaps.

Known gap (not part of this task): `PanelControllerTests.opensWithNothingFocusedButTraversalStillReachesTheControls` occasionally fails in the full suite (five consecutive solo runs all pass); this is isolation fragility in window focus tests, to be handled separately.
