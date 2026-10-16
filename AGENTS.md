[English](AGENTS.md) · [简体中文](AGENTS.zh-CN.md)

# AGENTS.md

Repository conventions for Owlet. Product behaviour is defined in `spec/`; this file only says *how* to work, it does not restate behaviour.

## Commands

```sh
mise run check    # lint + generate the project + tests; run by the pre-commit hook and by CI
mise run format   # swift-format in place; run it after editing Swift, before check
mise run dev      # build and relaunch Owlet on this Mac
mise run prod     # Release build, verified and packaged into dist/ (universal and arm64 by default; version from project.yml)
scripts/local-check.sh   # same as check, but build products stay in this repository's .build/derived (optional)
```

`mise run check` writes build products to `~/Library/Developer/Xcode/DerivedData`; when temporary files must stay inside the repository, use `scripts/local-check.sh` (`lint` / `test` / both by default), which only adds a `-derivedDataPath`.

**Judge a result by its exit code, never by grepping the log.** `xcodebuild` failure lines look like `Failing tests:` / `** TEST FAILED **`; filtering for a lowercase `error:` misses them and reports red as green.

## Native components only

- The interface uses native macOS 26 SwiftUI / AppKit components throughout. **No hand-drawn controls**: no custom colours, tints, fills, borders, gradients, glows, shadows, corner styles or custom `ButtonStyle`.
- The full rules and how to judge them are in `spec/DESIGN.md`; the per-screen component map is `docs/liquid-glass-components.md`.
- Common patterns: pages use `Form` + `Section` (`.formStyle(.grouped)`); grouping containers, cards and list rows are system components; long text folds with `DisclosureGroup`; errors use `Label(systemImage:)` + system red; action rows use `PageFooter` + `.glass` / `.glassProminent`. **Do not draw rounded card backgrounds.**
- Before adding a screen, check the per-screen table in `docs/liquid-glass-components.md`, and add the new screen to it.

## SwiftUI inside AppKit containers

- `NSHostingController.sizingOptions = .preferredContentSize` makes SwiftUI **resize the window on every layout pass**. Only one arrangement is safe: put the hosting view inside a plain container view, make the **container** the window's contentView, and let the container observe `preferredContentSize` and size the window itself (see `Owlet/App/Panel/FloatingPanel.swift`).
- **Do not** set a hosting controller as `NSPopover.contentViewController` directly. The popover also positions and resizes itself, the two trigger each other and recurse until the stack overflows (measured at 6558 frames; pressing Speak crashed it): `NSHostingView.updateAnimatedWindowSize` ↔ `-[_NSPopoverWindow setFrame:display:]`. See `Owlet/Lookup/LookupPresenter.swift`.

## Versions

A release changes only `MARKETING_VERSION` (the version users see) and `CURRENT_PROJECT_VERSION` (a build number that increases with every delivery of the same version) in `project.yml`; `scripts/prod-build.sh` reads `CFBundleShortVersionString` from the product and uses it for naming and output. **Do not** add a VERSION file, and do not treat tags as a second source of truth. User-visible changes go into the Unreleased section of `CHANGELOG.md` with each commit; at release, rename it to the version and date. The website's changelog page is not committed: after a push to main, `.github/workflows/site.yml` renders it from `CHANGELOG.md` with `scripts/site-changelog.ts` and deploys it to Cloudflare Pages (owlet.fahchen.dev); preview locally with `mise run site:preview`. The Pages project, domain and deploy secrets are managed by the Terraform in `infra/` (`cd infra && mise run apply`), never edited by hand in the dashboard. If `MARKETING_VERSION` is removed, the script falls back to the commit hash and says so.

## Interface language

- **English is the source language** of the app: `strings/translations.json` is keyed by English and holds the Simplified Chinese, Traditional Chinese and Japanese translations; `Owlet/Localizable.xcstrings` is generated from it by `scripts/build-strings.py`. **Do not edit it by hand** (`mise run lint` checks that the two agree).
- Interface text **must** come from `L10n.shared.string("English key")` (views use `Text(L10n.shared.string(…))`). Do not use bare literals or `String(localized:)`: they resolve through `Bundle.main`, which is fixed once at launch, so they do not follow a language switch. Pass placeholders as explicit arguments (`L10n.shared.string("%@ · %@", a, b)`); **do not** put `\(...)` interpolation in a key, because the interpolation is evaluated first and no longer matches the key with `%@`; and do not interpolate a `LocalizedStringResource` into a string, which prints its debug description.
- Choose the placeholder by **argument type**: `%@` for strings, `%lld` for integers (`Int`, `.count`, `OSStatus`). `%@` only accepts objects; passing an integer gives the runtime error `does not match expected '%lld'`. `String(format:)` checks this, so do not guess.
- Text sent to the model (task descriptions and examples in `Owlet/ModelPrompts.json`) is **not localised**, and neither is it translated through the catalog. The two behaviour prompts are the one exception: they are read and edited on the Model page, so each has an entry per interface language (`translate.zh-Hans`, …; the bare key holds the English source), and an unedited prompt follows a language switch (BDR-0011).
- `mise run i18n` (needs a build first) lists interface strings that would show in Chinese after translation: it takes the product's `en.lproj` as the reference and compares it with Chinese literals in the source. Run it after adding interface text, so no gap reaches users.

## Spec first

- A behaviour change lands first in `spec/{processing,learning,vocabulary,history,settings}/features/*.feature`; trade-offs are written up as `spec/settings/decisions/BDR-*.md` (status "Accepted / Implemented").
- After implementing, update `spec/product.md`, the root `README.md` and `docs/roadmap.md` (items waiting for acceptance, unverified items, unbuilt designs and proposals live only there).
- New work gets an entry in `docs/roadmap.md` with its acceptance conditions and how it will be verified; remove the entry once it ships and is verified. User-visible changes go into `CHANGELOG.md`.

## Documentation language

- `docs/`, `README` and `AGENTS` are bilingual with English as the default: `foo.md` is English and `foo.zh-CN.md` is its Simplified Chinese copy, and the first line of each links to the other. Change both together; their content must match. Links in an English document point to English files; links in a Chinese copy point to `.zh-CN` files where one exists.
- `spec/` is written in Simplified Chinese only, with no English copy. Its Gherkin `.feature` files use English keywords with Chinese scenario text and must parse with the official Gherkin parser.
- Code comments (including documentation comments) are always in English; interface text still goes through `L10n` as described under *Interface language*.

## Model calls

- `spec/llm/contract.md` is a hard constraint: structure, target language and source concatenation are all validated locally, and a reply that fails validation must never be treated as a success or written back.
- Contract failures must be diagnosable: `ModelError` distinguishes `format` / `targetMismatch` / `sourceMismatch`, and the raw request and reply are recorded on the hidden Debug page (`Owlet/Debug/`, controlled by the Debug switch in Settings; off by default, in memory only, never holding the API key).
- `Provider` only names the protocol and the two local agents; differences between HTTP vendors go through the capability flags of `ServicePreset` (`Owlet/Settings/ServicePreset.swift`) and reach the request via `ServiceConfig.supportsJSONSchema` (for example, DeepSeek supports `json_object` but not `json_schema`). Adding a vendor means adding one row of preset data, not a `Provider` case.

## Swift and tests

- Swift 6 with strict concurrency; types are UpperCamelCase, members lowerCamelCase; no template comments at the top of files.
- Tests use Swift Testing (`@Test` / `#expect` / `@Suite`) with `@testable import Owlet`.
- Everything that depends on external state must be injectable: `UserDefaults(suiteName: "…")`, `ModelClient(transport:)`, and `read` / `write` / `makeWindow` on `PanelController`. Tests must never read the developer's real settings or call a real model.
- Comments say *why*, not *what*; if one sentence says it, use one sentence.

## Commits

- Conventional Commits, with the body in Chinese; one commit does one thing.
- Never commit secrets; API keys live only in the Keychain. Keys must never appear in debug output or logs.
- `mise run check` must pass before committing (the pre-commit hook runs it again).
