# Owlet 工程规范草案

状态：Specify，待用户审阅；不授权开始原生实现。产品范围沿用 [product.md](product.md)，不创建重复规格体系。

## 目标与范围

面向母语中文、主要阅读和书写英语及日语的个人用户，完成翻译、润色、安全替换和主动积累表达。支持其他语言，首版无复习、账号、同步。已确认交互以产品规范为准，HTML 是交互示例，不是真实模型或选区实现。

## 技术约束

macOS 26.0 起；SwiftUI + AppKit、URLSession、SwiftData 为既有计划中的建议，待确认。Keychain 保存密钥，普通配置不得保存明文密钥。JSON 契约以 `llm/contract.md` 为准，已确认。

## 命令

当前可执行：

```sh
open design/index.html
git diff --check
```

浏览器控制台可执行 `checkDesignStates()` 与 `checkFlowBoard()`，检查设计状态布局和状态图覆盖；不代表原生验收通过。

原生 build/test 命令见 `../tasks/plan.md`，属于拟议命令；仓库尚无 Xcode 工程，不能声称可运行。工程创建后必须更新为真实 project、scheme 与测试 target。工程由 `project.yml`（XcodeGen）生成，`Owlet.xcodeproj` 不入库。`mise run check` 执行 `git diff --check`、`swift-format lint --strict`、生成工程并运行测试；`mise run setup` 安装 pre-commit hook，CI 同样运行 `mise run check`。

## 结构

- `design/index.html`：单文件交互原型。
- `spec/product.md`、`spec/DESIGN.md`：产品与视觉决策。
- `spec/{processing,learning,vocabulary,history,settings}/features/`：行为验收场景。
- `spec/llm/`：默认 Prompt 与 JSON 契约。
- `tasks/plan.md`、`tasks/todo.md`：已有计划和任务，尚未实施。
- 原生源码与测试目录在工程方案确认后创建，不预建空模块。

## 代码风格

原型沿用当前无依赖 JavaScript/CSS；颜色采用 OKLCH，语义色独立于玫瑰主色。原生建议 Swift 标准命名：类型 UpperCamelCase，成员 lowerCamelCase。示例是约定，不代表已有实现：

```swift
struct TranslationSegment: Decodable {
    let source: String
    let target: String
}
```

仅实现当前消费者所需字段；以上字段须随最终 JSON 契约校正。异步操作必须绑定操作身份，取消或过期响应不得更新结果或写回原文。

## 测试策略

原生建议 Swift Testing 验证契约解析、取消、选区失效与数据隔离；UI／辅助功能使用系统集成测试和人工兼容性检查。Gherkin 目前未绑定测试实现。

固定模型响应覆盖成功、网络失败、无效 JSON；普通自动测试不调用真实模型。写回须覆盖选区变化、焦点变化、取消和迟到响应。历史删除不得影响收藏。学习默认不发请求，点击或开启自动请求后才请求。

不设任意覆盖率数字；以上高风险行为必须有对应测试。仅在配置完成后进行显式真实服务检查。

## 边界

- Always：更新行为规格，校验模型响应，保护原文，运行对应验证并报告尚未验证的范围。
- Ask first：改变已确认范围、最终 JSON 契约或原生技术方案；新增外部服务与依赖。
- Never：提交密钥、未确认焦点元素与选中文本即粘贴覆盖选区、迟到响应写回、自动收藏、把示例原型称为原生实现。

## 成功条件

1. 三种快捷键唤起对应操作；菜单栏打开主界面，主界面无返回浮窗按钮。
2. 首次处理使用紧凑提示；工具栏尚未展开时遇阻显示紧凑提示及对应入口；已展开后重试或遇错保持展开，并在内容区提示问题。
3. 分区／逐句显示切换不发新请求，复制与写回只输出结果。
4. 未获可靠写回目标时不替换；取消与旧响应不能写回。
5. 学习默认手动，翻译／润色各自可开启自动请求；收起后展开不重复请求。
6. 收藏与历史独立持久化；Key 存入 Keychain。
7. 中性背景，玫瑰色主按钮／选中态／焦点，呼吸灯尊重减少动态效果。

## 已确认

JSON 字段与校验规则、SwiftUI + AppKit + SwiftData、工程名 Owlet、快捷键无默认、选区回退、仅菜单栏及分发方式，见 `../tasks/plan.md` 与 `llm/contract.md`。

签名分发在发布阶段确定，不阻塞本地工程规格审阅。本次仅整理 Specify，不推进新的 Plan、Tasks 或 Implement。
