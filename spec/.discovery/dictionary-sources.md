[English](dictionary-sources.md) · [简体中文](dictionary-sources.zh-CN.md)

# Discovery: Local Dictionary Lookup

Status: under design discussion (2026-10-11), not implemented. The user has confirmed that reading lookup is "local dictionary first; the AI in-context explanation is requested only after a manual click", and that translation learning adopts **B: automatically add local dictionary results after generation**. There is currently no ready-made offline dictionary; the choice of offline format is still to be confirmed, and choosing B for learning does not mean choosing MDX/MDD.

## Story / Actor / Value

A user who is reading can look words up in the system dictionary or in a local dictionary they imported, without configuring a model service; when they need to understand the original sentence, they request the AI themselves. After translation learning succeeds, supplementary content from the same local dictionary is provided automatically. Importing means choosing a file on this Mac; nothing is uploaded to a server.

## Decisions Made

- **Reading lookup is local first, AI is manual.** A lookup queries the local source first; a miss, a failure or a source switch must never automatically request the model. This rule does not change the existing learning switch or the learning generation flow.
- **Translation learning adds dictionary content automatically (B chosen).** Learning expressions that were generated successfully are automatically looked up in the currently selected local dictionary; the existing AI in-context meaning, recommendation reason and saving behaviour are kept. The dictionary result is a supplement, collapsed by default; the local lookup does not wait for a user click, and no extra model request is sent for the dictionary supplement.
- **No existing files yet.** The first version does not assume the user already has MDX or other files; the offline format is chosen explicitly first, then formal acceptance criteria are written.

## Automatic dictionary supplement for translation learning (B confirmed)

- [x] The local dictionary is queried automatically only after the existing learning flow successfully produces entries; when learning is off and not temporarily expanded, no extra learning content is generated. With no recommended entries there is no query.
- [x] AI recommendations and in-context meanings are shown first; copy, replace and save never wait for the dictionary. A dictionary miss or failure only affects the supplement area; it does not make learning generation fail and does not fall back to the model automatically.
- [x] Each expression keeps its main learning content; dictionary results are collapsed by default, and expanding shows the source, the original sense and any reading / part of speech available. The dictionary's own language does not change the language AI definitions use under BDR-0005.
- [x] Clicking a row still saves / unsaves it; expanding the dictionary, copying or retrying does not trigger saving. Saving still stores the original learning expression and its definition; the dictionary supplement does not overwrite stored fields.
- [x] Supplements for the same expression and the same source / version can be reused; expanding again does not re-request a lookup that is in flight or already obtained in this session; a new learning batch or a source change must not be overwritten by an old response.
- [x] A miss states "this dictionary has no result", and a failure can be retried on its own. No model configuration is needed to run the dictionary supplement, but generating learning recommendations still follows the existing model and switch requirements.

Confirmed acceptance examples:

1. The user turns on translation learning and a `bank` entry is generated: the AI in-context meaning and saved state appear first and the local lookup runs automatically; once the dictionary returns, all original senses can be expanded, with no new model request.
2. While the dictionary lookup is still running, the user copies the translation or saves the entry: the action runs immediately under the existing rules, without waiting for the dictionary and without writing dictionary content that has not arrived into the saved entry.
3. The entry is a phrase / whole sentence the dictionary does not contain: the AI learning content is still readable, the supplement area says nothing was found, and the entry is not cut down to another headword nor filled in by an automatic model request.
4. The user expands / collapses the supplement or copies dictionary text: the saved state does not change; a failed lookup can be retried on its own, and a late result only affects its original entry.
5. The user turns off translation learning and does not temporarily expand it: no learning entries are generated, and enabling the dictionary feature does not automatically request learning or batch lookups.

## Rules Discovered (proposed, to be confirmed)

- [ ] Keep the existing reading entry, selection and card; learning rows still save / unsave on click, editable areas still edit, and a lookup neither saves nor writes back.
- [ ] With no imported dictionary, default to "System Dictionary". The "Dictionary" group in settings can import and remove dictionaries and choose the default local source; the card can switch source, which only affects the current lookup and never silently changes the default. The first version queries one source at a time, with no merging of multiple dictionaries and no automatic round-robin.
- [ ] The card title keeps the actual query text and shows the source and the dictionary's original text. System sources are labelled "System Dictionary" uniformly; custom sources show the name and version from the package. Dictionary senses are not labelled "meaning in this sentence", and the card is not forced to show only one sense.
- [ ] Dictionary definitions stay in the dictionary's own language; they do not follow BDR-0005's AI target language and are not translated automatically. Readings that can be obtained are shown exactly as the dictionary gives them; base forms, parts of speech or phonetics are never invented.
- [ ] The card offers "Explain in context"; only a click goes through the existing AI lookup contract and BDR-0005 / 0006, sending the current query and its local context, never the whole dictionary. Dictionary content stays viewable; an AI failure does not affect dictionary results already shown.
- [ ] A miss clearly shows "this dictionary has no result", and the user can switch local source or click the AI action; the local dictionary can be queried even with no model configured. When a whole sentence has no entry, it is not shrunk to one of its words and passed off as the sentence's definition.
- [ ] When the system dictionary has no result, do not infer that the Mac has no dictionaries installed; offer "Open in Dictionary" to help the user check the system source. That explicit system app action is separate from Owlet's local lookup and cannot promise that everything in the system UI is offline.
- [ ] Import validates first, then builds a queryable copy; an available dictionary is not replaced before completion. Failure / cancellation leaves no partial result and does not modify the original file. The dictionary copy remains usable after restart; removing deletes only Owlet's copy, never the user's source file, saved words or history.
- [ ] The same file is not imported twice; replacing a version requires an explicit user choice, and a failure keeps the old version. Deleting the current default dictionary falls back to the system source with a clear notice.
- [ ] When language metadata is missing, let the user choose the headword / definition language or leave it unknown; never infer Japanese from the file name, extension or format. With an unknown language, definitions are still readable, but the TTS language is not guessed.
- [ ] Keep manual system TTS and do not call system speech the dictionary's original audio. Closing / switching the card or source stops the old audio; a missing usable voice does not block definitions.
- [ ] After a source switch, removal or version change, old responses do not overwrite new results or re-open the card; an old cache does not pass itself off as results from the new dictionary version. Esc, body focus, keyboard and VoiceOver keep the existing lookup boundaries.

## Examples (proposed acceptance examples)

1. No model configured, the system source matches `bank`: show "System Dictionary" and the dictionary's original senses with no model request; only choosing "Explain in context" prompts for configuration.
2. Looking up `bank` in a sentence about a river bank: the dictionary may list both the bank and river bank senses and must not automatically claim which one is meant in the text; after the user clicks the AI action, the in-context explanation is shown separately.
3. An English-English dictionary is imported and a word is looked up on a Chinese-to-English page: the dictionary still shows the English original; the AI explanation follows the definition language rules for that run.
4. After importing a supported text dictionary, look up offline: neither a model nor the original file path is needed; importing a corrupt package fails while existing dictionaries remain usable.
5. The dictionary has no entry for a whole sentence: show not found, without automatically shrinking the selection or going online; the user can request the AI explicitly.
6. Look up A, then switch source / look up B / remove the source: A's late result must not overwrite the current card; saved words and source files stay as they were.

## Open Questions

- [ ] Offline format: **A (recommended) the text subset of Yomitan v3 ZIP**, or **B dedicated MDX/MDD compatibility**. Ship only one first; do not implement several parsers at once.
- [ ] Should the card and source selection follow the single-source plan above, or aggregate several dictionaries at once? Single source first is recommended; aggregation is not a confirmed requirement for this round.
- [ ] Native verification: get at least one real successful result from the system API; verify offline lookup, long entries, focus / Esc and accessibility on the current system and on the minimum supported version.
- [ ] Limits on input, package size, total decompressed size, entry count and index resources are set before implementation; anything over the limit is rejected explicitly, without silently dropping entries.

## Relation to existing specs

- The first step of [BDR-0008](../vocabulary/decisions/BDR-0008-reading-word-lookup.md) excluded the system dictionary, and its card requires the AI in-context meaning. This feature is an explicit extension: dictionary senses and AI explanations are kept separate, and the local lookup does not go through the LLM response contract. Once confirmed, add a BDR that supplements / supersedes the corresponding scope instead of erasing the old decision.
- BDR-0005 / 0006 continue to govern AI explanations and the existing vocabulary supplements; "fixed definition language" and "no reading for whole sentences" are not imposed on raw dictionary content. The automatic dictionary supplement in learning is extra display and does not change the existing learning switch, recommendation generation or saved-data contract.
- The current term "definition" (释义) is limited to model output; proposal: add "dictionary sense: the original explanation provided by a local dictionary, which does not mean the app chose the in-sentence meaning". Update the [glossary](../glossary.md) once confirmed.
- At the time of writing, `Owlet/Lookup/` and the floating panel had uncommitted implementation work by other agents whose completion status was not checked; this round only added this file, did not adjust that implementation and did not close T47 to T51.

## Technical research (kept separate from product rules)

- Apple's public Dictionary Services returns plain text, not structured senses, readings or audio that can be reliably taken apart. The system dictionary source should not fake an AI response that satisfies `$defs.lookup`; reuse the selection, anchor, card container and system speech, while keeping content and caches separate per source.
- The public API requires `nil` for the dictionary parameter and does not promise enumerating or selecting a specific system dictionary such as Oxford; users manage system sources in Dictionary.app. Symbols the framework exports but does not document must not be treated as usable API.
- `DCSGetTermRangeInString` can expand to the longest word / phrase; do not use it to expand an explicit manual selection. A plain definition returned by the dictionary does not prove the right sense for the current sentence was chosen.
- Yomitan's public ZIP / JSON structure is suitable to evaluate first. The recommendation is that the first version accept only v3 term text definitions, keeping the term form, reading, definitions and source metadata, without claiming full compatibility. Unsupported definition content rejects the package with an explanation; importing half a dictionary and reporting success is not allowed. Dictionary CSS, scripts, images, external links and audio are not loaded. Missing language information requires user confirmation.
- MDX/MDD requires handling binary blocks, compression / encoding, HTML and resource relationships; evaluate it separately as another format option, without first building a generic dictionary engine.
- Imported copies / indexes may be persisted, but lookup history is not added because of them; result caches live only in memory. Caches distinguish at least source and version; AI caches still follow the existing context and model conditions and do not share success / failure state.
- The import boundary validates file structure, resource limits and in-package paths, and rolls back atomically on failure; dictionary content is never executed and download / update URLs are never followed automatically. A lookup does not load the whole dictionary's definitions into memory and does not build a large index on the UI thread.

## Sources and limits of evidence

- [Apple: Accessing Dictionaries](https://developer.apple.com/library/archive/documentation/UserExperience/Conceptual/DictionaryServicesProgGuide/access/access.html): returns CFString plain text; this archived document needs to be checked against the current SDK.
- [Apple: DCSCopyTextDefinition](https://developer.apple.com/documentation/coreservices/1446842-dcscopytextdefinition) and [Dictionary Services](https://developer.apple.com/documentation/coreservices/dictionary_services): the public API and the first matching definition.
- [Apple: Dictionary User Guide](https://support.apple.com/guide/dictionary/welcome/mac) and [Look Up guide](https://support.apple.com/en-md/guide/mac-help/mchl3983326c/mac): boundaries of the system source and the system Look Up UI.
- [Yomitan packaging notes](https://github.com/yomidevs/yomitan/blob/master/docs/making-yomitan-dictionaries.md), [v3 term schema](https://github.com/yomidevs/yomitan/blob/master/ext/data/schemas/dictionary-term-bank-v3-schema.json), [index schema](https://github.com/yomidevs/yomitan/blob/master/ext/data/schemas/dictionary-index-schema.json): format and optional language information.
- [StarDict official format](https://github.com/huzheng001/stardict-3/blob/master/dict/doc/StarDictFileFormat), [reverse-engineered MDX format notes](https://github.com/zhansliu/writemdict/blob/master/fileformat.md): the compatibility cost of other formats. Parser licences and dictionary content licences are separate matters; this design does not bundle, download or distribute third-party dictionaries.
- A read-only probe with the local 27.0 SDK got no definition for any of `apple / running / bank / 苹果 / 猫`; this neither proves the Mac has no dictionaries nor proves the integration works. A successful match, the native dictionary popover, offline lookup and running on macOS 26 are not yet verified.

## Next steps

Once the format and card behaviour are confirmed, turn the settled rules into features / BDRs for lookup and learning, and sync the product definition, dictionary settings and component mapping, and the [roadmap](../../docs/roadmap.md). First deliver a real successful path for the system dictionary, then reuse it for the learning auto-supplement and one offline format; do not interrupt the current AI lookup implementation work. The collapsed supplement in learning uses the native DisclosureGroup, and it must be verified that its actions and whole-row saving do not interfere with each other.
