[English](liquid-glass-components.md) · [简体中文](liquid-glass-components.zh-CN.md)

# Owlet · macOS 26 Liquid Glass Component Map

> T33 current component map (supersedes the workspace, notebook and history layouts in the old screenshots below): the design prototype only expressed layout; the real interface uses system components throughout. `design/` has been retired; the screenshot list below is kept as a historical record and does not represent the current interface.

| Page | Native components and current behavior |
| --- | --- |
| Translate & Polish | Native `.toolbar`: in the middle a `SwiftUI-hosted NSSegmentedControl (momentary / fit)`, on the right the run `Button`; system SF Symbols and `.help`. Source and result use `GroupBox`; the title and the language `Picker(.menu)` share a row, with the language aligned right. |
| Study (shared by the workspace, history and the panel) | `PanelLearningView`: the study button in the bottom-right corner expands it and requests on demand; each entry is a full-row button, and clicking toggles saving immediately (bookmark icon, accent color when saved), with a hover background. No separate explanation-language setting. |
| Notebook | Native split view, `List(selection:)` and a detail scroll area, each scrolling independently; the toolbar groups search and filter, with delete on the right. No export, copy or edit buttons. |
| History | Same split view with search and filter; study and delete on the right. Study opens the study section for that record's result; checked items are added to the notebook. No copy or edit buttons. |

Do not imitate the HTML's rounded corners, chevrons or icon-button look, and do not define a custom `ButtonStyle`; native components decide appearance and accessibility.


Status: the retired `design/index.html` had 66 states (matching `design/screenshots/`), all corresponding to features implemented in `Owlet/`, with design and implementation in agreement; the only exception is `success` (write-back confirmation), which keeps the old screen. Unimplemented items are listed in [docs/roadmap.md](roadmap.md). The comparison covers every visible component in the screenshots; the goal is to replace each with a macOS 26 (Tahoe) native SwiftUI / AppKit component, with no hand-drawn controls and no custom colors, corner radii, borders, gradients or shadows.

## 1. Two criteria
**Criterion 1: Liquid Glass belongs to the functional layer, not the content layer.** Liquid Glass only belongs to the control and navigation layer that floats above content (toolbars, sidebars, panels, popovers); the content layer uses system materials and never stacks glass. `materials.md › Liquid Glass`: **Don't use Liquid Glass in the content layer.**

**Criterion 2: if a system component exists, do not build a custom one.** System components automatically get the Liquid Glass look, `Reduce Transparency` / `Increase Contrast` / `Reduce Motion` adaptation, vibrancy, focus rings, and keyboard and VoiceOver support; a hand-built equivalent gets none of these automatically. `liquid-glass.md › Where the material belongs`: **Use Liquid Glass effects sparingly.**

Corollaries (the three this project is most likely to break):

- Pick button styles by layer. In the implementation every action button uses `.glass` / `.glassProminent`, including toolbar icon buttons, status-recovery entry points in the content area, the footer action bar and the floating panel. "Use `.bordered` / `.borderedProminent` in the content area" is a stricter recommendation that has not been adopted; see §2.2.
- No glass on glass, and a limited amount of it: keep the glass surfaces on one screen within "the few most important functional elements".
- One prominent action per screen, placed at the trailing end (`buttons.md › Style`: **Keep the number of prominent buttons to one or two per view.**; `toolbars.md › Actions`: **Use the `.prominent` style for key actions such as Done or Submit.**).

## 2. This design update

The update does only two things: replace the window skeleton with the system skeleton, and replace the controls with system controls. None of the information structure, states or available actions in the design was removed; what was removed is duplication and empty copy. The sections below split by "do design and implementation agree".

### 2.1 Landed (design and implementation agree)

| # | Change | Before | Now | Basis |
| --- | --- | --- | --- | --- |
| 1 | The sidebar is a real source list | Fixed 178px column that drew its own traffic lights and group headings, with a custom white capsule for selection; `Settings` and `Local` pinned to the bottom | `NavigationSplitView` + `List(selection:)`: the collapse/expand button in the toolbar comes from the system (the toggle in the design is this one); `Show/Hide Sidebar (⌃⌘S)` is provided by an explicitly added `SidebarCommands()` (T25); selection uses the system look; `Settings` moved into the same group, no longer pinned to the bottom; the `Local` badge was removed; `.badge` counts not adopted | `sidebars.md › Best practices`; `sidebars.md › Desktop (macOS)`: **Avoid putting critical information or actions at the bottom of a sidebar.** |
| 2 | The top-right Translate / Polish and target language become toolbar controls | Two hand-drawn dropdowns squeezed into a 64px self-drawn title bar | Toolbar of the `NavigationSplitView`: the `Simplified Chinese` pop-up button on the left, the `Translate｜Polish` segmented control on the right; `Copy` and the submit action stay in the bottom safe-area action bar and were not moved up (§2.2 #6) | `segmented-controls.md › Best practices`; `pop-up-buttons.md › Best practices` |
| 3 | Panel floating glass redone, error entry becomes a button, focus ring handed to the system | Two gradient layers + four inner shadows + double stroke; error recovery was a rose underlined link; a `2px` rose outline offset by 4px | Default appearance of the system `NSGlassEffectView` (default corner radius, regular variant), with no self-drawn border or drop shadow on top; the glass is wrapped in a container masked to the same corner radius, so the `NSPanel.hasShadow = true` shadow follows the rounded corners instead of casting a rectangle from the square frame; recovery entry points become `.glass` buttons (`StatusNote`, `CompactNoticeView` and the panel action row); 3px accent glow + accent stroke | `liquid-glass.md › Review checklist` #2: **Restraint.** "Glass stacked on glass blurs the hierarchy the material was meant to create."; `buttons.md › Content`: a button must be recognizable as a button at a glance; `focus-and-selection.md`: **Rely on system-provided focus effects.** |
| 4 | Settings page becomes an inset grouped form | A full-width divider under every row | Grouped rounded container + in-row dividers; the container ends with its group | `boxes.md › Best practices`: **Consider using padding and alignment to communicate additional grouping within a box.** |
| 5 | State overview grouped by window / panel | 16 swim lanes by flow, joined by arrows | 9 horizontal sections by surface (Translate & Polish 12 / Notebook 4 / History 3 / Settings 14 / compact bar 10 / direct-replace compact notice 6 / study expressions section 5 / expanded 10 / menu bar 2); sections stack vertically, and states within a panel wrap horizontally | Prototype tooling; grouping shows all states of a surface at once, matching the map in this document |

### 2.2 Recommended but not adopted at the time

Neither `design/index.html` nor `Owlet/` adopted the following recommendations at the time; they are kept as design input for later work (see [docs/roadmap.md](roadmap.md)). Rows that have since been implemented say so.

| # | Recommendation | Basis | Implementation status |
| --- | --- | --- | --- |
| 6 | Remove the bottom action bar and move actions into the toolbar | `windows.md › Desktop (macOS)`: **Avoid putting critical information or actions in a bottom bar…** | The `.safeAreaBar(edge: .bottom)` bottom action bar is kept (`Translate Text` / `Copy` / `Save Settings`). |
| 7 | Stop drawing shortcut hints inside buttons | `toolbars.md › Desktop (macOS)`: **Make every toolbar item available as a command in the menu bar.** | The source label still reads `⌘ V Paste`, and the bottom of the panel still has a `Shortcut not set` / `Esc Cancel` hint row. |
| 8 | Buttons use bare verbs | `writing.md › Best practices`: **Build language patterns.** | Still `Translate Text` and `Save Settings`; the object stays in the button. |
| 9 | Breathing full border while processing | `motion.md › Providing feedback`: **Aim for brevity and precision in feedback animations.** | Only `ProgressView`; the glass bar edge does not breathe (T24). |
| 10 | Responsive two-column text processing page at 720pt | `layout.md › Adaptability`; `split-views.md › Desktop (macOS)` | Implemented: `ProcessingLayout.choose(width:)` uses 720pt as the threshold, side by side when wide enough, stacked otherwise; screen `workspace-narrow`. |
| 11 | Settings becomes a separate `Settings` window | `settings.md › Desktop (macOS)`: **Include a settings item in the App menu.** | Implemented: settings is a separate `Settings` scene (opened from the App menu and ⌘,), and the main window sidebar no longer has a settings page (T19); details in §6. |
| 12 | Remove hint text from the panel action row; put `Save Selection` at the leading end | `layout.md › Visual hierarchy`; `writing.md`: **Be action oriented.** | The hint text is still there; `Save Selection` was removed, and saving now happens by checking items in the study section (screens `learning` / `saved`). |

### 2.3 Copy rules (once proposed; adopted by neither design nor implementation)
1. **Action areas hold only actions.** No explanatory text in toolbars or action rows; status is carried by the content area, `.help()` or the menu bar.
2. **The interface does not show shortcuts.** The only places shortcuts appear are the menu bar (`.keyboardShortcut`) and hover tooltips (`.help()`); do not draw `⌘↵` into buttons, and do not write "Shortcut not set".
3. **Buttons use verbs; leave the object to context.** When other controls on the screen already state the object (the segmented control already has "Translate" selected), the button does not repeat it; keep the object only when it would be ambiguous, for example `Restore Default` in settings. Use one name per action: `Copy` is always `Copy`, never `Copy Translation` in one place.

## 3. Component map overview

Ordered by Apple HIG component categories (<https://developer.apple.com/design/human-interface-guidelines/components>); only things that actually appear in the 66 states are listed.

### 3.1 Components › Layout and organization
- Main window skeleton (sidebar + content) → `NavigationSplitView` + `List(selection:)` + `.listStyle(.sidebar)`; no `TabView` on desktop; dividers are the system's own, never a self-drawn 1px vertical line; the sidebar itself, `Section` groups and selection are handled by the `List` sidebar appearance and the system source-list selection; show/hide uses the system sidebar toggle toolbar item + `⌃⌘S` (`sidebars.md`: **Consider letting people hide the sidebar.**); settings sections use `Form` + `Section` (`.formStyle(.grouped)`), and settings is a separate `Settings` window, see §6.

### 3.2 Components › Menus and actions
- Top toolbar → `.toolbar { ToolbarItem(placement:) }` + `.navigationTitle`, spanning the whole window above the sidebar; `Simplified Chinese` → `Picker(.menu)`, `Translate｜Polish` → `SwiftUI-hosted NSSegmentedControl (momentary / fit)` (segment labels are nouns); `Translate Text` / `Save Settings` / `Copy` in the bottom action bar → `.glass` / `.glassProminent` + `.keyboardShortcut(.return, modifiers: .command)`, with the object kept in the button (§2.2 #8); the panel header (Retry / Settings) and bottom action row (`Copy ⌘⇧C` / `Replace ⌘↩` / `Cancel`) use `Button(.glass)` wrapped in a `GlassEffectContainer`, and the hint text is still there (§2.2 #7); the always-present menu bar icon uses `MenuBarExtra` + `Menu` (`the-menu-bar.md`: **Display a menu — not a popover — when people click your menu bar extra.**).

### 3.3 Components › Navigation and search
- Sidebar navigation (Translate & Polish / Notebook / History) → `List(selection:)` bound to `enum Page`; Shortcuts and Debug (when the debug switch is on) are tabs of the settings window, and the "Global / In Panel" groups on the Shortcuts page use `Form` + `Section`; the notebook and history `List`, toolbar search and filter, in-row delete, and the list → detail hierarchy have all landed.

### 3.4 Components › Presentation
- Floating toolbar window → `NSPanel` (`.borderless`, `.nonactivatingPanel`, `.floating`) + `NSGlassEffectView`; the glass is drawn by the window server, keeps its default corner radius and style, and gets no self-drawn border or inner shadow; the window's `contentView` is a container masked to the glass corner radius, so the `hasShadow = true` shadow follows the glass shape (it is also needed to tell the overlay's edge on light backgrounds); the compact processing bar (`loading` / `polish-loading` / `direct-loading`) uses the same glass container + `Text` + `ProgressView` + a glass stop button; the breathing full border is a recommendation that was not adopted (§2.2 #9, T24).
- Compact notice bar (failure / permission / not configured / cancelled / could not write back) → same container + `Label` + one recovery button, with an extra retry icon button for failures (see §7 exception 1); in the expanded state the inline status row (`result-notice`) puts `Label(systemImage:)` + a recovery button into the content flow without collapsing the panel; the permission onboarding uses `AXIsProcessTrustedWithOptions` to open System Settings rather than a self-drawn dialog.

### 3.5 Components › Selection and input
- Source input → multi-line `TextEditor`, single-line `TextField(axis: .vertical)`, with the focus state handed to the system focus ring; service settings use `TextField` / `SecureField` / `Picker(.menu)` inside `Form` rows (`entering-data.md`: never prefill passwords; `pickers.md`: use a pop-up button for short lists); the shortcut recorder has **no system component**, so the implementation uses `Button` + `.glass`, switching to `.glassProminent` while recording, with registration through Carbon / `NSEvent` (§7 exception 2); the `⌘ V Paste` / `⌘ ↵` / `Esc` hints are kept in both design and implementation (§2.2 #7).

### 3.6 Components › Content and status
- Translation / polish result → `Text` + `.textSelection(.enabled)` with semantic font sizes (`labels.md`: **Make useful label text selectable.**); section label rows use `LabeledContent` or a `Section` header + `.secondary`; the processing skeleton uses `.redacted(reason: .placeholder)` on the real content instead of hand-drawn gray bars.
- Processing indicator → `ProgressView().controlSize(.small / .mini)` + status text; the status text carries the state apart from the animation (the breathing full border was not adopted, T24); inline notices use `StatusNote` (`Label` + recovery `Button`) for in-place feedback; the study section, notebook and history (`learning*`, `saved`, `book-*`, `history-*`) reuse the same set of system components.

### 3.7 System experiences
- Always-present menu bar entry → `MenuBarExtra` + `Menu` (`the-menu-bar.md › Menu bar extras`); no system API offers a "user-recordable" UI for global shortcuts, so registration uses Carbon `RegisterEventHotKey` (§7 exception 2); the app icon is set by `ASSETCATALOG_COMPILER_APPICON_NAME` in `project.yml` (current value `AppIcon`, i.e. `AppIcon.appiconset` in the catalog; it has no `appearances` entries, so the intended light / dark / tinted variants do not exist yet, see [docs/roadmap.md](roadmap.md)).
- Owlet mark in the menu bar → monochrome rounded square base with a cut-out owl head and facial silhouette; `Image("OwletMark")` + `template-rendering-intent: template` / `.renderingMode(.template)`, tinted with `.primary` to follow the system appearance.

## 4. Screen-by-screen map

Same grouping as the "state overview" of the retired `design/index.html`: 9 sections stacked vertically (the app window's Translate & Polish, Notebook, History and Settings; the floating panel's compact bar, direct-replace compact notice, study expressions section and expanded state; and the menu bar), 66 states in total. Apart from `success`, which keeps the old screen, every screen corresponds to an implemented interface in the app.

| Screenshot | System components already in the design |
| --- | --- |
| `workspace*.png` (result, empty input, with input, processing, polish result, request failure, service not configured, sidebar collapsed) | Sidebar toggle · `TabView` along the top edge of the content area (`Tab(title, systemImage:)`, with margins all round) · two `GroupBox`es in each pane (separated by background, no divider lines; the title slot holds controls: a `Picker(.menu)` for the source language on the source side, and a "Translation / Study" segmented control on the result side; the target language `Picker(.menu)` is inside the result group) · two separate glass icon buttons floating at the bottom-right of the content (`Copy Result`, `Translate` / `Polish`, replaced by `Cancel` while processing; `.labelStyle(.iconOnly)` + `.help()`, not wrapped in a `GlassEffectContainer`, see §2.2) · `TextEditor` · `.redacted` placeholder in the result area · inline `StatusNote`; both sides are visible at once and scroll independently (a wide window splits the width evenly left/right, a narrow window splits the height evenly top/bottom), and study expressions follow below the translation/polish; this page has no bottom action bar |
| `settings-shortcuts.png` / `settings-shortcuts-recording.png` / `settings-shortcuts-conflict.png` | Shortcuts page of the settings window: two `Section`s of a `Form` (`Global` recorders / `In Panel` fixed keys) · recorder button (exception 2) · `Clear` · each group's footer carries the explanation and conflict notice |
| `settings-general.png` | Separate settings window: title bar of the `Settings` scene + `TabView` tab switcher (not customizable, always visible) · several `Section`s of an inset grouped `Form` on each page; the General page has a "Text" group (Translation Display) and a "Panel" group (Glass Effect `Picker`, with a secondary `Text` line + system `Link` below it pointing to "System Settings › Appearance", see BDR-0014; `Toggle` "Use the whole text of the focused field when nothing is selected", off by default, see T69); the Shortcuts page is one toolbar tab |
| `settings-language-empty.png` / `settings-language-rows.png` | Languages page: "Languages" group (one `LabeledContent` row + delete button per selected language; the full system list only appears via `Add Language`) + "Target Language" group (fallback target `Picker(.menu)`, one mapping row per source language, `Add Mapping`) |
| `settings-model.png` / `settings-model-openai.png` / `settings-model-agent.png` / `settings-model-failed.png` / `settings-model-prompts.png` / `settings-model-prompts-customized.png` | Model page: "Service" group (Provider, Base URL, `SecureField`), "Model" group (Model Name, Reasoning Effort), and two System Prompt editor groups; a model failure — from reading the list or from the `Test` — appears once, on the error row at the end of the Model group, with a `Retry` (BDR-0016 §10). The trailing end of each editor group's title is a native button labelled `Restore Default` with an `arrow.counterclockwise` icon (`Label(_:systemImage:)` + `.buttonStyle(.borderless)` + `.controlSize(.small)`): it always sits in the same place, is `.disabled` when the editor content equals the built-in default, and clicking it restores that editor to the default prompt for its operation, which is the one in the current interface language — an editor the user never edited follows a language switch. The editor follows the grouped `Form` row instead of drawing its own surface: the system `.textEditorStyle(.plain)` + `.scrollContentBackground(.hidden)` remove the default white background and inset block, so the row background shows through (T73). The Provider `Picker(.menu)` has three sections (BDR-0016). The first is the protocols: `OpenAI Compatible` (custom; you fill in the address and model yourself), `OpenAI Responses`, `Anthropic` and `Gemini` (choosing one writes the protocol owner's address; you fill in the model). The second is the vendor presets `DeepSeek`, `OpenRouter`, `Ollama (Local)` (BDR-0016 §6); choosing one writes its public Base URL and default model, and both stay editable in place afterwards. The third is the local agents, with a separator between sections; **local agents are always listed**, those not found are marked "not detected", and once selected you can still `Choose…` an executable by hand in place; a hand-picked path is not overwritten by later scans (T61, T71). `settings-model-agent` is the same page for a local agent: Base URL and `SecureField` are replaced by a `LabeledContent` executable row + two buttons `Detect` / `Choose…` + the detection result shown in place (the version, or a failure reason such as "%@ was not found. Choose its executable by hand, or install it and press Detect."), and the footer says no API Key is needed; Model Name and Reasoning Effort are each one `LabeledContent` row of a plain `TextField` plus a `Menu` button labelled `Presets`, all system appearance: the field takes any value and the menu lists the candidates (BDR-0016 §8). The model list comes from the selected protocol's model endpoint, from Codex's own listing command, or from Claude Code's cached catalog; when none can be read the list is empty and the field still takes a typed name, and an empty field on a local agent means its own default model (T62, T66). The effort menu lists the raw values (automatic, none, low, medium, high, max) and the field shows the value it sends rather than a translated level name; a typed value outside the list is sent as-is, and an empty field means the provider's own default. Under them, a `Test` button (`bolt.horizontal`) translates the first line of 蒹葭 and shows its state on the button itself (a spinner while running, then a check or a red warning icon and "Test · 1.32 s"); a passing reply sits on its own row below. Each service remembers its own model name and Base URL, and switching back restores them (T67) |
| `settings-debug.png` / `settings-debug-open.png` / `settings-debug-empty.png` | Debug page: one `Section` of a grouped `Form` (title "Recent Requests", footer saying it is in memory only, at most 20 entries) + system `DisclosureGroup`, one row per exchange (the indicator, animation and accessibility state all come from the system); a leading status icon (system red for failure, secondary color for success); the row shows the operation name and time, a source summary with `.lineLimit(1)`, and a red failure reason (the full text appears when expanded and is not repeated); expanded, it shows the source diff and three separately collapsible blocks of selectable raw text (the model raw reply is expanded by default), and a borderless `Copy This Record` (`document.on.document`); with no records it shows `ContentUnavailableView` (T76) |
| `workspace-auto.png` / `workspace-target-pinned.png` | Toolbar `Picker(.menu)`: two states, `Automatic (Simplified Chinese)` and an explicit language; the result label uses the resolved language name |
| `loading.png` / `polish-loading.png` / `direct-loading.png` | Compact glass bar · `ProgressView` · status text · glass stop button; Esc cancels |
| `error.png` / `format-error.png` / `cancelled.png` / `permission.png` / `unconfigured.png` / `selection-error.png` / `unwritten.png` | Compact glass bar · one line of explanation · one recovery button (Service Settings / Prompt Settings / Permission Settings / Enter Text / Configure Service / Copy Result / Try Again), with an extra retry icon button for failures; with "Use the whole text of the focused field when nothing is selected" turned on, when focus is in an editable field and nothing is selected the whole field text is used instead, and the `selection-error` state is no longer reached (see T69) |
| `direct-selection-error.png` / `direct-permission.png` / `direct-unconfigured.png` / `direct-error.png` / `direct-format-error.png` / `direct-cancelled.png` | Pixel-identical to the previous row: the direct-replace flow reuses the same compact glass bar and the same recovery entry points; only the shortcut that starts the flow differs. With "Use the whole text of the focused field when nothing is selected" turned on, the source is the whole text of the focused field; direct replace first selects the field with ⌘A and then pastes, so the field ends up holding only the translation instead of having it appended at the insertion point; if it cannot confirm the select-all it does not send the paste and shows the "could not write back" notice (see T70) |
| `result.png` / `polish.png` / `long.png` / `result-loading.png` / `result-unwritten.png` / `result-notice.png` / `result-cancelled.png` / `menubar.png` / `menubar-menu.png` | `NSGlassEffectView` panel · header `Picker(.menu)` + glass icon buttons · selectable result text · bottom hint row + `Copy ⌘⇧C` / `Replace ⌘↩` · `StatusNote` in the content area; the panel closes after copying the result or a successful write-back; `MenuBarExtra` menu (not a popover); the menu bar mark is a template image (`.renderingMode(.template)`) tinted by the system |
| `empty.png` | Expanded with empty source: `canRetry` in `ExpandedPanel` is false and the retry controls are `.disabled`; the source field stays editable |
| `success.png` | Write-back success confirmation: confirms the replacement inside the expanded result, and the action row closes with `Done`; the app instead closes the panel directly after a successful write-back, so this screen is still a prototype proposal |
| `book-list.png` / `book-detail.png` / `book-empty.png` / `no-results.png` | Unified toolbar · search field · `All Languages` pop-up button · `Export…` · `List` rows · `ContentUnavailableView` empty state |
| `history-list.png` / `history-detail.png` / `history-empty.png` | Same toolbar structure · type filter · destructive `Clear History` · detail can be copied and saved |
| `learning.png` / `learning-loading.png` / `learning-error.png` / `learning-empty.png` / `saved.png` | Separate section inside the expanded result · `ProgressView` / `.redacted` placeholder · in-place retry · checkable list and `Save Selected` |
| `aligned.png` | Sentence-by-sentence alignment: system `Text` inside the paired view; copy and replace still output only the translation (§7 exception 3) |
| `workspace-narrow.png` | The single-column stacked branch for a narrow window (content area < 720pt) versus side by side in a wide window |

All 40 states of the old prototype are now covered: `stale` is carried by `unwritten`, `settings-shortcuts` by `shortcuts-recording`, and the other 38 each have a screen.

### 4.1 Where each state is implemented

The 67 states and their counterparts in `Owlet/` (grouped by implementation file):

| State | Implementation |
| --- | --- |
| `workspace`, `workspace-empty`, `workspace-input`, `workspace-loading`, `workspace-polish`, `workspace-error`, `workspace-unconfigured` | `Owlet/Processing/TextProcessingView.swift` (workspace toolbar and editors) · `Owlet/Processing/TextProcessingModel.swift` (processing state) · `Owlet/App/OwletApp.swift` (window, sidebar and menu commands) |
| `workspace-collapsed` | `Owlet/App/OwletApp.swift` (the NavigationSplitView sidebar in MainView) |
| `settings-shortcuts`, `settings-shortcuts-recording`, `settings-shortcuts-conflict` (conflict copy from `ShortcutController.registrationError`) | `Owlet/Shortcuts/ShortcutSettingsPane.swift` · `Owlet/Shortcuts/ShortcutController.swift` |
| `settings-general` | `Owlet/Settings/SettingsView.swift` (tabs) · `Owlet/Settings/GeneralSettingsPane.swift` |
| `settings-language-empty`, `settings-language-rows` | `Owlet/Settings/LanguageSettingsPane.swift` · `Owlet/Settings/LanguageSettingsView.swift` · `Owlet/Settings/TargetMappingSettingsView.swift` · `Owlet/Settings/TargetMapping.swift` |
| `settings-model`, `settings-model-openai`, `settings-model-agent`, `settings-model-failed` | `Owlet/Settings/ModelSettingsPane.swift` · `Owlet/Settings/SettingsStore.swift` (Keychain and local agent paths) · `Owlet/LLM/LocalAgent.swift` (lookup environment, three-level fallback, detection and version) |
| `workspace-auto`, `workspace-target-pinned` | `Owlet/Settings/TargetLanguagePicker.swift` · `Owlet/Processing/LanguageDetector.swift` · `Owlet/Processing/TextProcessingView.swift` |
| `settings-debug`, `settings-debug-open`, `settings-debug-empty` | `Owlet/Settings/DebugSettingsPane.swift` · `Owlet/Debug/DebugLog.swift` · `Owlet/LLM/ModelClient.swift` (recording points) |
| `loading`, `polish-loading`, `direct-loading` | `Owlet/App/Panel/CompactPanelContent.swift` (CompactProcessingView) |
| `error`, `format-error`, `cancelled`, `permission`, `unconfigured`, `selection-error`, `unwritten` | `Owlet/App/Panel/PanelController.swift` (Notice) · `Owlet/App/Panel/PanelRootView.swift` (recover) · `Owlet/App/Panel/CompactPanelContent.swift` (CompactNoticeView) · `Owlet/Selection/SelectionBridge.swift` (sources of permission and read failures) |
| `direct-selection-error`, `direct-permission`, `direct-unconfigured`, `direct-error`, `direct-format-error`, `direct-cancelled` | `Owlet/App/Panel/PanelController.swift`: "Translate and Replace" reuses the same `Notice` / `CompactNoticeView`, on the same screen as `selection-error` / `permission` / `unconfigured` / `error` / `format-error` / `cancelled` |
| `result`, `polish`, `long`, `result-loading` | `Owlet/App/Panel/ExpandedPanel.swift` · `Owlet/App/Panel/ExpandedPanelContent.swift` · `Owlet/App/Panel/PanelController.swift` (when to expand) |
| `result-notice` (failure), `result-cancelled` (cancel) | `Owlet/App/Panel/ExpandedPanelContent.swift` (StatusNote) · `Owlet/App/Panel/PanelController.swift` (inlineNotice); on failure and cancel `hasResultSection` is false and the result area is not rendered |
| `result-unwritten` | `Owlet/App/Panel/PanelController.swift` (`writebackRefusal` → `inlineNotice` returns `.unwritten` / `.unwritable`) · `Owlet/App/Panel/ExpandedPanel.swift` |
| `empty` | `Owlet/App/Panel/ExpandedPanel.swift` (`canRetry`) · `Owlet/App/Panel/PanelController.swift` (with empty source, `processCurrentText()` sets `.idle` and the expanded state is kept) |
| `menubar`, `menubar-menu` | `Owlet/App/OwletApp.swift` (MenuBarExtra, MenuContent, MenuBarLabel) |
| `book-list`, `book-detail`, `book-empty`, `no-results` | `Owlet/Vocabulary/VocabularyView.swift` · `Owlet/Vocabulary/VocabularyStore.swift` · `Owlet/Vocabulary/CollectionAction.swift` |
| `history-list`, `history-detail`, `history-empty` | `Owlet/History/HistoryView.swift` · `Owlet/History/HistoryStore.swift` · `Owlet/History/HistoryRecorder.swift` |
| `learning`, `learning-loading`, `learning-error`, `learning-empty`, `saved` | `Owlet/App/Panel/PanelLearningView.swift` · `Owlet/Learning/LearningContent.swift` · `Owlet/App/Panel/ExpandedPanel.swift` |
| `aligned` | `Owlet/Processing/AlignedSegments.swift` · `Owlet/Processing/TextProcessingView.swift` (`.aligned` of `TranslationDisplayMode`) |
| `settings-model-prompts`, `settings-model-prompts-customized` | `Owlet/Settings/PromptSettingsView.swift` · `Owlet/LLM/DefaultPrompts.swift` |
| `workspace-narrow` | `Owlet/Processing/ProcessingLayout.swift` (720pt threshold) · `Owlet/Processing/TextProcessingView.swift` |
| `success` | Proposal (not implemented): the prototype draws a write-back confirmation; `performReplace` in the app's `Owlet/App/Panel/PanelController.swift` closes the panel directly after a successful write-back |

## 5. Design token retirement table

The color table in `spec/DESIGN.md` and `RoseGlass` have been removed from `Owlet/`; the table below is kept as the migration record.

| Token | Use | Replaced by |
| --- | --- | --- |
| `RoseGlass.accent` / `ink` / `muted` / `paper` / `line` / `selectedNav` / `tint` / `keyFill` | Primary buttons and focus, body text and headings, secondary text, content background, dividers, sidebar selection, recorder background and key caps | The app's `AccentColor` asset (the only allowed outlet for the brand color); `.primary` / `.secondary` / `.tint(nil)`; system window paper and list materials; `Divider()` |
| `RoseGlass.errorFill` / `errorText` / `green` / `skeleton` / pink gradient breathing stroke | Error blocks, success, skeleton, processing decoration | `StatusNote` (`Label` + `.secondary`), `.green`, `.redacted(reason: .placeholder)`; breathing not adopted, the implementation uses only `ProgressView` (T24) |
| `RoseGlass.window` / `sidebar` / `footerFill` | Window / sidebar / bottom bar background | System window background, `List` sidebar appearance, bottom safe area bar material |
| `MainButtonStyle` / `MainLabelStyle` / `FieldBox` / `SelectField` / `KbdChip` / `GroupTitle` / `FormRow` / `PageFooter` / `PageHeader` / `SectionLabel` / `NavRow` / `ProcessingStrip` / `CompactNoticeView` | Self-drawn buttons, input strokes and focus rings, self-drawn dropdowns, key caps, self-drawn window and compact bar parts | `.bordered` / `.borderedProminent` / `.glass` / `.glassProminent`; system `TextField` in `Form` rows + system focus ring; `Picker(.menu)`; shortcuts belong to the menu bar and `.help()` (the design still draws `⌘ ↩`, §2.2 #7); `Form` + `Section`, `.toolbar`, `List`; the compact bar keeps its glass container and uses only `ProgressView`, `Text`, `Label`, `Button(.glass)` and `StatusNote` inside |

## 6. About the settings window

The design drew settings as a page of the main window; the implementation has since moved to the **separate window** required by `settings.md › Desktop (macOS)` (§2.2 #11): opened from the App menu (`⌘,`), with a tabbed toolbar whose buttons are always present and not customizable, minimize and zoom buttons disabled, and the window title following the tab.

1. Settings becomes a `Settings` scene + tabbed `TabView`: **General** (Translation Display, Panel Position) · **Display** · **Prompts** · **Service** (Base URL, API Key, model).
2. The sidebar no longer has a `Settings` row, and the toolbar has no settings button either (`settings.md`: **Include a settings item in the App menu.**).

Settings is a separate window (`Settings` scene, opened from the App menu and ⌘,); the main window sidebar only has Translate & Polish, Notebook and History, and Shortcuts is a tab of the settings window.

## 7. Judgments and exceptions

macOS 26 has no system counterpart in three places, which must be custom; exception 3 belonged to a feature that was not yet implemented when this was written.

| Exception | Approach |
| --- | --- |
| 1 · Inline notice row | macOS has no system banner, and `feedback.md` asks for status feedback close to where it applies. Approach: `Label(systemImage:)` + one recovery `Button` placed in the content flow; failures get a symbol as well, never relying on color alone. |
| 2 · Global shortcut recorder | No system API offers a "click, then record a key combination" UI; Carbon's `RegisterEventHotKey` only registers. In the implementation the recorder button uses `.glass` and switches to `.glassProminent` while recording (`Owlet/Shortcuts/ShortcutSettingsPane.swift`), and keeps `Esc` to cancel, `Delete` to clear, the conflict notice, and `accessibilityLabel` / `accessibilityValue`. This is the only unavoidable custom control in the project. |
| 3 · Sentence-by-sentence alignment layout (implemented, T14) | No system component expresses "source / translation paired by semantic sentence". Approach: paired views inside a `LazyVStack`, all children system `Text`; the pairing comes from the model and is not inferred from display lines. Screen `aligned.png`. |

**Other judgments (mine, not Apple's rules):**

- Keep pink as the app accent color. `color.md › App accent colors` lets an app specify an accent; as long as it only appears in the accent color, prominent buttons, selection and status indicators, it complies with `liquid-glass.md › Color on glass`. **Do not** spread it into every view's tint.
- Remove the `Local` badge (it carries no actionable information; where data is stored is written in the "Service" tab of settings); recommend removing the `Copied` toast (the result is already on screen); switch the Owlet mark in the panel header to a tintable symbol or template image so a white PNG is not invisible on light glass.

## 8. Acceptance checklist

1–7 and 9 have landed with the implementation; 8 is not met (the menu bar only has open main window, the four shortcut actions, settings and quit, and does not cover every toolbar item); 11–12 are tied to the unadopted recommendations in §2.2 and need a decision on adoption first.

1. **Layer discipline.** Glass only appears in toolbars, sidebars, floating panels and popovers; content areas, cards, list rows and group containers never have glass.
2. **Amount of glass.** Custom glass surfaces on one screen do not exceed "the few most important functional elements", and the panel never stacks glass on glass.
3. **Color budget.** At most one tinted prominent action per screen; control labels are monochrome; the brand color only appears in the accent color, prominent actions and status indicators.
4. **Accessibility.** `Reduce Transparency` has a solid fallback; `Increase Contrast` has stronger strokes; `Reduce Motion` removes the expand animation (`PanelController` already has a `reduceMotion` branch); the breathing animation is an unadopted recommendation (T24); `workspace-collapsed.png` is functionally identical to the expanded state.
5. **Contrast.** Body text ≤17pt reaches 4.5:1, ≥18pt or bold reaches 3:1; rose `oklch(47% .17 350)` is about 8:1 on white and safe as an accent; secondary text uses `.secondary`, guaranteed by the system.
6. **Hit targets.** Desktop default 28×28pt, minimum 20×20pt; toolbar icon buttons 28×28; list rows no shorter than 28pt.
7. **Font size.** Desktop default 13pt, minimum 10pt, no small light-weight text.
8. **Keyboard.** Every toolbar item has a matching menu bar command and shortcut (`toolbars.md › Desktop (macOS)`); the focus ring is visible; every control is reachable under `Full Keyboard Access`.
9. **Dark appearance.** With no hard-coded colors, check both light and dark; no app-level appearance switch.
10. **Menu bar.** `Settings… (⌘,)` is in the App menu (implemented); `Show/Hide Sidebar (⌃⌘S)` is provided by `SidebarCommands()` (implemented); the `Edit` menu provides `Undo/Redo/Cut/Copy/Paste/Select All`.
11. **Width adaptation.** Dragging continuously from minimum width to full width, the Translate & Polish page switches between side by side and stacked at 720pt with no jumps, truncation or reflow jitter.
12. **Copy (not adopted, §2.2 #7 / #8 / #12).** The three copy rules in §2.3 hold without exception; no shortcut glyphs or empty hints anywhere in the interface.

The retired `design/index.html` console used to have two automatic checks:

- `checkDesignStates()` → renders each of the 66 states once: app window states must have a toolbar and content area (the Translate & Polish toolbar must have action buttons, settings states must have a tab switcher); panel states must be floating panels, the compact bar must have compact bar elements, the expanded state must have a panel header and action row, and the action row must not be clipped; `menubar` only checks that the state exists.
- `checkFlowBoard()` → all 66 states appear on the overview without duplicates, and the section count matches the definition (10 windows / panels); returns `{states, frames, panels}`.

## 9. Migration order

From smallest to largest impact; each step can be verified on its own.

1. Delete `RoseGlass` and the self-drawn button styles, replacing them all with system semantic colors and system buttons (landed).
2. Move the main window to `NavigationSplitView` (collapsible sidebar) and put the toolbar in place: `navigationTitle` + pop-up button (left) + segmented control (right) (landed).
3. Move settings to a `Settings` scene + tabs, and remove its entry from the sidebar and toolbar (implemented, T19).
4. Remove the bottom action bar and move actions into the toolbar (implemented, T32); the Translate & Polish page shows two columns side by side when the content area is ≥720pt (implemented, T22).
5. Switch lists to `List` + `.searchable` + `ContentUnavailableView` (implemented with the notebook and history); context menus are not implemented; the floating panel's breathing animation and the `Save Selection` action row were not adopted (the compact bar and action row have landed).
6. Complete the menu bar and tighten the copy (`⌘,` is wired; the copy has not been tightened); final accessibility and appearance checks in §8.

## 10. References

HIG references come from Apple's official documentation <https://developer.apple.com/design/human-interface-guidelines>: `liquid-glass` (`Where the material belongs` / `Which variant` / `Color on glass` / `Review checklist`), `materials`, `color`, `layout`, `designing-for-macos`, `sidebars`, `toolbars`, `windows`, `panels`, `split-views`, `settings`, `the-menu-bar`, `buttons`, `segmented-controls`, `pop-up-buttons`, `menus`, `search-fields`, `lists-and-tables`, `boxes`, `labels`, `text-views`, `toggles`, `pickers`, `progress-indicators`, `feedback`, `writing`, `accessibility`, `focus-and-selection`, `dark-mode`, `generative-ai`. The component categories follow Apple's official catalog: <https://developer.apple.com/design/human-interface-guidelines/components>

T33 materials: navigation and toolbars use the system default Liquid Glass; the content area does not stack glass and uses the system background of GroupBox / Form. Actions use the system `.glass` / `.glassProminent`, and icons come from SF Symbols. In a narrow window the workspace keeps the editors and the study section reachable through a native ScrollView.

2026-09-29, the user confirmed an override of the content-layer restriction above: the three workspace GroupBoxes get the native `.glassEffect(.regular, in: ContainerRelativeShape())`, whose shape follows the container; no new color, blur, border or shadow implementation was added.

Management page titles: the Notebook and History pages do not repeat the window navigation title; the count is the first row of the List as a Text (secondary, selectionDisabled), no longer a sticky Section header.

T35 layout restoration: the workspace title was removed; the language Picker keeps its layout size; the study GroupBox is always present; management details use a separate ScrollView, gray metadata and native GroupBox, and the list supports system multiple selection; a ToolbarSpacer separates previous/next from the content actions.

T36: removed the brand accent color setting and use the system default accent color; the sidebar explicitly uses List.sidebar without overriding font size. Study uses the SF Symbol lightbulb.fill, the Notebook uses books.vertical; the filter Menu contains a Picker.inline so options show directly at the first level.

T37: search uses AppKit NSSearchField, with the system providing the magnifier, clear button and focus ring; a separate ToolbarItem hides the shared background to avoid a glass capsule stacked with a local focus ring.

T38 supersedes T37: search becomes SwiftUI searchable + DefaultToolbarItem(.search), with the system handling size, focus and search interaction; ToolbarSpacers separate navigation, content actions and the rightmost search.

T39: keep NavigationSplitView; the unified toolbar distributes filter, previous/next, content actions and search across navigation/principal/primaryAction.

The body split views of management pages keep a minimal gap from the top safe area, and the system divider does not extend into the unified toolbar; native lists are not clipped.

T40: the wide-screen workspace uses the native HSplitView, the same split approach as the management pages; source and result scroll independently, the study section at the bottom stays present, and narrow screens keep the top/bottom arrangement.

T42 panel: the source summary and the result use the system glassEffect; the status bar and the combined source actions use a SwiftUI-hosted NSSegmentedControl (momentary / fit); standalone actions use Button.glass, more actions use contextMenu, and study uses a List with a borderless save button per entry; no outer glass covers the transparent gaps.

### T42 exact artboard component check

Only [6313:31216](https://www.figma.com/design/PL0seWKhVgNHzaHLFbWLaQ/macOS-27--Community-?node-id=6313-31216) is used as the layout source. The main components and variants below were all read from the instance details, and Button was checked against its master via From this file; other artboards are not layout sources.

| Instance on the artboard | Main component / variant | SwiftUI counterpart |
| --- | --- | --- |
| 6313:31543 source actions; 6313:31552 error state; 6313:31628 processing | Segmented Control / Light / XL / Active=True; master 605:3160 | SwiftUI-hosted NSSegmentedControl (momentary / fit), keeping icons and text, not assembled from several buttons |
| 6313:31274, 6329:31755 content material | Liquid Glass - Medium / Light; master 483:9257 | System glassEffect |
| 6313:31301 close, 6313:31302 copy, 6329:31761 study | Button / Light / XL / Idle; master 648:4854 | Button(.glass), SF Symbols xmark, doc.on.doc, lamp.desk |
| 6313:31478 save | Buttons / Over-Glass / Borderless / Idle; master 502:5872 | Button(.borderless), bookmark / bookmark.fill |
| 6329:31758, 6313:31277 | Separators | Divider |

Appearance follows the system and is not fixed to Light; no self-drawn colors, materials, borders or button styles.

T42 visual fixes: body text Title 2 Regular (17/22), icons SF Pro Medium 13pt, system circular buttons 36pt; the result and study panels are 257 / 295pt tall respectively, with actions stacked at the bottom-right. Large surfaces use the system ButtonBorderShape.roundedRectangle; no radius is filled in by hand.

### Isolated native panel preview

The full process, failed attempts and the limits of the evidence are in [Panel debugging, testing and screenshots](panel-debugging-and-testing.md).

`python3 scripts/panel-preview.py` uses a fixed selection and a mock model, bypasses system permission requests, and keeps the notebook in memory only; the main app's configuration is unchanged. ⌘1–⌘5 switch between five states: processing, missing configuration, connection failure, success and study.

`python3 scripts/panel-preview.py --live` reads `DEEPSEEK_API_KEY` from the process environment for a real integration run; the key is never written to disk or printed. `--background /absolute/path/background.png` provides an in-window reference background for glass screenshots; by default the system wallpaper is neither used nor changed.

The panel's combined-action NSSegmentedControl turns off the cell's own border (isBordered = false), and a single `.glassEffect(.regular)` layer provides the background; this avoids stacking while keeping the background clear.

T43: the Panel section of General settings uses a native Picker to choose the glass effect; panel glass surfaces consistently use the system Glass.clear / regular, defaulting to regular, with no hand-written opacity or material. Glass intensity still does not belong to the app: `SwiftUICore.Glass` only has `regular` / `clear` / `identity`, and `NSGlassEffectView` only has `style` and corner radius / tint, with no public symbol for continuous intensity, so under the Picker that group only uses a secondary `Text` + a system `Link` pointing to "System Settings › Appearance" (BDR-0014). This points to an existing system setting and is not a new HIG claim, so this table adds no reference entry for it.

The preview can use `--screenshots /absolute/path/output-dir` to switch states automatically and export window screenshots of the five main states plus the saved / unsaved states through the system screencapture, without computer use. AppKit cacheDisplay misses the glass compositing and cannot be used for material acceptance; `--settings /absolute/path/output-dir` uses the same cacheDisplay path to export the General settings page off-screen (it has no glass surface, so the result is usable) and does not need screen recording permission. While the window is inactive, system buttons show their inactive colors.

T44: expanding the result uses a SwiftUI spring and NSAnimationContext.animate(.spring), with both the window and the content expanding from the top; study rows are vertically centered HStacks, and the bottom actions of result / study sit 24pt from the right and bottom edges.

T45: the two study columns use a native spring with move / opacity transitions; each entry row is a borderless Button, and its icon switches with the actual saved state from the SwiftData Query; already-saved buttons are no longer disabled.

The translation on the left side of study uses a native NSTextField(wrappingLabelWithString:) with justified paragraph alignment, 17pt, 2pt line spacing, selectable and copyable, with the last line naturally aligned. The preview's `--active` is only for comparing active colors of system controls; it does not represent mouse hover or a truly active window; the bottom buttons keep the standard Button.glass.

The settings "Languages" group gains a "Reading Notation" section: languages with competing systems (Japanese, Chinese) use a system `Picker`, the rest use `LabeledContent` to show fixed IPA.

## T47 Lookup card component map (implemented in the panel, the rest pending)

Behavior is in the [lookup spec](../spec/vocabulary/features/word-lookup.feature), the decision in [BDR-0008](../spec/vocabulary/decisions/BDR-0008-reading-word-lookup.md). The following are implementation candidates and do not mean controls have been replaced or accepted; they do not add to the retired prototype's screenshot / state counts.

| Reading area | Behavior kept and native hosting boundary |
| --- | --- |
| Panel body | **T48 implemented**: the source TextEditor stays; the read-only result becomes a TextKit 1 read-only `NSTextView` (`LookupText`, 16pt Medium, `NSColor.textColor`, justified when study shows two columns), replacing `Text.textSelection` and `PanelJustifiedText` in the panel |
| Main window text processing result | **T50 implemented**: both the result and both sides of the sentence alignment are `LookupText` (result justified 16pt Medium; aligned source Regular, translation Medium); the source input field stays editable |
| Notebook detail | **T50 implemented**: the expression (22pt semibold), the source sentence context and before/after polish are `LookupText`; before polish uses the secondary color; the meaning stays `Text` |
| History detail | **T50 implemented**: source (Regular) and result (justified Medium) are `LookupText`, replacing `PanelJustifiedText`; study and save actions unchanged |
| Study expressions | **T51 implemented**: the row is no longer wrapped in one full-row `Button`: the bookmark is a `.plain` button (the accessibility entry for saving), and the row saves via `onTapGesture` while keeping the hover background; the expression is `LookupText`: ⌘-click looks up a word; dragging / double-clicking selects and shows the toolbar; right-click or Return looks it up; the context is that entry's source sentence |

T48: the selection toolbar and the lookup card share one system `NSPopover` (`.transient`). The toolbar has a single `.plain` "Look Up" text button; the popover itself is the toolbar frame, with no extra glass button layer and no hover tooltip; when over the limit it shows the reason directly. The card is 320pt wide; the title is the looked-up word form at 16pt semibold; secondary 13pt `.secondary` lines show, in order, a differing base form, the reading and the part of speech; the meaning is 15pt; source / no source sentence use `Label` + `.secondary`; loading is centered secondary text, failure is a centered red `Label` with a plain-text "Retry", "Look Up in This Sentence" is a plain-text button, and Speak is a 36pt `CardButton`. The context menu inserts "Look Up Selection" at the top of the system menu. The lookup card validates the system popover first, with content built from system Text / Label, ProgressView and Button; selection actions are hosted by native toolbars / menus with no hand-drawn controls. The base form is shown as secondary; the source, failures and the reason Speak is disabled are readable in the content and accessible to assistive technologies.

Hover only follows the [closed exception in DESIGN](../spec/DESIGN.md) (the section on the closed exception for hover lookup). Native validation must cover hits on real text (not just the nearest character index), Chinese and Japanese word segmentation, double-click / drag / copy, isolation of saving in study rows, popover focus, Esc levels, VoiceOver, and system voices being available / missing. Validate the first reading area first, then decide the smallest change for the other areas; do not plan a uniform replacement across all five upfront.

T55 ([BDR-0010](../spec/vocabulary/decisions/BDR-0010-collect-from-lookup.md)): to the right of the card's title row and left of `Speak` sits a `CardGlassButton` (`.glass`, circular border, 36pt, 13pt glyph), the same component as `Speak`, only with the symbol `bookmark` / `bookmark.fill` and the accent color when saved; `.hoverTip` and the accessibility value give "Add to Notebook / Remove from Notebook" (when no system voice is available, the reason for `Speak` also goes through the tooltip instead of taking a line of explanation). The button does not appear when the text language is unknown or the notebook is not connected. No self-drawn controls and no confirmation dialog.
