# Design screenshots

Source: `index.html`. One PNG per state.

This board covers only features that are already implemented in the app. Removed states and the features still to come are listed in [../docs/unimplemented-features.md](../docs/unimplemented-features.md).

Screenshot filenames are defined in the fourth field of each `states` entry in `index.html`.

Regenerate from the repository root with Ego Lite running:

```sh
node design/screenshot.mjs
```

Captures use default demo data, a 1440 x 1000 viewport, and native window bounds with 24px padding.
Scrollable content retains its designed viewport; source text is the built-in English sample.

组件样式均为 macOS 26 原生控件的外观；每个组件到原生组件的对照见 [../docs/liquid-glass-components.md](../docs/liquid-glass-components.md)。

| State / screenshot | Name | Notes |
| --- | --- | --- |
| [workspace.png](screenshots/workspace.png) | 文本处理 · 结果 | 工具栏、原文、译文与底部操作栏；预留的收藏与学习两行仍为空位。 |
| [workspace-empty.png](screenshots/workspace-empty.png) | 文本处理 · 输入 | 没有结果时页面只是输入区，复制不可用。 |
| [workspace-loading.png](screenshots/workspace-loading.png) | 文本处理 · 处理中 | 结果区以占位文本表示处理中，底部改为取消。 |
| [workspace-error.png](screenshots/workspace-error.png) | 文本处理 · 请求失败 | 行内状态提示失败原因，并提供服务设置入口。 |
| [workspace-collapsed.png](screenshots/workspace-collapsed.png) | 文本处理 · 侧栏收起 | NavigationSplitView 收起侧栏后页面不变。 |
| [shortcuts.png](screenshots/shortcuts.png) | 快捷键 · 未设置 | 三个全局动作未录制；应用内快捷键固定。 |
| [shortcuts-recording.png](screenshots/shortcuts-recording.png) | 快捷键 · 录制中 | 录制按钮等待新组合键；Esc 取消，Delete 清除。 |
| [settings.png](screenshots/settings.png) | 设置 · 模型服务 | 分组表单：服务商、Base URL、API Key、模型名称与浮窗位置。 |
| [settings-models.png](screenshots/settings-models.png) | 设置 · 模型列表失败 | DeepSeek 取模型列表失败时就地提示并给重试。 |
| [loading.png](screenshots/loading.png) | 翻译 · 处理中 | 紧凑条：选中文字摘要、加载指示、停止按钮。 |
| [polish-loading.png](screenshots/polish-loading.png) | 润色 · 处理中 | 复用同一条紧凑条，只改状态文字。 |
| [direct-loading.png](screenshots/direct-loading.png) | 直接替换 · 处理中 | 独立快捷键授权本次写回，状态文字标明。 |
| [error.png](screenshots/error.png) | 请求 · 失败 | 连接失败时就地提示并给服务设置与重试。 |
| [format-error.png](screenshots/format-error.png) | 请求 · 格式错误 | 返回格式不符合契约时提示检查提示词。 |
| [cancelled.png](screenshots/cancelled.png) | 请求 · 已取消 | 取消后不写回，可重新处理。 |
| [permission.png](screenshots/permission.png) | 权限 · 未授权 | 未授权时不发起请求，入口指向权限设置。 |
| [unconfigured.png](screenshots/unconfigured.png) | 服务 · 未配置 | 缺少服务配置时提示并指向设置。 |
| [selection-error.png](screenshots/selection-error.png) | 选区 · 读取失败 | 读取不到文字时不发起请求，可改用手动输入。 |
| [stale.png](screenshots/stale.png) | 直接替换 · 选区失效 | 原选区变化时停止写回，只保留复制。 |
| [result.png](screenshots/result.png) | 翻译 · 结果 | 展开面板：头部操作选择、原文、译文与底部复制替换。 |
| [polish.png](screenshots/polish.png) | 润色 · 结果 | 同一面板，标签改为润色结果与保留原意。 |
| [long.png](screenshots/long.png) | 翻译 · 长文本 | 结果滚动，复制与替换固定在底部。 |
| [result-loading.png](screenshots/result-loading.png) | 翻译 · 结果区处理中 | 已展开时重新处理保持展开，在结果区显示加载。 |
| [result-notice.png](screenshots/result-notice.png) | 翻译 · 结果区提示 | 展开态的错误在内容区就地呈现，不收起面板。 |
| [menubar.png](screenshots/menubar.png) | 菜单栏 · 常驻 | 点击菜单栏图标打开主界面；快捷键唤起浮动面板。 |
