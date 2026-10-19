[English](README.md) · [简体中文](README.zh-CN.md)

# Owlet

Owlet is a menu bar app for macOS 26 and later. It translates and polishes selected text, keeps a personal notebook of the words and phrases you save, and keeps a history of what you processed. It speaks the OpenAI Chat Completions, OpenAI Responses, Anthropic Messages and Gemini protocols, with built-in presets for common vendors, or works with a local agent CLI (Claude Code or Codex CLI).

- Website: https://owlet.fahchen.dev
- Downloads: [Releases](https://github.com/fahchen/owlet/releases)
- Changes: [CHANGELOG.md](CHANGELOG.md)
- What is still open: [Roadmap](docs/roadmap.md)

## Docs

- [Product definition](spec/product.md)
- [BDD behaviour specs](spec/README.md) (the specs are written in Chinese)
- [Visual and interaction rules](spec/DESIGN.md)
- [Liquid Glass components](docs/liquid-glass-components.md)
- [Panel debugging, testing and screenshots](docs/panel-debugging-and-testing.md)
- [Selected text capture](docs/selected-text-capture.md)

## Production build

A verified Release build, packaged into `dist/` (git-ignored) by [scripts/prod-build.sh](scripts/prod-build.sh):

```sh
mise run prod                       # universal and arm64 zips
mise run prod -- --arch arm64       # this Mac's architecture only
mise run prod -- --team Z98NKJSF69  # sign with that team explicitly
```

The script builds, verifies the bundle id, minimum macOS, icon, signature and the absence of `get-task-allow`, then packages with `ditto` and prints the SHA-256. Artifacts are named `Owlet-<version>-<arch>.zip`. The version is `MARKETING_VERSION` in `project.yml` (currently `0.7.0`); see `scripts/prod-build.sh --help` for all options.

Builds are not notarised, so another Mac needs a right-click Open on first launch. An ad-hoc build also loses its Accessibility grant on every rebuild; a certificate keeps it. Copy with `scp` or `rsync`, not AirDrop, to avoid the quarantine flag.

## Development

```sh
mise run setup    # install tools and the pre-commit hook
mise run dev      # build and relaunch Owlet locally
mise run check    # lint + generate the project + tests
mise run format   # format Swift sources
mise tasks        # list every task
```

Repository conventions are in [AGENTS.md](AGENTS.md).
