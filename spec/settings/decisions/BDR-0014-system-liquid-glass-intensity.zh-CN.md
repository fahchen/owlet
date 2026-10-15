[English](BDR-0014-system-liquid-glass-intensity.md) · [简体中文](BDR-0014-system-liquid-glass-intensity.zh-CN.md)

# BDR-0014：玻璃强度归系统设置，应用只指向它

状态：已确认（用户 2026-10-13），已实现（T64）。来源：用户决定应用不再提供自己的液态玻璃强度控制，改为在设置里指向系统设置。

## 决定

应用只保留「玻璃效果」两选一（更透明／更高对比度），并在该行下说明：液态玻璃及其强度在**系统设置 › 外观**中调整，附一个打开该面板的原生入口。应用不提供任何暗示可以自行调整玻璃强度的控件。

## SDK 事实（macOS 27 SDK 复核两次）

| API | 能表达什么 |
| --- | --- |
| `SwiftUICore.Glass` | `regular` / `clear` / `identity`，另有 `tint` 与 `interactive`；没有连续强度 |
| `NSGlassEffectView` | `style`（Regular／Clear）、`cornerRadius`、`tintColor`，macOS 27 多一个 `effectIsInteractive`；没有连续强度 |
| 公开符号 | 不存在可设置连续玻璃强度的公开 API |

真正的强度滑杆在**系统设置 › 外观 › Liquid Glass**，系统级生效；浮窗玻璃由 window server 绘制，因此已经跟随该设置，不需要应用再复刻一遍。

## 备选与不采纳

- **五档 SwiftUI `Material` 滑杆**：用户否决——换成 `Material` 之后不再像液态玻璃。
- **自动跟随系统无障碍开关**：用户否决——对用户来说太麻烦。

两个方案都已回退，`PanelGlassEffect` 保持两选一，`PanelGlassEffectTests` 原样通过。

## 后果与代价

- **接受的代价：浮窗玻璃的一部分观感不再由应用掌握。** 用户把系统强度调高或调低时，应用既不补偿也不假装能补偿；两处（系统设置与应用设置）显示的是同一件事的不同部分，不会互相矛盾。
- 指向系统设置而不是复制一个假的强度控件，用户看到的入口唯一，也不会误以为应用能覆盖系统强度。

## 影响

- `Owlet/Settings/GeneralSettingsPane.swift`：「浮窗」分组的玻璃效果下加一行次级说明与「打开系统设置」链接。
- `Owlet/Settings/PanelGlassEffect.swift`：新增 `SettingsStore.appearanceSettingsURL`（外观面板的 `x-apple.systempreferences:` URL，可选值，不强制解包）。
- `strings/translations.json`：两条新界面串（说明与链接标签），目录随之重新生成。
