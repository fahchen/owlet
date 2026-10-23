[English](icloud-sync.md) · [简体中文](icloud-sync.zh-CN.md)

# iCloud Sync

Status: design proposal, not implemented. Sync is listed under "Not in the first version" in [the product definition](../spec/product.md) (`:124`); this proposal moves sync — not accounts — out of that list, and needs a BDR plus a settings page. Nothing here is built.

## What exists today

- One SwiftData store holds the notebook and history: `VocabularyEntry`, `VocabularyContext` and `HistoryRecord` share a container ([VocabularyStore.swift:149](../Owlet/Vocabulary/VocabularyStore.swift), [HistoryRecord.swift](../Owlet/History/HistoryRecord.swift)).
- The notebook's uniqueness is a database constraint, `#Unique<VocabularyEntry>([\.language, \.expression])` ([VocabularyEntry.swift:7](../Owlet/Vocabulary/VocabularyEntry.swift)), backed by app-level lookup ([VocabularyStore.swift:23](../Owlet/Vocabulary/VocabularyStore.swift)).
- Settings are `UserDefaults`; the API key is in the Keychain. Nothing touches the network except model requests.
- Signing is ad-hoc by default ([Signing.xcconfig](../Signing.xcconfig)); there is no entitlements file. A machine can opt into a team in the ignored `Signing.local.xcconfig`.

## The chosen mechanism

**SwiftData with a CloudKit private database** (`ModelConfiguration(cloudKitDatabase:)`, which runs on `NSPersistentCloudKitContainer`), plus **`NSUbiquitousKeyValueStore`** for a whitelist of settings.

| Alternative | Why not |
| --- | --- |
| Custom CloudKit records | Full control over merging, at the cost of writing a sync engine; the dataset is a single user's notebook. |
| A file in the iCloud Drive ubiquity container | One file, no record-level merge: two devices writing at once lose one side wholesale; history and notebook would need a custom file format and full-rowname conflicts. |
| Third-party sync services | Adds an account, a dependency and a server the app does not need; the user asked for iCloud. |
| No sync, manual export/import | Already possible via the existing export ([VocabularyExport.swift](../Owlet/Vocabulary/VocabularyExport.swift)); does not meet the request. |

CloudKit's private database is reachable only by the user's own iCloud account. It is encrypted in transit and at rest by Apple; it is **not** end-to-end encrypted, and the settings text must not claim otherwise.

## What syncs

| Data | Syncs | Why |
| --- | --- | --- |
| Notebook entries and their contexts | Yes | The point of the feature. |
| History | Yes (decision 1) | Same store; keeping it out means splitting containers. It also means clearing history on one Mac clears it everywhere. |
| Settings whitelist | Yes, via key-value store (decision 2) | Target mapping, language subset, native languages, display mode, custom prompts, and later word blocks are user-authored content. |
| API keys | **No** (decision 3) | They stay in the Keychain, per device. A sync of secrets is a different risk class. |
| Shortcuts, panel position, interface language, debug switch | No | Device-local choices; a shortcut can be right on one Mac and taken on another. |
| Lookup cache, debug records, selection text | **Never** | The existing privacy rule: these live in memory and are never written anywhere. |

## CloudKit's price on the model

- `#Unique` is not supported. The database constraint goes; the app-level lookup that already prevents same-device duplicates stays. Two devices that collect the same expression while offline can still create two rows.
- Every attribute needs a default value (they do today) and relationships must be optional where CloudKit requires it; the exact to-many requirement is to be checked against the SDK before implementation.
- Each entry gains a UUID attribute. `persistentModelID` is not stable across stores, and a deterministic winner is needed for duplicate merging.
- Existing stores must migrate when sync is first enabled; the migration and the upload of rows that existed before sync must be verified on a real device pair.

## Consent and states

- The setting is **off by default**. Turning it on explains exactly what leaves the Mac (notebook, history if enabled, the settings whitelist), and that Apple stores it in the user's private iCloud.
- Sync needs a build signed with a team entitled to iCloud. An ad-hoc build cannot sync; the page reports "Sync is not available in this build" instead of failing silently. Whether an app carrying the iCloud entitlement launches correctly when ad-hoc signed is to be verified; the entitlement must be switchable by signing configuration so ordinary local builds stay unchanged.
- iCloud account missing or restricted: the page says so and points to System Settings; local use continues untouched.
- Changing the toggle requires a relaunch, because the `ModelContainer` is chosen at launch. Turning sync off stops syncing, keeps local data, and does **not** delete the private database copy (decision 5).
- Sync status is read from CloudKit's account status and the persistent store's sync events; the page shows last-sync state and errors without blocking the notebook.

## Conflicts

- SwiftData + CloudKit resolves a record by last-write-wins per field. That is acceptable for a single user's two Macs: the newer meaning or note wins, older text is not merged.
- Duplicate notebook rows (same language and expression) are possible. They are not deleted automatically: two devices can each decide to keep a different row, and both deletes would propagate until nothing is left. The notebook instead offers a **Merge Duplicates** maintenance action with a deterministic winner (earliest `createdAt`, tie-broken by UUID): contexts are unioned using the existing same-content rule ([VocabularyContext.hasSameContent](../Owlet/Vocabulary/VocabularyEntry.swift)), then the losers are deleted. The action is user-initiated, shows how many pairs it found, and never runs on its own (decision 4).
- Identical contexts arriving from two devices are shown once and merged by the same action.
- History is append-only; concurrent appends coexist. Clears and deletes do propagate.

## Settings through the key-value store

- KVS is a small mirror, not the source of truth: `UserDefaults` stays authoritative locally, and whitelisted keys are written through on change and read on launch.
- Last-write-wins per key, which matches the existing "same setting on both Macs, newest edit lives" expectation. There is no merge UI.
- The store has a hard size limit (1 MB per app); the whitelist today is far below it. Limits are checked before writing, and a value that would exceed them fails visibly instead of being truncated.
- Keys that are not on the whitelist are never read from or written to KVS, so a future setting does not start syncing by accident.

## Integration seams

- `VocabularyStore.makeContainer()` is the one place that chooses the configuration: local by default, cloud when the setting is on and the build is entitled. Tests keep building in-memory containers and never touch CloudKit.
- A small `SyncStatus` observable (account status, enabled, last event) is injected into the settings page; UI tests use a fake.
- KVS sits behind a `SettingMirror` seam with the whitelist in one place, so tests never read the real ubiquitous store.
- The merge action lives in `VocabularyStore` beside the existing collection logic, with the winner rule in one function that tests can drive.

## Decisions for the human

1. **History.** Sync it too (recommended, it is the same store and the same consent), or keep it device-local by splitting stores.
2. **Settings whitelist.** Sync user-authored settings (recommended), or start with the notebook only and add settings later.
3. **API keys.** Per device (recommended), or synchronizable Keychain items so one Mac can use the other's key.
4. **Duplicates.** Manual Merge Duplicates (recommended), or automatic merging with a deterministic winner.
5. **Turning sync off.** Keep the private database copy (recommended), or offer a separate "Delete iCloud data" confirmation.

## Must be verified on real hardware

- A signed build with the iCloud capability, two Macs on the same iCloud account: first enable, upload of pre-existing rows, edits, deletes, and a duplicate created offline on both.
- Whether an ad-hoc build carrying the entitlement launches, and what CloudKit reports; the settings text depends on it.
- Migration of the existing store when sync is first turned on, with a backup taken first.
- KVS latency and conflict behaviour between two Macs.
- iCloud storage growth with a realistic history.
- Sync events while the Mac is offline and after reconnection; the page must not claim "synced" when it is not.
