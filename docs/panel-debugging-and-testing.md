[English](panel-debugging-and-testing.md) · [简体中文](panel-debugging-and-testing.zh-CN.md)

# Panel Debugging, Testing and Screenshot Notes

Recorded: 2026-10-07. Implementation commit: `cb2717d`. Scope is the floating panel; the main window study flow is unchanged, and General settings gains a panel glass effect choice.

## Design preferences captured

The general principles the user stated explicitly, and the specific panel requirements, have been moved into [visual and interaction rules](../spec/DESIGN.md) (section "Design tendencies confirmed by the user on 2026-10-07"): native components, checking component details, faithful font sizes and states, glass readability, alignment and whitespace, continuous transitions, instant saving, and verification with screenshots of real states. That section overrides conflicting panel descriptions from the old prototype and does not extend the scope of the main app.

## Check design components first, then change the implementation

The only layout source is [Figma artboard 6313:31216](https://www.figma.com/design/PL0seWKhVgNHzaHLFbWLaQ/macOS-27--Community-?node-id=6313-31216). Use computer use to select an instance, read the component name, variant, size and font in the Design panel on the right, and jump to the master to check. Do not guess components from how a screenshot looks, and do not use other pages as the layout source.

The instance-to-master table lives in [Liquid Glass component map](liquid-glass-components.md#t42-exact-artboard-component-check). Key findings this time:

- The status bar and the combined actions are a Segmented Control, not several Buttons assembled together.
- Standalone actions are native glass Buttons; save rows are borderless Buttons.
- Body text is 17pt regular with a design line height of 22pt; action icons are 13pt medium; circular buttons are 36pt.
- The panel is 773pt wide, the result is 257pt tall, and study is 295pt tall; body text and bottom actions share a 24pt boundary.
- Large Figma surfaces have a 34pt corner radius; the implementation uses the system default roundedRectangle and does not fully reproduce that radius.

## Verify behavior, layout and material separately

| Verification layer | Method | What it proves | What it does not prove |
| --- | --- | --- | --- |
| Behavior regression | Swift Testing, injected dependencies, isolated storage | Contracts such as cancellation, save toggling and settings persistence | Glass, hover, the feel of animations |
| State screenshots | Native preview + system window screenshot | Font sizes, boundaries, separation, the content of different states and static material | Real mouse clicks, animation continuity, the full app path |
| Interaction acceptance | Real window operation while unlocked, screen recording or UI automation | Hover, press, focus, window changes and animation | Screenshots alone cannot replace this layer |
| Model integration | The preview's `--live` | The current provider's responses and local contract validation | Stable regression with fixed responses |

`mise run check` runs lint, project generation and tests; it is not XCUITest or visual acceptance. This round did not complete XCUITest screenshots, real hover / press screenshots or animation recordings.

## Reproducible native preview

The tools are [panel-preview.py](../scripts/panel-preview.py) and [PanelPreview.swift](../scripts/PanelPreview.swift). They need macOS 26 and the Xcode toolchain; build output goes to `.build/panel-preview/` and is not committed.

```sh
# Show options
python3 scripts/panel-preview.py --help

# Interactive preview with fixed content and a mock model
python3 scripts/panel-preview.py

# Export seven states automatically; no computer use needed
python3 scripts/panel-preview.py --screenshots /tmp/owlet-panel-states

# Compare material on the same background; the background is a local file you provide
python3 scripts/panel-preview.py --screenshots /tmp/owlet-panel-states --background /absolute/path/background.png

# Only compare the active appearance of system controls
python3 scripts/panel-preview.py --screenshots /tmp/owlet-panel-active --active

# Render the General settings page off-screen; no screen recording permission needed
python3 scripts/panel-preview.py --settings /tmp/owlet-settings-pane

# Main window Notebook and History pages (a solid-color window placed behind, capturing only the main window) and the Languages settings page (off-screen), for the website
python3 scripts/panel-preview.py --app-shots /tmp/owlet-app-shots

# Translate Screen Region's 10 states, run one after another on the real PanelController / FloatingPanel and captured per window
python3 scripts/panel-preview.py --region /tmp/owlet-region-states

# Record the real PanelController / FloatingPanel transition from translating to result (.mov, about 4 seconds)
python3 scripts/panel-preview.py --transition /tmp/owlet-panel-transition.mov
```

Screen region (`--region`, BDR-0019): the capture, OCR, Screen Recording permission and model are all fixtures, so nothing touches the screen, Vision or a service. The screenshot is two lines of English drawn in the process, OCR returns those two lines, and the model answers in the requested target language, or stands in for a connection failure, a missing configuration or a malformed reply. It exports `01-permission`, `02-capture-failed`, `03-no-text`, `04-translating`, `05-result`, `06-result-aligned`, `07-result-zoomed`, `08-connection-failure`, `09-missing-config` and `10-format-failure` in turn. The Sentence by Sentence shot sets the display mode through the preview process's own UserDefaults, which are cleared at the end. Shots are taken per window with `screencapture -l`, so the screen has to be awake and the terminal needs Screen Recording permission; the preview process has no localisation resources, so the interface is English.

The transition recording uses the production expand path, with the mock model replying after a 1.5 second delay; split it into frames with `ffmpeg -i <mov> -vf fps=30 f%03d.png` and check frame by frame. The recording process ends on its own and the main thread does not wait for it, otherwise the animation would be blocked.

Lookup interaction (T48) uses the real controllers: `--panel` opens the real `PanelController` / `FloatingPanel` as an accessory app (an isolated suite pins the target to en); fixture lookups are delayed 1.2 seconds, and "frost" returns contract-violating content the first time to drive failure and retry; `--no-voice` simulates having no system voice; `--target ja|zh-Hans` changes the result language, and `--appearance dark|contrast|darkContrast` only changes the preview process's appearance; `--main` opens the main window's Text, Notebook and History pages with fixtures and in-memory storage. Synthesized mouse and keyboard events need the terminal to already have Accessibility permission; system appearance and voice settings are not changed.

The interactive preview switches with ⌘1–⌘5: processing, model not configured, connection failure, success, study. The preview window is fixed at 1030×550pt; the actual pixel size of screenshots changes with screen scaling.

Automatic export:

| File | State |
| --- | --- |
| `processing.png` | Translating, with the stop action |
| `missing-config.png` | Missing configuration, with the settings action |
| `connection-failure.png` | Connection failure, with the retry action |
| `success.png` | Result, with study / copy actions |
| `learning.png` | Two study columns, nothing saved |
| `learning-selected.png` | First entry saved |
| `learning-deselected.png` | First entry unsaved |

The last two are toggled by calling the production `CollectionAction.setCollected` directly, then checking membership in storage. They are state screenshots, not mouse-press screenshots, and do not cover the real click hit area. Waiting 1 second per state before the screenshot is a rendering buffer, not production loading time or an animation performance metric.

Off-screen export of the settings page (`--settings`): `GeneralSettingsPane` is put into a fixed 620×660pt canvas with `NSHostingView`, drawn into a 2x bitmap with `cacheDisplay(in:to:)`, then written as PNG; it opens no window and requests no permission, so it **does not need screen recording permission** (`--screenshots` still does). `ImageRenderer` rendered the same view on this machine as a **blank white image** (none of the `Form` groups, `Picker` or `Toggle` were drawn), so it was not used. Defaults are written to the isolated suite `dev.fahchen.owlet.panel-preview`, and the main app's settings are not touched before or after export; temporarily written keys are removed at the end. The settings page is a plain grouped `Form` with no glass surface, so off-screen drawing matches the window; the panel's Liquid Glass is composited by the window server, so this path **cannot** replace `--screenshots` for material acceptance. The Model pane (`settings-model-deepseek` / `-anthropic` / `-responses`) is exported after a real Test run: `ModelSettingsPane.runTest` goes through the real `ModelClient` and contract checks with a fixture transport that answers in each protocol's envelope after a pause, so the shown time and reply are measured, not typed in. The pane is given a fake key reader, so the export never reads the keychain (a stored key would stop it at a keychain prompt).

| File | State |
| --- | --- |
| `settings-general-off.png` | Light, the new switch in the Panel section off (default) |
| `settings-general-on.png` | Light, the same switch on |
| `settings-general-off-dark.png` | Dark, switch off |
| `settings-general-on-dark.png` | Dark, switch on |

The preview reuses production views but does not go through the full PanelController / FloatingPanel expand path, so static preview screenshots cannot be taken as acceptance of the real window spring.

### Isolating permissions, storage and keys

- Uses fixed source text, does not read the user's real selection, and does not request Accessibility or other permissions.
- Injects a mock ModelClient by default, so there are no real model calls; saving uses in-memory SwiftData.
- UserDefaults uses the separate suite `dev.fahchen.owlet.panel-preview`, isolated from the main app; that suite persists and is not cleared automatically on each launch.
- Preview options such as `--active` are only passed to the child process and do not change the system or shared test configuration.
- For a real integration run use `python3 scripts/panel-preview.py --live`, which reads `DEEPSEEK_API_KEY` from the existing process environment; do not put the value in commands, logs, docs or the repo. Regular regression needs no key.
- In this round real translation passed; the real study response failed structural validation and was handled as an error. This is not a successful study integration, and mock success screenshots cannot stand in for it.

## Lessons from screenshots and glass debugging

### Only system-composited screenshots keep the glass

AppKit `cacheDisplay` was tried, but the result missed the glass compositing and some button effects, so it cannot be used as evidence for material acceptance. The final approach:

```sh
/usr/sbin/screencapture -x -l <windowNumber> /absolute/path/state.png
```

The preview script takes the windowNumber from its own window, calls the system screenshot tool and checks the exit code. `--background` puts a reference background into the same preview window to compare how the glass treats the background, without changing the system wallpaper.

In this round computer use on this machine was unavailable while the screen was locked, but the window screenshots above still succeeded. So "computer use is unavailable" does not mean "every screenshot method is unavailable"; nor can this result be generalized to every machine, permission state, or XCUITest working while locked.

### One layer of glass, keep native controls

NSSegmentedControl uses momentary / fit; the cell's own border is turned off and a single surrounding glassEffect layer provides the material, which fixed the double background while translating. Standalone buttons keep the standard Button.glass, with no hand-drawn backgrounds, borders or custom ButtonStyle.

More transparent / higher contrast map to the system Glass.clear / regular, defaulting to regular; glass is not simulated with custom alpha.

Changing the layer the outer glass sits on, and switching to borderless + interactive glass, were both tried; screenshots did not show an improvement, and both were reverted. Do not treat experiment screenshots as evidence of the final implementation.

### Set icon color inside the label

Adding `.foregroundStyle(.primary)` only on the outer Button left the icons looking faint in this round's screenshots. Setting the system primary foreground on the Label inside the Button made the close and copy icons clearly darker, while keeping light/dark adaptation and the native glass style.

`--active` only overrides the preview's controlActiveState, to diagnose active / inactive colors; it is not real window activation, hover or press state, and it did not resolve every glass appearance difference the user raised.

### Checkpoints for layout and animation

- The right edge of the bottom buttons shares a 24pt inset with the body text; do not judge it by eye from the outer outline alone.
- The study divider is inset 24pt above and below; the save icon is vertically centered with the row content.
- The study translation uses a native NSTextField with justified paragraph alignment, the last line naturally aligned. Hyphenation was once turned on and produced many hyphens; it has been removed.
- SwiftUI content and the NSAnimationContext window use the same spring; with Reduce Motion they position directly. Continuity still needs confirming with a real window recording.

## Check commands and handling failures

```sh
mise run format
mise run check
mise run dev
```

Judge success by exit code, not just by grepping `error:`; Xcode's `Failing tests:` / `TEST FAILED` can slip through. The final implementation and the full checks in the commit hook all passed.

`mise run dev` once built successfully but `open` returned LaunchServices `-600`; that does not mean the whole command succeeded. After confirming the build succeeded, retrying with a new instance launched fine:

```sh
open -n .build/Build/Products/Debug/Owlet.app
```

Do not change source files while the preview's swiftc is compiling, or you may get "input file modified during build"; wait for compilation to finish, then edit and rerun. Avoid running several previews with the same bundle at once.

Regression coverage includes late results after cancellation, native control and separator sizes, isolated persistence of the glass setting, and repeated save toggling / deduplication / keeping other entries. A standalone AppStorage instance cannot replace a mounted SwiftUI view: the persistence test checks the value after reopening and is not grounds to claim cross-view instant refresh is tested.

## Still awaiting acceptance

- The difference between the Figma 34pt radius and the system default radius; follow the native component constraint and do not add a hand-written radius.
- Material feel, hover and press states of the bottom glass buttons in a real active window.
- Animation continuity of the real panel from processing to result, and from result to study.
- Visual combinations of dark mode with the system Reduce Transparency / Increase Contrast.
- The difference between the error segment text and the Figma red; the native NSSegmentedControl does not yet implement per-segment red.

Temporary screenshots are saved in `/tmp` and are not guaranteed to persist. This round's final icon screenshot directory is `/tmp/owlet-panel-icon-primary/`; for long-term reproduction regenerate them with the scripts above and record the system appearance, glass setting, whether `--active` was used, and the background source. T42 still awaits visual review; passing tests must not be written up as full design alignment.
