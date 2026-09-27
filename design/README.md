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
| [workspace-empty.png](screenshots/workspace-empty.png) | 文本处理 · 空输入 | 没有选区也没有文本：占位提示可见，复制与提交都不可用。 |
| [workspace-input.png](screenshots/workspace-input.png) | 文本处理 · 已输入 | 有文本但还没结果：可提交，复制仍不可用。 |
| [workspace-loading.png](screenshots/workspace-loading.png) | 文本处理 · 处理中 | 结果区以占位文本表示处理中，底部改为取消。 |
| [workspace-polish.png](screenshots/workspace-polish.png) | 文本处理 · 润色结果 | 同一页面切到润色：标签改为润色结果与保留原意。 |
| [workspace-error.png](screenshots/workspace-error.png) | 文本处理 · 请求失败 | 行内提示 ModelError 的原始文案，并提供服务设置入口。 |
| [workspace-unconfigured.png](screenshots/workspace-unconfigured.png) | 文本处理 · 服务未配置 | 缺少服务配置时提示并指向设置。 |
| [workspace-collapsed.png](screenshots/workspace-collapsed.png) | 文本处理 · 侧栏收起 | NavigationSplitView 收起侧栏后页面不变。 |
| [shortcuts.png](screenshots/shortcuts.png) | 快捷键 · 未设置 | 三个全局动作未录制；面板内固定键只读。 |
| [shortcuts-recording.png](screenshots/shortcuts-recording.png) | 快捷键 · 录制中 | 录制按钮等待新组合键；Esc 取消，Delete 清除。 |
| [shortcuts-conflict.png](screenshots/shortcuts-conflict.png) | 快捷键 · 组合冲突 | 与已录制动作冲突时提示换一个组合。 |
| [settings.png](screenshots/settings.png) | 设置 · 模型服务 | DeepSeek 已保存：Base URL、Key、模型列表选择与浮窗位置。 |
| [settings-openai.png](screenshots/settings-openai.png) | 设置 · 自定义服务商 | OpenAI Compatible 默认项：Base URL 与模型名称是自由填写，显示占位文案。 |
| [settings-saved.png](screenshots/settings-saved.png) | 设置 · 已保存 | 保存后在页脚左侧确认，模型列表随保存重新读取。 |
| [settings-models.png](screenshots/settings-models.png) | 设置 · 模型列表失败 | DeepSeek 取模型列表失败时就地提示原始错误并给重试。 |
| [settings-models-loading.png](screenshots/settings-models-loading.png) | 设置 · 模型列表读取中 | 读取模型列表时在名称行尾显示小号指示器。 |
| [loading.png](screenshots/loading.png) | 翻译 · 处理中 | 紧凑条：选中文字摘要、加载指示、停止按钮。 |
| [polish-loading.png](screenshots/polish-loading.png) | 润色 · 处理中 | 复用同一条紧凑条，只改状态文字。 |
| [direct-loading.png](screenshots/direct-loading.png) | 直接替换 · 处理中 | 独立快捷键授权本次写回，状态文字标明。 |
| [error.png](screenshots/error.png) | 请求 · 失败 | 连接失败时就地提示并给服务设置与重试。 |
| [format-error.png](screenshots/format-error.png) | 请求 · 格式错误 | 返回格式不符合契约时提示检查提示词。 |
| [cancelled.png](screenshots/cancelled.png) | 请求 · 已取消 | 取消后不写回，可重新处理。 |
| [permission.png](screenshots/permission.png) | 权限 · 未授权 | 未授权时不发起请求，入口指向权限设置。 |
| [unconfigured.png](screenshots/unconfigured.png) | 服务 · 未配置 | 缺少服务配置时提示并指向设置。 |
| [selection-error.png](screenshots/selection-error.png) | 选区 · 读取失败 | 读取不到文字时不发起请求，可改用手动输入。 |
| [unwritten.png](screenshots/unwritten.png) | 直接替换 · 未能写回 | 未能写回原应用时就地提示，并可复制结果；同一布局也用于「原选区不可编辑」。 |
| [result.png](screenshots/result.png) | 翻译 · 结果 | 展开面板：头部操作选择、原文、译文与底部复制替换。 |
| [polish.png](screenshots/polish.png) | 润色 · 结果 | 同一面板，标签改为润色结果与保留原意。 |
| [long.png](screenshots/long.png) | 翻译 · 长文本 | 结果滚动，复制与替换固定在底部。 |
| [result-loading.png](screenshots/result-loading.png) | 翻译 · 结果区处理中 | 已展开时重新处理保持展开，在结果区显示加载。 |
| [result-unwritten.png](screenshots/result-unwritten.png) | 翻译 · 未能写回 | 结果仍保留，就地说明未能写回并可复制；同一布局也用于「原选区不可编辑」。 |
| [result-notice.png](screenshots/result-notice.png) | 翻译 · 结果区失败 | 展开态失败不收起面板：结果区隐藏，行内提示加底部重试。 |
| [result-cancelled.png](screenshots/result-cancelled.png) | 翻译 · 结果区已取消 | 取消后结果区隐藏，行内提示与底部都回到重新处理。 |
| [menubar.png](screenshots/menubar.png) | 菜单栏 · 常驻 | 点击菜单栏图标展开菜单，不直接开窗。 |
| [menubar-menu.png](screenshots/menubar-menu.png) | 菜单栏 · 展开菜单 | 菜单：打开 Owlet、三个快捷键状态、设置…（⌘,）与退出。 |
