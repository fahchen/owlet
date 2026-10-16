# Changelog

User-visible changes to Owlet. Versions match `MARKETING_VERSION` in `project.yml`.

## Unreleased

### Added
- More protocols: besides OpenAI Compatible, choose OpenAI Responses, Anthropic or Gemini. The service list now has three groups: protocols, vendor presets, and local agents.
- The base URL is always editable, and each service remembers its own.
- Model Name and Reasoning Effort each take a typed value, with a "Presets" menu beside them listing the candidates. The effort row shows the value it sends (automatic, none, low, medium, high, max) rather than a translated level name; any other typed value is sent as is.
- A Test button checks the current settings: it translates the first line of the Classic of Poetry's 蒹葭 into English and shows the reply and how long it took. A model failure — from the Test or from reading the model list — is reported in one place, with a retry.
- The two System Prompts are shipped in every interface language: switch the language and a prompt you never edited switches with it, while your own edited prompt stays as you wrote it.
- The prompt editors' restore button reads "Restore Default" and asks for confirmation before discarding your edits.
- Service presets: pick DeepSeek, OpenRouter or Ollama, and Owlet fills in the base URL and default model. "OpenAI Compatible" stays for any other service.
- The Debug page lists each recorded request as a card: the heading starts with that request's own glyph, green when it worked and red when it failed, with the text that was sent below and the reason in red when it failed. Clicking a card opens `Response` and `Request` — JSON shown pretty printed — and the copy.
- Copy buttons say "Copied" for a moment after a press, in the Debug page, the result cards, the notebook, the history and the panel's notices, without the row moving as the word changes.

- About Owlet links to the project on GitHub.

### Fixed
- Back — and the Study shortcut — closes the learning column again. One state decides whether it shows, so a late reply can no longer keep it open.
- A reply whose sources differ from what was sent only by a space at a segment boundary is accepted. Models move or drop that space routinely and the pairing is still sound; a missing or reordered word still fails.

## 0.5.1 — 2026-10-15

### Changed
- The prompt editor sits inside the settings form. "Restore Default" is now an icon button that is always visible.
- New menu bar icon, drawn as a template image so the system colors it.

## 0.5.0 — 2026-10-14

### Fixed
- Owlet finds local agent CLIs no matter how it was launched. If it finds none, you can still set the path by hand.

## 0.4.0 — 2026-10-14

### Added
- Optional: when no text is selected, use the full text of the focused input field (off by default).

### Fixed
- In that mode, Replace overwrites the whole field instead of appending.

## 0.3.0 — 2026-10-14

### Added
- Local agent CLIs (Claude Code, Codex CLI) as model services. They need no API key.
- Pick the model and reasoning effort from the agent's own list.
- Each service remembers its own model name.
- Release builds for both universal and Apple silicon.

### Changed
- The glass effect setting points to System Settings instead of a custom control.

### Fixed
- Settings… brings an open settings window to the front.

## 0.2.0 — 2026-10-12

### Added
- Native language setting, with more than one language allowed. Learning suggestions skip your native languages.
- Changing the interface language takes effect at once, with no restart.

### Changed
- Definitions follow your current language mapping instead of the source language.
- Learn and Back buttons moved to the bottom left. Action buttons show the action's own icon and name.

### Fixed
- The floating panel leaves room for its action bar, so buttons no longer cover text.
- The word lookup popover no longer crashes when you press Speak.
- Mixed Chinese and English in status text, and other localization gaps.

## 0.1.0 — 2026-10-11

First build.

- Translate, Polish, Translate & Replace, and Polish & Replace with global shortcuts, in a Spotlight-style floating panel with Liquid Glass.
- Learning suggestions and a word book with readings, tags, and source app.
- ⌘-click word lookup with system speech.
- Local history, grouped by day and searchable.
- Any OpenAI-compatible service. The API key is stored in the Keychain.
- Interface in English, 简体中文, 繁體中文, and 日本語.
