# AGENTS.md

Owlet 的仓库级约定。产品行为以 `spec/` 为准，本文只说「怎么做」，不复述行为。

## 命令

```sh
mise run check    # lint + 生成工程 + 测试；pre-commit 与 CI 都跑它
mise run format   # swift-format 就地格式化，改完 Swift 先跑再 check
mise run dev      # 构建并重启本机 Owlet
mise run prod     # Release 通用二进制，校验后打包到 dist/
scripts/local-check.sh   # 同 check，但产物只写进本仓库的 .build/derived（可选）
```

`mise run check` 会把编译产物写进 `~/Library/Developer/Xcode/DerivedData`；要求临时文件不出仓库时用 `scripts/local-check.sh`（`lint`／`test`／默认两者），它只多一个 `-derivedDataPath`。

**判断结果看退出码，不要 grep 日志。** `xcodebuild` 的失败行长成 `Failing tests:` /
`** TEST FAILED **`，用小写 `error:` 过滤会漏掉，把红的当绿的。

## 只用原生组件

- 界面一律用 macOS 26 原生 SwiftUI / AppKit 组件，**不手写控件**：不加自定义颜色、tint、
  填充、边框、渐变、光晕、阴影、圆角样式或自定义 `ButtonStyle`。
- 规则全文与判据见 `spec/DESIGN.md`；逐屏组件对照见 `docs/liquid-glass-components.md`。
- 常见落法：页面用 `Form` + `Section`（`.formStyle(.grouped)`），分组容器、卡片、列表行都用
  系统组件；长文本折叠用 `DisclosureGroup`；错误用 `Label(systemImage:)` + 系统红；动作行用
  `PageFooter` + `.glass` / `.glassProminent`。**不要画圆角卡片背景**。
- 加新界面前先查 `docs/liquid-glass-components.md` 的逐屏表，并把它补进去。

## 界面语言

- 应用以简体中文为源语言，`Owlet/Localizable.xcstrings` 另存 English、繁體中文、日本語；该文件由
  `scripts/build-strings.py` 的对照表生成，**不要手改**，改完跑一次脚本（`mise run lint` 会校验两者一致）。
- 界面文字用 `Text("中文源串")` 即可被抽取；需要拼装的用 `String(localized:)`，占位用 `\(...)`。
- 发给模型的文字（`DefaultPrompts` 的两段默认 Prompt、提示词说明与示例）**保持中文**，不本地化；
  用户可见的错误文案、按钮、标题一律本地化。

## 规格先行

- 行为变更先落到 `spec/{processing,learning,vocabulary,history,settings}/features/*.feature`；
  需要取舍的写 `spec/settings/decisions/BDR-*.md`（状态写「已确认／已实现」）。
- 实现后同步：`spec/product.md`、`docs/unimplemented-features.md`、根 `README.md` 里的
  状态数／分区数／提案数必须与实际一致。
- 新工作进 `tasks/todo.md`（T 编号，含验收条件与验证），完成后同步 `tasks/plan-remaining.md`。

## 模型调用

- `spec/llm/contract.md` 是硬约束：结构、目标语言、原文拼接三项都要在本地校验，校验失败
  不得当成成功结果，也不得写回。
- 契约失败要能诊断：`ModelError` 区分 `format` / `targetMismatch` / `sourceMismatch`，
  原始请求与返回记录在隐藏调试页（`Owlet/Debug/`，设置里的「调试」开关控制，默认关闭、
  只在内存、不含 API Key）。
- 供应商差异走 `Provider` 的能力开关（如 DeepSeek 只支持 `json_object`，不支持 `json_schema`）。

## Swift 与测试

- Swift 6，严格并发；类型 UpperCamelCase、成员 lowerCamelCase；文件头不加模板注释。
- 测试用 Swift Testing（`@Test` / `#expect` / `@Suite`），`@testable import Owlet`。
- 依赖外部状态的地方都要可注入：`UserDefaults(suiteName: "…")`、`ModelClient(transport:)`、
  `PanelController` 的 `read` / `write` / `makeWindow`。测试不得读开发者真实设置，也不得
  调用真实模型。
- 注释写「为什么」，不写「做了什么」；一句话能说清就用一句话。

## 提交

- Conventional Commits，正文用中文；一次提交只做一件事。
- 不提交密钥；API Key 只进 Keychain。调试与日志里不得出现 Key。
- 提交前 `mise run check` 必须通过（pre-commit hook 会再跑一次）。
