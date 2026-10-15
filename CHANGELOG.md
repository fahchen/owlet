# Changelog

User-visible changes to Owlet. Versions match `MARKETING_VERSION` in `project.yml`.

## Unreleased

### Added
- Service presets: pick DeepSeek, Moonshot / Kimi, Zhipu GLM, Qwen / DashScope, xAI, OpenRouter, Ollama, or LM Studio, and Owlet fills in the base URL and default model. "OpenAI Compatible" stays for any other service.

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
