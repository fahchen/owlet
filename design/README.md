# Design screenshots

Source: `index.html`. One PNG per state.

This board covers the screens the app has shipped and, in separate bands, proposal screens for features that are not implemented yet.
Proposal frames carry a 未实现 badge and their bands are titled 提案（未实现）.

The features still without a mockup, and the mapping from each proposal to its task, are listed in [../docs/unimplemented-features.md](../docs/unimplemented-features.md).

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
| [workspace-error.png](screenshots/workspace-error.png) | 文本处理 · 请求失败 | 行内提示失败原因，并提供服务设置入口。 |
| [workspace-unconfigured.png](screenshots/workspace-unconfigured.png) | 文本处理 · 服务未配置 | 缺少服务配置时提示并指向设置。 |
| [workspace-learning.png](screenshots/workspace-learning.png) | 文本处理 · 学习表达 | 结果下方的学习表达区块：勾选推荐后主动入库。 |
| [workspace-collapsed.png](screenshots/workspace-collapsed.png) | 文本处理 · 侧栏收起 | NavigationSplitView 收起侧栏后页面不变。 |
| [settings-shortcuts.png](screenshots/settings-shortcuts.png) | 设置 · 快捷键 | 设置窗口的快捷键页：三个全局动作未录制，面板内固定键只读。 |
| [settings-shortcuts-recording.png](screenshots/settings-shortcuts-recording.png) | 设置 · 快捷键 · 录制中 | 录制按钮等待新组合键；Esc 取消，Delete 清除。 |
| [settings-shortcuts-conflict.png](screenshots/settings-shortcuts-conflict.png) | 设置 · 快捷键 · 组合冲突 | 与已录制动作冲突时提示换一个组合。 |
| [settings-general.png](screenshots/settings-general.png) | 设置 · 通用 | 通用页：学习开关、浮窗位置与调试开关，各自成组。 |
| [settings-language-empty.png](screenshots/settings-language-empty.png) | 设置 · 语言 | 语言页：语言子集，加目标语言的兜底目标（映射表为空）。 |
| [settings-language-rows.png](screenshots/settings-language-rows.png) | 设置 · 语言 · 已添加映射 | 语言页：映射表已有两行，一个源语言只保留一条。 |
| [settings-model.png](screenshots/settings-model.png) | 设置 · 模型 | 模型页：服务与模型两组，Base URL、Key、模型名称与思考强度。 |
| [settings-model-openai.png](screenshots/settings-model-openai.png) | 设置 · 模型 · 自定义服务商 | 模型页：OpenAI Compatible 时模型名称是自由填写。 |
| [settings-model-failed.png](screenshots/settings-model-failed.png) | 设置 · 模型 · 模型列表失败 | 模型页：取模型列表失败时就地提示并给重试。 |
| [settings-model-prompts.png](screenshots/settings-model-prompts.png) | 设置 · 模型 · Prompt | 模型页下半部分：翻译与润色各一个编辑器分组，标题右侧是「默认」标记与 info 图标。 |
| [settings-model-prompts-customized.png](screenshots/settings-model-prompts-customized.png) | 设置 · 模型 · Prompt · 已自定义 | 改过之后「默认」标记换成「恢复默认」按钮，位置不变。 |
| [settings-debug.png](screenshots/settings-debug.png) | 设置 · 调试 | 调试页：捕获到的请求各占一行，显示操作与原文摘要，行尾的展开按钮打开请求体、返回与提交原文。 |
| [settings-debug-open.png](screenshots/settings-debug-open.png) | 设置 · 调试 · 展开一条 | 展开一条记录：失败原因、原文差异（若有）与三段原始内容，附复制这条记录。 |
| [settings-debug-empty.png](screenshots/settings-debug-empty.png) | 设置 · 调试 · 无记录 | 调试页空状态；记录只在内存，重启即清空。 |
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
| [direct-selection-error.png](screenshots/direct-selection-error.png) | 直接替换 · 读取失败 | 与「选区 · 读取失败」是同一屏幕：直接替换流程读取不到文字时的紧凑条提示；Esc 关闭并取消。 |
| [direct-permission.png](screenshots/direct-permission.png) | 直接替换 · 权限未授权 | 与「权限 · 未授权」是同一屏幕：直接替换流程的紧凑条内进入设置。 |
| [direct-unconfigured.png](screenshots/direct-unconfigured.png) | 直接替换 · 未配置 | 与「服务 · 未配置」是同一屏幕：直接替换流程的紧凑条内进入设置。 |
| [direct-error.png](screenshots/direct-error.png) | 直接替换 · 请求失败 | 与「请求 · 失败」是同一屏幕：直接替换流程的紧凑条提示；Esc 关闭并取消。 |
| [direct-format-error.png](screenshots/direct-format-error.png) | 直接替换 · 格式错误 | 与「请求 · 格式错误」是同一屏幕：直接替换流程不写回原文。 |
| [direct-cancelled.png](screenshots/direct-cancelled.png) | 直接替换 · 已取消 | 与「请求 · 已取消」是同一屏幕：直接替换流程的紧凑条内展示取消。 |
| [result.png](screenshots/result.png) | 翻译 · 结果 | 展开面板：头部操作选择、原文、译文与底部复制替换。 |
| [polish.png](screenshots/polish.png) | 润色 · 结果 | 同一面板，标签改为润色结果与保留原意。 |
| [long.png](screenshots/long.png) | 翻译 · 长文本 | 结果滚动，复制与替换固定在底部。 |
| [result-loading.png](screenshots/result-loading.png) | 翻译 · 结果区处理中 | 已展开时重新处理保持展开，在结果区显示加载。 |
| [result-unwritten.png](screenshots/result-unwritten.png) | 翻译 · 未能写回 | 结果仍保留，就地说明未能写回并可复制；同一布局也用于「原选区不可编辑」。 |
| [result-notice.png](screenshots/result-notice.png) | 翻译 · 结果区失败 | 展开态失败不收起面板：结果区隐藏，行内提示加底部重试。 |
| [result-cancelled.png](screenshots/result-cancelled.png) | 翻译 · 结果区已取消 | 取消后结果区隐藏，行内提示与底部都回到重新处理。 |
| [empty.png](screenshots/empty.png) | 输入 · 无选区 | 展开面板中原文为空：来源字段可编辑，清空后 canRetry 为假，头部不显示重新处理，动作行默认分支没有可重试动作时不渲染按钮，底部只留快捷键提示。 |
| [menubar.png](screenshots/menubar.png) | 菜单栏 · 常驻 | 点击菜单栏图标展开菜单，不直接开窗。 |
| [menubar-menu.png](screenshots/menubar-menu.png) | 菜单栏 · 展开菜单 | 菜单：打开 Owlet、三个快捷键状态、设置…（⌘,）与退出。 |
| [book-list.png](screenshots/book-list.png) | 生词本 · 列表 | 工具栏搜索与语言筛选，内容区按语言列出收藏的表达与释义。 |
| [book-detail.png](screenshots/book-detail.png) | 生词本 · 详情 | 详情可编辑表达与中文释义，并保留原句语境。 |
| [book-empty.png](screenshots/book-empty.png) | 生词本 · 空状态 | 没有收藏时给出说明与“开始翻译”入口，不伪造条目。 |
| [no-results.png](screenshots/no-results.png) | 生词本 · 无搜索结果 | 搜索无匹配时给出“清除筛选”，保留原有收藏。 |
| [history-list.png](screenshots/history-list.png) | 历史 · 列表 | 工具栏搜索与类型筛选，列出翻译与润色的原文与结果。 |
| [history-detail.png](screenshots/history-detail.png) | 历史 · 详情 | 详情展示原文与结果，可复制，也可从历史收藏。 |
| [history-empty.png](screenshots/history-empty.png) | 历史 · 空状态 | 没有记录时给出说明与“开始翻译”入口。 |
| [learning.png](screenshots/learning.png) | 学习 · 展开 | 展开结果内的学习表达区块：勾选推荐后主动入库。 |
| [learning-loading.png](screenshots/learning-loading.png) | 学习 · 整理中 | 学习请求独立于主结果，整理中不阻塞复制与替换。 |
| [learning-error.png](screenshots/learning-error.png) | 学习 · 生成失败 | 生成失败只重试学习内容，不重新翻译。 |
| [learning-empty.png](screenshots/learning-empty.png) | 学习 · 无推荐 | 没有推荐时不强凑数量，保留手动收藏。 |
| [saved.png](screenshots/saved.png) | 收藏 · 已入库 | 收藏后就地反馈并保留入口，不跳转打断工作。 |
| [aligned.png](screenshots/aligned.png) | 翻译 · 逐句对照 | 原文与译文按语义句子配对，换行不改变对应关系。 |
| [workspace-narrow.png](screenshots/workspace-narrow.png) | 翻译与润色 · 窄窗口 | 内容区不足 720pt 时原文与译文上下平分高度；宽窗口时左右平分宽度。 |
| [success.png](screenshots/success.png) | 直接替换 · 完成 | 写回成功后确认替换并保留译文，按 Esc 或完成返回工作；应用现在写回成功即关闭面板，没有确认屏。 |
| [workspace-auto.png](screenshots/workspace-auto.png) | 文本处理 · 自动目标 | 工具栏目标语言为“自动”，显示按映射解析出的目标；手动选择语言可持久覆盖，直到切回自动。 |
| [workspace-target-pinned.png](screenshots/workspace-target-pinned.png) | 文本处理 · 手动指定目标 | 用户显式选择了日本語：该选择覆盖映射并持久保留，控件不再显示自动。 |
