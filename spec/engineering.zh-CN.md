[English](engineering.md) · [简体中文](engineering.zh-CN.md)

# Owlet 工程规范

状态：原生应用已实现，本文记录现行工程约定。产品范围沿用 [product.md](product.zh-CN.md)，不创建重复规格体系。

## 目标与范围

面向母语中文、主要阅读和书写英语及日语的个人用户，完成翻译、润色、安全替换和主动积累表达。支持其他语言，首版无复习、账号、同步。已确认交互以产品规范为准；早期的 HTML 交互原型（`design/`）已退役。

## 技术约束

macOS 26.0 起；SwiftUI + AppKit、URLSession、SwiftData。Keychain 保存密钥，普通配置不得保存明文密钥。JSON 契约以 `llm/contract.md` 为准，已确认。

## 命令

```sh
mise run check    # lint + 生成工程 + 测试；pre-commit 与 CI 都跑它
mise run format   # swift-format 就地格式化
mise run dev      # 构建并重启本机 Owlet
mise run prod     # Release 构建，校验后打包到 dist/
```

早期浏览器原型的 `open design/index.html` 与控制台检查（`checkDesignStates()`、`checkFlowBoard()`）已随原型退役。

工程由 `project.yml`（XcodeGen）生成，`Owlet.xcodeproj` 不入库。`mise run check` 执行 `git diff --check`、`swift-format lint --strict`、`scripts/build-strings.py --check`，生成工程并运行测试；`mise run setup` 安装 pre-commit hook，CI 同样运行 `mise run check`。`mise run prod` 走 [scripts/prod-build.sh](../scripts/prod-build.sh) 产出 Release 构建：默认同时产出 universal 与 arm64，按工程配置签名（`Signing.xcconfig`，本机可用 `Signing.local.xcconfig` 覆盖），也可用 `--identity`／`--team` 指定；打包前校验签名、最低系统版本、图标与调试授权。

## 结构

- `Owlet/`：应用源码，按功能分目录（`App`、`Processing`、`Learning`、`Vocabulary`、`History`、`Lookup`、`Selection`、`Shortcuts`、`Settings`、`LLM`、`Debug` 等）。
- `OwletTests/`：Swift Testing 测试，目录与 `Owlet/` 对应。
- `spec/product.md`、`spec/DESIGN.md`：产品与视觉决策。
- `spec/{processing,learning,vocabulary,history,settings}/features/`：行为验收场景。
- `spec/llm/`：默认 Prompt 与 JSON 契约。
- `docs/roadmap.md`：尚未完成的工作。
- 不预建空模块。

## 代码风格

Swift 6，严格并发；Swift 标准命名：类型 UpperCamelCase，成员 lowerCamelCase。颜色只用系统语义色与系统强调色（见 [DESIGN.md](DESIGN.zh-CN.md)）。示例是约定，不代表已有实现：

```swift
struct TranslationSegment: Decodable {
    let source: String
    let target: String
}
```

仅实现当前消费者所需字段；以上字段须随最终 JSON 契约校正。异步操作必须绑定操作身份，取消或过期响应不得更新结果或写回原文。

## 测试策略

用 Swift Testing 验证契约解析、取消、写回失败与数据隔离；UI／辅助功能使用系统集成测试和人工兼容性检查。Gherkin 目前未绑定测试实现。

固定模型响应覆盖成功、网络失败、无效 JSON；普通自动测试不调用真实模型。写回须覆盖无权限、无所属应用、取消和迟到响应。历史删除不得影响收藏。学习默认不发请求，点击或开启自动请求后才请求。

不设任意覆盖率数字；以上高风险行为必须有对应测试。仅在配置完成后进行显式真实服务检查。

## 边界

- Always：更新行为规格，校验模型响应，保护原文，运行对应验证并报告尚未验证的范围。
- Ask first：改变已确认范围、最终 JSON 契约或原生技术方案；新增外部服务与依赖。
- Never：提交密钥、迟到响应写回、自动收藏。

## 成功条件

1. 四个全局快捷键唤起对应操作；菜单栏打开主界面，主界面无返回浮窗按钮。
2. 首次处理使用紧凑提示；工具栏尚未展开时遇阻显示紧凑提示及对应入口；已展开后重试或遇错保持展开，并在内容区提示问题。
3. 分区／逐句显示切换不发新请求，复制与写回只输出结果。
4. 未获可靠写回目标时不替换；取消与旧响应不能写回。
5. 学习默认手动，翻译／润色各自可开启自动请求；收起后展开不重复请求。
6. 收藏与历史独立持久化；Key 存入 Keychain。
7. 中性背景，主按钮／选中态／焦点使用系统强调色；动效尊重减少动态效果。

## 已确认

JSON 字段与校验规则、SwiftUI + AppKit + SwiftData、工程名 Owlet、快捷键无默认、选区回退、菜单栏常驻并带 Dock 图标，见 [product.md](product.zh-CN.md) 与 `llm/contract.md`。

签名与分发见 [scripts/prod-build.sh](../scripts/prod-build.sh)：未给 `--notarise` 时产物未经公证，在另一台 Mac 上首次启动需右键「打开」。
