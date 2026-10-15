[English](BDR-0007-history-as-learning-log.md) · [简体中文](BDR-0007-history-as-learning-log.zh-CN.md)

# BDR-0007: History as the learning log, saved entries record their origin

Status: Accepted (2026-10-04, pending implementation). Source: user request "I want to build my vocabulary notebook and learning log with this app", clarified that the "learning log" means history; later added "it could also record the source app".

Scope: what origin a saved entry records, and how history is grouped, filtered and linked to the notebook. The rules for saving history, deleting it, and "history does not hold write-back permission" are unchanged.

## User value and motivation

Today history and the notebook are two lists that know nothing about each other: when two words are saved from one translation, history does not know; when a word was met in Slack, the notebook does not know. The user reviews history as a learning diary ("what did I translate and learn that day"), and with these two threads disconnected the diary is only half there.

Once origins are connected, every word in the notebook has a source and can be filtered by "met in Slack"; every history record knows how many words it contributed, can be filtered by "has saved entries", and its detail jumps straight to those words.

## Decision

### 1. No new "learning log" entity

The user clarified that the learning log is history. Grouping, filtering and links are added to the existing history; no new model is introduced.

### 2. Saved entries record their capture entry point

Each context records which entry point it came from: text selection, study recommendations, or history. This answers "did I pick this word myself or did the model recommend it".

### 3. The source app is the app the source text came from, and it is carried along the chain

Selecting text in Mail triggers a translation, so history records Mail, and words saved from the study area or the history detail also record Mail. Manually entered text has no source app.

Rejected alternative "record the frontmost app only at the moment of saving a selection": most saves go through the study area, where the frontmost app at that moment is Owlet itself, which carries no information, so this column would be mostly empty.

Cost: history stores one more column. Owlet already reads the frontmost app when it reads the selection, so the cost is close to zero.

### 4. History is grouped by day, newest first

The group header wording is an implementation detail.

### 5. History can be filtered by "has saved entries" and by source app, combined with Translate / Polish

The combination rule matches the notebook filters ([BDR-0004](../../vocabulary/decisions/BDR-0004-editable-notebook.md)). The notebook also gains a source app filter, combined with language, tags and starred.

### 6. The history detail links to saved entries through a weak, one-way reference

The detail lists the entries saved from that record and can jump to the notebook. The link is a weak reference for display only:

- Deleting history does not delete entries (existing rule unchanged). The capture entry point and source app on an entry are still shown, because they are facts from the time of saving and do not disappear with history; they just can no longer jump back to history.
- Deleting an entry shrinks the list in the history detail accordingly.

Rejected alternative "a real foreign key with cascade": history can be cleared entirely while the notebook must survive, so the cascade direction contradicts that rule.

## Consequences

- `spec/history/features/learning-log.feature` (new): source app, grouping, filtering, links.
- `spec/vocabulary/features/collection.feature`: new Rule "saved entries record their capture entry point and the app the source text came from".
- `spec/vocabulary/features/notebook.feature`: filter by source app; origins are still shown after clearing history.
- `spec/product.md`: the matching sentences in the three sections on study content and saving, the personal notebook, and history are updated.
- Terminology: add "origin"; extend the definition of "history" with the link (to be confirmed).
- Data: contexts gain the capture entry point and source app; history gains the source app; a history-to-entry link key. See the SwiftData models in `Owlet/Vocabulary/` and `Owlet/History/`.
- Implementation: the selection reader already has the frontmost app; carry it through `TextProcessingModel` → `HistoryRecord` → `LearningRequest` / `VocabularyDraft`; add grouping and two filters to the history list; add an entry list to the detail.

## Out of scope

- No new learning log model.
- No cascade from history to entries.
- Do not record the frontmost app at the moment of saving from the study area.
- No per-app statistics or charts.
