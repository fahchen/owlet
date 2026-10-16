# Changelog

User-visible changes to Owlet. Versions match `MARKETING_VERSION` in `project.yml`.

## 0.6.0 — 2026-10-16

### Added
- More protocols: besides OpenAI Compatible, choose OpenAI Responses, Anthropic or Gemini. The service list now has three groups: protocols, vendor presets, and local agents.
- Presets for DeepSeek, OpenRouter and Ollama: choosing one fills in the base URL and default model, and the address stays editable — each service remembers its own.
- Model Name and Reasoning Effort take a typed value, with a "Presets" menu beside them listing the candidates. The effort row shows the value it sends (automatic, none, low, medium, high, max) rather than a translated level name, and any other value is sent as is.
- A Test button translates the first line of the Classic of Poetry's 蒹葭 into English and reports the reply and how long it took. Anything that goes wrong with the settings or the model is reported in one place, with a retry.
- The two System Prompts ship in every interface language: a prompt you never edited follows a language switch, while your own edited prompt stays as you wrote it.
- The Debug page lists each recorded request as its own card — the request's glyph, green when it worked and red when it failed, the text that was sent and the reason it failed. A card opens to `Response` and `Request`, JSON shown pretty printed, with a copy for the whole record and a Clear for the page. A failed status keeps what the service answered, and a long body scrolls inside its block.
- A failed request keeps the text of the last result on the page, with the failure under it: a retry that did not work no longer takes away what was already produced.
- The study column's waiting, empty and failed states are the system's own: a spinner while it works, a centred "nothing more to suggest" with a reason, and a failure with a retry.

### Changed
- Copy buttons say "Copied" for a moment after a press, without the row moving as the word changes.
- Failures read as a state of the page — the symbol, the message in a quiet inset block, then the way out — in the panel and in the window alike.
- The prompt editors' "Restore Default" asks for confirmation before discarding your edits.
- The hover tip is a rounded rectangle and shows up to twelve lines of a long selection.
- About Owlet shows the project's GitHub address as a link, and nothing else.

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
