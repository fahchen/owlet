[English](DESIGN.md) · [简体中文](DESIGN.zh-CN.md)

> Confirmed by the user on 2026-09-29: body content may also use system Liquid Glass containers; the source, translation and study areas of the workspace use native `glassEffect`, with no hand-drawn material. This overrides the older rule below that "the content layer does not use glass".

# Owlet · Visual and Interaction Rules

## Design and Interaction Style Confirmed on 2026-10-11 (Takes Precedence over What Follows)

This section collects the style confirmed item by item during this iteration for the panel, the Translate & Polish page, the notebook, history and settings; where it conflicts with older rules below, this section wins.

### Surfaces and Materials

- The body of the panel and of the Translate & Polish page sits on one glass surface: system `glassEffect` with a fixed 34pt corner radius (`PanelMetrics.cornerRadius`) that does not change with size. The panel glass effect can be More Transparent / Higher Contrast (default); the processing and result states use the same opacity.
- The notebook and history are reference pages and are not wrapped in glass cards: list and detail are split columns sized to the available width (list 38%, 220–340pt), and they do not overflow or push out the sidebar when the window shrinks.
- The main window toolbar is translucent; content can scroll underneath it and show through. At rest, content still starts below the toolbar.
- The 24pt margins at the top and bottom edges of the body are fade bands: scrolling text passes under the margin and fades out, with no background colour or material and no darkening of the glass. The top margin of the panel can drag the window.
- The panel has a 24pt transparent margin on all sides so its shadow fades out completely and is not clipped by the window edge.

### Typography

- The result weighs more than the source: source Regular, translation / polish result Medium; panel source 15pt and result 16pt, main window columns 16pt. The result uses justified native read-only text (`LookupText`, selectable and supporting lookup) with `textColor`, so glass vibrancy does not wash it out.
- Areas fit their text height with no empty space; the panel source uses a vertical `TextField` that grows with its content.
- Leading and trailing whitespace of the selection is removed before processing and restored as is on write-back.
- Language names are shown in their own script: 简体中文, 繁體中文, English, 日本語, consistently across the app (`LanguageCatalog.name(for:)`).
- The detail of reference pages is a 640pt reading column, left aligned, so long lines do not span a wide window. List rows show the result or expression first (15pt Medium), then the source or meaning (secondary colour).

### Colour

- Only system semantic colours and the system accent colour: body `.primary`, metadata and hints `.secondary`, collection bookmark and selection `accentColor`, errors always `.red`.
- Operations carry their own colour: Translate blue (`systemBlue`), Polish green (`systemGreen`), used for the selected icon in the toolbar segmented control and the operation icon in history rows (`Operation.tint`).
- Compact notices and segment text use the normal foreground colour and turn red on error, with no background colour.
- Notebook contexts use a 3pt accent-coloured vertical bar as a quote mark; text before polish is greyed out, text after polish stays in the normal colour.

### Layout and Buttons

- Floating buttons: 36pt round glass buttons (`CardButton`) floating at the bottom-right of the body, 24pt from the edges. The button row wraps only the buttons themselves, so text beside them stays clickable; the bottom of the content reserves scroll room so text can scroll out from under the buttons, and no space is reserved for the buttons at rest.
- Translate & Polish page toolbar: an icon-only Translate / Polish segmented control on the left followed by the mode title; on the right the source language, a blue `»`, and the target language (Polish has only the source language). Language button width follows the current option. The page has no run button; ⌘↩ or the bottom-right button processes again.
- When the source language changes, the target language follows the mapping in settings and can still be changed by hand afterwards.
- Combined operations use a Segmented Control; standalone actions use round glass buttons. Inline actions on reference pages and in settings (delete, clear, restore default, add mapping) use borderless icon or plain text buttons, not grey boxes.
- Each action has exactly one icon across the app: cancel / close `xmark`, process again `arrow.clockwise`, study `lamp.desk`, back `chevron.left`, copy `document.on.document`, delete `trash`; operation icons use `Operation.symbol` (Translate `translate`, Polish `wand.and.sparkles`).
- Settings is a separate window with grouped Forms. Shortcut recording uses a value style (a set combination in secondary colour, an unset one as blue "Record", a light capsule while recording); clearing uses the × after the combination.

### States

- Loading text (Translating… / Polishing… / Finding useful expressions…) is centred horizontally and vertically in its area, in secondary colour.
- Errors sit in the same centred spot as loading: a red message plus a plain text Retry or Settings button. When reading fails, the previous text is cleared and no old result is shown.
- When there is no content, the whole page area shows a single centred empty state, with no empty list column.

### Motion

- Always `spring(duration: 0.36, bounce: 0.12)`, respecting Reduce Motion.
- The panel goes from source bar to result as the same piece of glass growing downward in place: no new panel, no flash, no jitter. The top edge stays fixed; once expanded it can be dragged, and its position is remembered.
- Switching to study keeps reading continuous:
  - Side by side, the source column squeezes its text and narrows to zero, the result moves into the source position, and the study column grows in from the right.
  - Stacked vertically and in the history detail, the source collapses together with the first divider, the result moves up, and the second divider and the study list expand from below.
  - Going back plays exactly in reverse. Size animations use measured heights and never jump from nil.
- When the panel switches from result to study it keeps its height where possible: the study list is 3–5 items tall and shrinks only when there are fewer items.

### Interaction and Shortcuts

- The panel closes only on clear intent: Esc or a click outside; losing focus does not close it.
- Clicking a study item collects / uncollects it immediately, with no confirmation; rows have a hover background and do not flash when pressed. Expression text can be dragged or double-clicked to select and look up (T51): a click on the expression text waits for the system double-click interval before toggling collection, so double-clicking to select a word does not collect by mistake; clicks on the bookmark, the meaning or empty row space still toggle immediately (to be confirmed).
- Four global shortcuts, all recordable: Translate, Polish, Translate and Replace, Polish and Replace; "and Replace" authorizes writing this result back directly.
- Buttons in the panel and the main window all have fixed shortcuts, defined in one place in `KeyHint`, so button bindings, hover tips and the Shortcuts page share one source:
  - Panel: ⌘↩ replace, ⌘C copy result, ⌘R process again, ⌘L study / back, Esc stop / close.
  - Main window: ⌘↩ process, ⌘1 / ⌘2 switch Translate / Polish, ⌘. cancel, ⌘L study / back, ⌘C copy, ⌘↑ / ⌘↓ previous / next, ⌘⌫ delete.
- ⌘C respects the selection first: with text selected it copies the selection; otherwise it copies the current result, record or expression.
- Buttons with text get no hover tip, since the text already states the action (confirmed 2026-10-11).
- Every icon button has a hover tip reading "action + key", shown in a custom glass capsule (`HoverTip`) so it also appears in a panel that does not activate the app; the settings window has no shortcut actions and shows no tips.
- The Shortcuts page groups fixed keys by scope in a three-column table; the menu bar menu shows recorded global shortcuts as key equivalents, right aligned.

### How to Verify

- Read the components, font sizes and spacing of the Figma instance before implementing; render the real views in previews with fake data, without calling a model.
- Check each state with screenshots; check motion with frame-by-frame screenshots or screen recordings; capture only the preview window itself so other windows on screen are not recorded.

## Design Rules (Take Precedence over What Follows)

- Every component uses native macOS 26 SwiftUI / AppKit, with no hand-made controls: no custom colours, tint or accent tokens, and no custom fills, borders, gradients, glows, shadows, corner styles, underlined links or custom ButtonStyle.
- The component mapping is in [docs/liquid-glass-components.md](../docs/liquid-glass-components.md). The `design/screenshots/` folder of the old browser prototype was retired along with it; every component in it had been mapped to a native component. Implementation follows that document.
- Two criteria:
  1. **Liquid Glass belongs only to the functional layer**: toolbars, sidebars, floating panels, popovers. The content layer (body, results, cards, list rows, group containers) uses system materials and never stacks glass.
  2. **Use a system component whenever one exists**: system components automatically get the Liquid Glass look, vibrancy, focus rings, keyboard and VoiceOver support, and Reduce Transparency / Increase Contrast / Reduce Motion adaptation.
- The window skeleton uses system components: a `Window` scene + `NavigationSplitView` (collapsible sidebar, `⌃⌘S`), `.toolbar`, `List`, `MenuBarExtra` and a separate `Settings` scene; the notebook and history use `.searchable` and `ContentUnavailableView`.
- Button styles by layer: toolbar items use system toolbar buttons; action rows always use `.glass` / `.glassProminent`. The bottom action row of a floating panel is wrapped in a `GlassEffectContainer` (adjacent glass needs to merge); the two icon buttons floating at the bottom-right of the Translate & Polish page are **not** wrapped (they must stay separate); the settings window footer has been removed.
- Each screen has only one primary action, at the trailing end; the Translate & Polish page puts it at the end of the toolbar action group.
- Use the system accent colour, system semantic colours, the system font and SF Symbols. The brand rose colour exists only as the app `AccentColor` resource and appears in the accent colour, prominent actions, selection states and status indicators; it is not scattered into per-view tints.
- Light and dark modes both use system semantic colours. The user can choose the panel glass effect separately: More Transparent or Higher Contrast, using the system clear / regular glass, with no hand-drawn material.
- Layout (element order, position, size, spacing) and states were constrained by `design/screenshots/` (now retired), never component styles. Component styles follow this document and the component mapping.

### Closed Exception for Lookup Hover (Confirmed 2026-10-07; Since 2026-10-11 Shown Only While ⌘ Is Held)

While ⌘ is held, an unselected word under the pointer in read-only text may be tinted with the system `NSColor.selectedTextBackgroundColor` as a hover hint, with a candidate opacity of 25–35%; the final value must pass a native readability check. Meanwhile the cursor is the system hand (`NSCursor.pointingHand`), signalling that ⌘-click looks the word up. Without ⌘ there is no hover hint and the cursor stays an I-beam. The hint covers only the word actually hit, never sits on top of an existing selection and never changes text layout; study rows likewise show it only while ⌘ is held.

This exception allows only the system semantic colour hint above: no custom RGB, rounded backgrounds, borders, shadows, extra padding or underlines. The hand cursor appears only while ⌘ is held over a word that can be looked up (confirmed by the user 2026-10-11). The lookup card, the selection toolbar and buttons still use system components; keyboard and VoiceOver lookup do not depend on hover. Accept only after verifying light and dark, Increase Contrast and the distinction from a real selection. T49 uses 30% (`LookupTextView.hoverOpacity`, accepted for now in review), drawn as a temporary attribute without changing layout; screenshots in light, dark, and high-contrast light / dark confirmed it is visible and distinguishable from the selection. In a panel that does not activate the app, cursor rects do not apply, so the text view sets the I-beam explicitly on mouse moves. Behaviour is in the [lookup spec](vocabulary/features/word-lookup.feature).

### Design Preferences Confirmed by the User on 2026-10-07

This section records what was explicitly asked for in this round; panel details take precedence over the sizes, font sizes and action row descriptions of the old prototype below. Requirements that apply only to the panel do not automatically extend to the main app.

**General principles:**

- Native feel first: use system SwiftUI / AppKit components and Liquid Glass; do not hand-make controls or imitate materials.
- Stay faithful to the specified design: inspect the Figma instance details, component names, variants and master before implementing; do not guess from screenshots or substitute another page for the specified board.
- Visual fidelity covers component semantics, font size and weight, icon size, colour, spacing and state differences, not just a similar outline.
- Glass must stay readable: the background must not be too transparent and operation icons need enough contrast; prefer system semantic colours and native material options.
- Compare results against real native screenshots; check each state separately, and keep hover, pressed and selected states distinct rather than letting one stand in for another.

**Specific requirements for the panel in this round:**

- Combined operations use a Segmented Control rather than several separate buttons; while translating there is only one background layer.
- The translation status and the icons on the right are separate actions with a divider between them; the standalone icon button on the right of the source bar is round.
- Expanding the result when a request finishes, and switching from result to study, both animate continuously and respect the system Reduce Motion setting.
- The study collect icon is vertically centred on its row; the vertical divider in the middle leaves space above and below and does not run through the panel.
- Bottom actions keep a distance from the panel corner radius, with their right edge aligned to the body's right edge; the shared inset is currently 24pt.
- Study text on the left fills the row width as much as possible, using native justification with a naturally aligned last line.
- Clicking an item toggles collect / uncollect immediately with no confirmation step; the selected state comes from real notebook membership.
- Provide a "More Transparent / Higher Contrast" panel glass setting using the system clear / regular; Higher Contrast by default.
- Operation icons use the system primary foreground colour for contrast; glass buttons keep the native style.

These requirements have gone into the implementation or the task records; that does not mean all visual acceptance is done. The open corner radius, error text colour, active material and interaction acceptance items are in the [debugging and testing notes](../docs/panel-debugging-and-testing.md#still-awaiting-acceptance).

### Copy Rules (Proposal, Not Yet Applied)

1. **Action areas hold only actions.** No explanatory text in toolbars or action rows; state is carried by the content area, hover tips or the menu bar.
2. **The interface does not show shortcuts.** Shortcuts appear only in the menu bar (`.keyboardShortcut`) and hover tips (`.help()`); do not draw `⌘↩` into buttons or write "Shortcut not set". The Shortcuts page itself is the exception, since bindings are its content.
3. **Buttons use verbs and leave the object to context.** When the controls on the same screen already make the object clear, the button does not repeat it: `Translate`, `Polish`, `Copy`, `Save`, `Collect`, `Export…`. Keep the object only when it would be ambiguous, as in `Restore Default` or `Clear Filters`.

One action has only one name within the product.

Rule 2 has been adopted: buttons show no keys; keys appear only in hover tips, menus and the Shortcuts page. Hover tips use the custom `HoverTip` rather than `.help()`, because system tips do not appear when the panel does not activate the app.

## Layout Constraints (Carried Over)

A neutral light interface with rose pink as the brand accent, for a language tool summoned briefly during daytime reading and work communication. Keep the system font, a compact layout and Liquid Glass materials.

- Text processing page: source and result sit side by side in one glass card, stacked vertically when the content area is narrower than 600pt.
- Font sizes and weights are in "Typography" above: the result is one step heavier than the source, panel source 15pt and result 16pt.
- The panel is 773pt wide with a 62pt source bar; the app window defaults to 1080 × 690, minimum 760 × 500.
- Copy and replace output only the translation; sentence-by-sentence display is switched by "Translation Display" in the General settings.

## Retired Colour Tokens

The table below holds the values from the early browser prototype (`:root` of `design/index.html`, now retired) as a historical record only. The native implementation defines no custom colour tokens. The only outlet for the rose colour was meant to be the app `AccentColor` resource; **the resource now exists but defines no colour, and no view uses `.tint()`**, so prominent buttons and selection states actually follow the system accent colour.

| Role | OKLCH | Native replacement |
|---|---|---|
| Rose accent | 47% .17 350 | App `AccentColor` resource (defines no colour yet); once set, the system uses it under the "Multicolour" setting and the user's choice overrides it otherwise. No tint today; buttons use the system accent colour |
| Petal light pink | 95% .025 350 | System source list selection appearance |
| Dark body text | 27% .008 265 | `.primary` / `NSColor.labelColor` |
| Neutral secondary text | 45% .008 265 | `.secondary` / `NSColor.secondaryLabelColor` |
| Near-white background | 99% .003 265 | System window background and paper material |
| Divider | 60% .012 350 / .17 | `Divider()` / `NSColor.separatorColor` |
| Error fill and text | 96% .025 45 / 43% .1 40 | `.red` on a system material |
| Success | 43% .09 158 | `.green` |

Pink is only for brand and interaction emphasis. Success stays green and errors stay system red, so neither is confused with the brand pink. Backgrounds, glass panels and body text stay neutral grey-white; the rose colour is concentrated in the accent colour, prominent actions, selection states and the processing indicator. The full-ring breathing border while processing is still an open design and has not been adopted: the panel adds no hand-drawn border or shadow and keeps the default system glass look; breathing uses no pink gradient stroke and adds no extra layer. The app currently uses only `ProgressView`.

Added and confirmed by the user on 2026-09-29: the pink brand accent is withdrawn in favour of the system default accent colour; the sidebar keeps the system default font size.
