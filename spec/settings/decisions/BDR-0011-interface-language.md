# BDR-0011：界面语言支持四种，默认跟随系统

状态：已实现（2026-10-11）。来源：用户要求「实现系统的 i18n，支持英语、简体和繁体中文、日语」。

## 决定

- **四种界面语言**：简体中文、繁體中文、English、日本語。默认跟随系统；系统语言不在四者之内时回落到简体中文。
- **设置里可覆盖**：设置的「通用」页有「界面语言」，可选「跟随系统」或四种之一，选择持久化。写入 `AppleLanguages` 并**在构建任何视图之前**生效，因此改动在下次启动时切换，而不是在应用内再实现一套语言解析。
- **语言名跟随界面语言，但选择器例外**：内容语言（目标语言、兜底目标、映射表里的语言）在英文界面下显示 `Japanese` 而不是 `日本語`。设置里的「界面语言」选择器是唯一例外——它必须把每种语言写成自己的名字，否则用户在切换前读不懂；为此该选择器用 `Text(verbatim:)` 绕过字符串目录。
- **发给模型的文字不本地化**：`Owlet/ModelPrompts.json`（经 `DefaultPrompts` 读取）里的提示词说明、学习任务描述与示例 JSON 不随界面语言变化。模型行为与契约因此不随界面语言改变，`spec/llm/contract.md` 也不受影响。
- **两段默认 System Prompt 例外**（2026-10-16 用户要求「切换系统语言时，用户没编辑过就换成那种语言的 Prompt」）：翻译与润色这两段 Prompt 是用户在模型页**读并编辑**的文字，界面语言换了却还是旧语言，就读不懂也改不懂。`ModelPrompts.json` 因此给它们每种界面语言一份，键为 `<名字>.<locale>`（`translate.zh-Hans` 等），裸键 `translate`／`polish` 放英文原文，也是没有对应语言条目时的回落。取值时机是**每次读取时**（`DefaultPrompts.text` 读 `L10n.currentLanguage`），所以请求发出时用的就是当前界面语言那一份。用户编辑过则存的是自定义内容，不随语言变化；判断「编辑过」按「等于任意一种语言的默认」来算，这样切换语言时编辑器里残留的旧语言默认不会被当成编辑而钉住旧语言。
- **目录是生成物**：`Owlet/Localizable.xcstrings` 由 `scripts/build-strings.py` 从 `strings/translations.json` 生成，源语言为英文，英文原文**就是目录键**，源码经 `L10n.shared.string("English key")` 取字符串。`mise run lint` 校验两者一致，避免同一文案在一处改了另一处忘改。
- **分类不靠文案**：凡是「按失败类型选择恢复入口」「按类型决定展示哪种比较」这类判断，一律改为按 `ModelError.Kind`。原先有三处拿本地化文案当标识，翻译后会静默失效（详见下文）。

## 后果与代价

- 新增界面文字必须进对照表，否则该语言下显示中文；`mise run i18n` 用来发现这种缺口。
- 语言名与选择器的例外是刻意的：请勿为「一致性」把它改成跟随界面语言。
- 集成测试若断言界面文案，会在不同语言的机器上假失败；断言应针对结构与行为，不针对措辞。

## 影响

- `Owlet/Localizable.xcstrings`（新增，236 条 × 4 语）、`scripts/build-strings.py`、`scripts/check-i18n.py`。
- `Owlet/Settings/AppLanguage.swift`（新增）：`resolve` 为纯函数，覆盖「已保存的选择／跟随系统／不认识的值／没有匹配语言」四类输入。
- `project.yml`：`developmentLanguage: zh-Hans`；`mise.toml`：lint 增加目录一致性校验，新增 `i18n` 任务。
- `ModelError.Kind`：从「契约／服务」两类扩为「契约／连接／服务」，面板与文本处理页据此选恢复入口。
- `DebugExchange`：带上 `failureKind`，`sourceDivergence` 不再比对 `failure == ModelError.sourceMismatch.message`。
- `spec/settings/decisions/BDR-0003`：语言名的显示规则改为跟随界面语言。
