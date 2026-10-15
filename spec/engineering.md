[English](engineering.md) · [简体中文](engineering.zh-CN.md)

# Owlet Engineering Spec

Status: the native app is implemented; this document records the current engineering conventions. Product scope follows [product.md](product.md); no duplicate spec system is created.

## Goals and Scope

For a personal user whose native language is Chinese and who mainly reads and writes English and Japanese: translation, polishing, safe replacement and deliberately accumulating expressions. Other languages are supported; the first version has no review, accounts or sync. Confirmed interactions follow the product spec; the early HTML interaction prototype (`design/`) has been retired.

## Technical Constraints

macOS 26.0 and later; SwiftUI + AppKit, URLSession, SwiftData. Secrets are stored in the Keychain; ordinary configuration must never store a secret in plain text. The JSON contract is defined by `llm/contract.md` and is confirmed.

## Commands

```sh
mise run check    # lint + generate project + test; pre-commit and CI both run it
mise run format   # swift-format in place
mise run dev      # build and relaunch Owlet locally
mise run prod     # Release build, verified and packaged into dist/
```

The early browser prototype's `open design/index.html` and console checks (`checkDesignStates()`, `checkFlowBoard()`) were retired along with the prototype.

The project is generated from `project.yml` (XcodeGen); `Owlet.xcodeproj` is not committed. `mise run check` runs `git diff --check`, `swift-format lint --strict` and `scripts/build-strings.py --check`, generates the project and runs the tests; `mise run setup` installs the pre-commit hook, and CI also runs `mise run check`. `mise run prod` runs [scripts/prod-build.sh](../scripts/prod-build.sh) to produce a Release build: by default it builds both universal and arm64, signed as the project configures (`Signing.xcconfig`, which a machine can override with `Signing.local.xcconfig`), or with `--identity` / `--team` when given; before packaging it verifies the signature, minimum system version, icon and debug entitlements.

## Structure

- `Owlet/`: app sources, one directory per feature area (`App`, `Processing`, `Learning`, `Vocabulary`, `History`, `Lookup`, `Selection`, `Shortcuts`, `Settings`, `LLM`, `Debug`, and so on).
- `OwletTests/`: Swift Testing tests, mirroring the directories in `Owlet/`.
- `spec/product.md`, `spec/DESIGN.md`: product and visual decisions.
- `spec/{processing,learning,vocabulary,history,settings}/features/`: behaviour acceptance scenarios.
- `spec/llm/`: default prompts and the JSON contract.
- `docs/roadmap.md`: work not yet finished.
- No empty modules are created ahead of need.

## Code Style

Swift 6 with strict concurrency; standard Swift naming: types UpperCamelCase, members lowerCamelCase. Colours use only system semantic colours and the system accent colour (see [DESIGN.md](DESIGN.md)). The example shows the convention and does not imply an existing implementation:

```swift
struct TranslationSegment: Decodable {
    let source: String
    let target: String
}
```

Implement only the fields the current consumer needs; the fields above must be corrected to match the final JSON contract. Asynchronous operations must be bound to an operation identity; a cancelled or stale response must not update results or write back to the source text.

## Testing Strategy

Swift Testing verifies contract parsing, cancellation, write-back failures and data isolation; UI / accessibility use system integration tests and manual compatibility checks. Gherkin is not yet bound to a test implementation.

Fixed model responses cover success, network failure and invalid JSON; ordinary automated tests never call a real model. Write-back must cover missing permission, no owning app, cancellation and late responses. Deleting history must not affect collected entries. Study sends no request by default; it requests only after a click or once automatic requests are turned on.

No arbitrary coverage number is set; each high-risk behaviour above must have a matching test. Explicit checks against a real service happen only after configuration is complete.

## Boundaries

- Always: update the behaviour specs, validate model responses, protect the source text, run the matching verification and report what is still unverified.
- Ask first: changing the confirmed scope, the final JSON contract or the native technical approach; adding external services and dependencies.
- Never: commit secrets, write back late responses, collect automatically.

## Success Criteria

1. The four global shortcuts summon their operations; the menu bar opens the main interface, and the main interface has no button to return to the panel.
2. The first processing uses a compact notice; when the toolbar is not yet expanded, a blocker shows a compact notice with the matching entry; once expanded, retries and errors keep it expanded and the problem is shown in the content area.
3. Switching between section and sentence-by-sentence display sends no new request; copy and write-back output only the result.
4. Nothing is replaced without a reliable write-back target; cancellations and stale responses cannot write back.
5. Study is manual by default, and Translate / Polish can each turn on automatic requests; collapsing and expanding does not request again.
6. Collected entries and history are persisted independently; the Key is stored in the Keychain.
7. Neutral background; primary buttons, selection states and focus use the system accent colour; motion respects Reduce Motion.

## Confirmed

JSON fields and validation rules, SwiftUI + AppKit + SwiftData, the project name Owlet, no default shortcuts, selection fallback, and a resident menu bar icon plus a Dock icon: see [product.md](product.md) and `llm/contract.md`.

Signing and distribution are in [scripts/prod-build.sh](../scripts/prod-build.sh): without `--notarise` the artifact is not notarised, so the first launch on another Mac needs a right-click Open.
