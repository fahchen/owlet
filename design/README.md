# Design screenshots

Source: `index.html`. One PNG per state; repeated flow-board states are captured once.

Screenshot filenames are defined in the fourth field of each `states` entry in `index.html`.

Regenerate from the repository root with Ego Lite running:

```sh
node design/screenshot.mjs
```

Captures use default demo data, a 1440 x 1000 viewport, and native window bounds with 24px padding.
Scrollable content retains its designed viewport; the Prompt state opens its corresponding settings section.

组件样式均为 macOS 26 原生控件的外观；每个组件到原生组件的对照见 [../docs/liquid-glass-components.md](../docs/liquid-glass-components.md)。

| State / screenshot | Name | Notes |
| --- | --- | --- |
| [result.png](screenshots/result.png) | 翻译 · 结果 | 每句原文下方紧跟对应译文，复制和替换仅使用译文。 |
| [empty.png](screenshots/empty.png) | 输入 · 无选区 | 没有选区时直接粘贴；空文本不能提交。 |
| [loading.png](screenshots/loading.png) | 翻译 · 处理中 | 紧凑条仅展示选中文字摘要、整圈边框呼吸与状态；不显示终止按钮，Esc 取消。 |
| [polish-loading.png](screenshots/polish-loading.png) | 润色 · 处理中 | 复用紧凑处理条，完成后平滑展开结果。 |
| [long.png](screenshots/long.png) | 翻译 · 长文本 | 句子成组滚动，自然换行不影响中英对应关系。 |
| [polish.png](screenshots/polish.png) | 润色 · 结果 | 同一个工具栏，保持原语言与原意。 |
| [learning.png](screenshots/learning.png) | 学习 · 展开 | 勾选所需表达，再主动入库。 |
| [learning-loading.png](screenshots/learning-loading.png) | 学习 · 整理中 | 学习处理独立于主结果，复制与替换可继续。 |
| [learning-error.png](screenshots/learning-error.png) | 学习 · 生成失败 | 局部重试，不要求重新翻译。 |
| [learning-empty.png](screenshots/learning-empty.png) | 学习 · 无推荐 | 不强凑推荐，保留手动收藏。 |
| [saved.png](screenshots/saved.png) | 收藏 · 已入库 | 收藏反馈就地呈现，不跳转打断工作。 |
| [direct-selection-error.png](screenshots/direct-selection-error.png) | 直接替换 · 读取失败 | 紧凑条提示；Esc 关闭并取消。 |
| [direct-permission.png](screenshots/direct-permission.png) | 直接替换 · 权限未授权 | 紧凑条内进入设置。 |
| [direct-unconfigured.png](screenshots/direct-unconfigured.png) | 直接替换 · 未配置 | 紧凑条内进入设置。 |
| [direct-error.png](screenshots/direct-error.png) | 直接替换 · 请求失败 | 紧凑条提示；Esc 关闭并取消。 |
| [direct-format-error.png](screenshots/direct-format-error.png) | 直接替换 · 格式错误 | 不写回原文。 |
| [direct-cancelled.png](screenshots/direct-cancelled.png) | 直接替换 · 已取消 | 紧凑条内展示取消。 |
| [direct-loading.png](screenshots/direct-loading.png) | 直接替换 · 处理中 | 独立快捷键授权本次写回；整圈边框呼吸，Esc 取消本次写回。 |
| [success.png](screenshots/success.png) | 直接替换 · 完成 | 确认写回成功，按 Esc 或完成返回工作。 |
| [stale.png](screenshots/stale.png) | 直接替换 · 选区失效 | 停止写回，只提供复制；原文不受影响。 |
| [error.png](screenshots/error.png) | 请求 · 失败 | 解释失败并提供重试，不把旧结果当成本次结果。 |
| [format-error.png](screenshots/format-error.png) | 请求 · JSON 格式错误 | 无法通过格式校验时保留原文，不写回或记录为成功。 |
| [cancelled.png](screenshots/cancelled.png) | 请求 · 已取消 | 取消后的响应不再写回；可重新处理。 |
| [selection-error.png](screenshots/selection-error.png) | 选区 · 读取失败 | 选区不可读取时不发起模型请求，允许手动输入或重新读取。 |
| [aligned.png](screenshots/aligned.png) | 翻译 · 逐句对照 | 按句配对显示。 |
| [book-list.png](screenshots/book-list.png) | 生词本 · 列表 |  |
| [book-detail.png](screenshots/book-detail.png) | 生词本 · 详情 |  |
| [history-list.png](screenshots/history-list.png) | 历史 · 列表 |  |
| [history-detail.png](screenshots/history-detail.png) | 历史 · 详情 |  |
| [settings.png](screenshots/settings.png) | 设置 · 显示 |  |
| [settings-prompts.png](screenshots/settings-prompts.png) | 设置 · Prompt |  |
| [settings-shortcuts.png](screenshots/settings-shortcuts.png) | 快捷键 · 录制 |  |
| [permission.png](screenshots/permission.png) | 权限 · 未授权 | 选区读取不可用时仍支持粘贴输入。 |
| [unconfigured.png](screenshots/unconfigured.png) | 服务 · 未配置 | 只在需要配置时引导进入完整设置窗口。 |
| [book-empty.png](screenshots/book-empty.png) | 生词本 · 空状态 | 完整窗口管理积累，空状态不伪造收藏。 |
| [history-empty.png](screenshots/history-empty.png) | 历史 · 空状态 | 成功生成后才出现历史记录。 |
| [no-results.png](screenshots/no-results.png) | 生词本 · 无搜索结果 | 允许清除筛选，保留原有收藏。 |
| [shortcuts.png](screenshots/shortcuts.png) | 应用 · 快捷键 | 查看常用操作快捷键与作用范围。 |
| [workspace.png](screenshots/workspace.png) | 应用 · 文本处理 | 同一页面选择翻译或润色，结果可复制，不包含选区替换。 |
| [workspace-collapsed.png](screenshots/workspace-collapsed.png) | 应用 · 文本处理（侧栏收起） | 工具栏跨整窗，侧栏可收起；同一页选择翻译或润色。 |
| [workspace-narrow.png](screenshots/workspace-narrow.png) | 应用 · 文本处理（窄窗口） | 内容区不足 720px 时，原文与译文从并排改为上下堆叠。 |
| [menubar.png](screenshots/menubar.png) | 菜单栏 · 常驻 | 点击菜单栏图标打开主界面；快捷键唤起浮动工具栏。 |
