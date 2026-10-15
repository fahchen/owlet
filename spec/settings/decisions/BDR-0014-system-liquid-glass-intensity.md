[English](BDR-0014-system-liquid-glass-intensity.md) · [简体中文](BDR-0014-system-liquid-glass-intensity.zh-CN.md)

# BDR-0014: Glass intensity belongs to System Settings; the app only points to it

Status: Accepted (user, 2026-10-13), Implemented (T64). Origin: the user decided the app should no longer offer its own Liquid Glass intensity control and should point to System Settings from its settings instead.

## Decision

The app keeps only the two-way "Glass Effect" choice (More Transparent / Higher Contrast), with a note under that row: Liquid Glass and its intensity are adjusted in **System Settings › Appearance**, plus a native link that opens that pane. The app offers no control that suggests it can adjust glass intensity itself.

## SDK facts (checked twice against the macOS 27 SDK)

| API | What it can express |
| --- | --- |
| `SwiftUICore.Glass` | `regular` / `clear` / `identity`, plus `tint` and `interactive`; no continuous intensity |
| `NSGlassEffectView` | `style` (Regular / Clear), `cornerRadius`, `tintColor`, and on macOS 27 also `effectIsInteractive`; no continuous intensity |
| Public symbols | No public API exists to set a continuous glass intensity |

The real intensity slider is in **System Settings › Appearance › Liquid Glass** and applies system-wide. The panel's glass is drawn by the window server, so it already follows that setting; the app does not need to replicate it.

## Alternatives rejected

- **Five-step SwiftUI `Material` slider**: rejected by the user; after switching to `Material` it no longer looks like Liquid Glass.
- **Automatically following the system accessibility switches**: rejected by the user; too much hassle for the user.

Both have been reverted. `PanelGlassEffect` stays a two-way choice, and `PanelGlassEffectTests` passes unchanged.

## Consequences and costs

- **Accepted cost: part of the panel glass's look is no longer controlled by the app.** When the user raises or lowers the system intensity, the app neither compensates nor pretends it can. The two places (System Settings and app settings) show different parts of the same thing and do not contradict each other.
- Pointing to System Settings instead of copying a fake intensity control gives the user a single entry point, and they will not assume the app can override the system intensity.

## Impact

- `Owlet/Settings/GeneralSettingsPane.swift`: under Glass Effect in the "Panel" group, add a secondary note and an "Open System Settings" link.
- `Owlet/Settings/PanelGlassEffect.swift`: add `SettingsStore.appearanceSettingsURL` (the `x-apple.systempreferences:` URL for the Appearance pane, optional, never force-unwrapped).
- `strings/translations.json`: two new interface strings (the note and the link label); the catalog is regenerated.
