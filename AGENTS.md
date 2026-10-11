# AGENTS.md

Owlet 的仓库级约定。产品行为以 `spec/` 为准，本文只说「怎么做」，不复述行为。

## 命令

```sh
mise run check    # lint + 生成工程 + 测试；pre-commit 与 CI 都跑它
mise run format   # swift-format 就地格式化，改完 Swift 先跑再 check
mise run dev      # 构建并重启本机 Owlet
mise run prod     # Release 通用二进制，校验后打包到 dist/（版本取自 project.yml）
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

## 版本

发版只改 `project.yml` 的 `MARKETING_VERSION`（用户看到的版本）与 `CURRENT_PROJECT_VERSION`（同一版本下每次交付递增的构建号），`scripts/prod-build.sh` 从产物的 `CFBundleShortVersionString` 读取并用于命名与打印。**不要**另建 VERSION 文件或 tag 作为第二真源。若把 `MARKETING_VERSION` 去掉，脚本会回退到提交号并明确标注。

## 界面语言

- 应用以**英文为源语言**：`strings/translations.json` 以英文为键，存简体中文、繁體中文、日本語的译文；
  `Owlet/Localizable.xcstrings` 由 `scripts/build-strings.py` 从它生成，**不要手改**（`mise run lint` 校验一致）。
- 界面文字**必须**经 `L10n.shared.string("English key")` 取（视图用 `Text(L10n.shared.string(…))`）。
  不要用裸字面量或 `String(localized:)`：它们经 `Bundle.main` 解析，只在启动时定一次，切换语言不会跟着变。
  占位符用显式参数（`L10n.shared.string("%@ · %@", a, b)`），**不要**在键里写 `\(...)` 插值，那样插值会先
  求值而匹配不到含 `%@` 的键；也不要把 `LocalizedStringResource` 插进字符串，那会打印它的调试描述。
- 占位符按**参数类型**选：字符串用 `%@`，整数（`Int`、`.count`、`OSStatus`）用 `%lld`。`%@` 只接受
  对象，传整数会得到 `does not match expected '%lld'` 的运行时错误；`String(format:)` 会检查，别猜。
- 发给模型的文字（`Owlet/ModelPrompts.json` 的两段默认 Prompt、任务描述与示例）**不本地化**。
- `mise run i18n`（需先构建）列出「翻译后会显示成中文」的界面串：它以产物里的 `en.lproj` 为准，
  比对源码中的中文字面量。新增界面文字后跑一次，别让缺口留到用户那里。

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
