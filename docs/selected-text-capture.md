# macOS 选中文字读取方案

状态：AX 主路径已实现（`96f8f2e`、`ef8682e`、`671ebd3`），实机兼容性待验证。适用于 Owlet 的 macOS 26+ 原生应用。

## 目标与边界

用户通过已录制的快捷键触发翻译、润色或翻译并替换时，在浮窗取得焦点之前读取外部应用的选中文字。没有有效原文时不请求模型，提供权限设置或手动输入入口。

本方案聚焦 Accessibility（AX）读取主路径，不新增依赖，不涉及 OCR、持续监控选区或替换算法。快捷键沿用现有录制设置，不指定默认组合。

[实现计划](../tasks/plan.md)已约定模拟复制／粘贴并恢复剪贴板的兼容回退；本文不撤销该约定，也不将其混入 AX 读取。本文的失败行为描述 AX 主路径的返回结果；完整流程如需自动回退，应另行落实剪贴板恢复和焦点校验后再接入。当前 AX 主路径不读取、清空或写入剪贴板。

## 实现位置

- [SelectionBridge.swift](../Owlet/Selection/SelectionBridge.swift)：`read(completion:)` 按下述流程读取；`SerialLatest` 工作队列；可注入的 AX 属性读取器。
- [PanelController.swift](../Owlet/App/PanelController.swift)：`trigger` 分配操作标识，异步接收读取结果并按工具栏是否展开呈现错误。
- 测试：[SelectionBridgeTests.swift](../OwletTests/Selection/SelectionBridgeTests.swift)、[SerialLatestTests.swift](../OwletTests/Selection/SerialLatestTests.swift)、[PanelControllerTests.swift](../OwletTests/App/PanelControllerTests.swift)。

## 读取流程

1. 快捷键触发后立即使旧操作失效，取消旧模型请求，分配本次操作标识。
2. 在主线程检查 `AXIsProcessTrusted()`，记录 `NSWorkspace.shared.frontmostApplication` 及其 PID。未授权返回 `.permission`；无前台应用或来源为 Owlet 自身，返回 `.unreadable`。
3. 在专用串行工作队列创建 `AXUIElementCreateApplication(pid)`，后续读取限定于这一应用。设置 AX 消息超时，再读取 `kAXFocusedUIElementAttribute`。
4. 核验返回对象类型，读取 `kAXSubroleAttribute`。若为 `kAXSecureTextFieldSubrole`，立即返回 `.secure`，不得读取文本或选区内容。无法确认必要属性时按读取失败处理。
5. 读取选区。先看聚焦元素自己的 `kAXSelectedTextAttribute`；Safari 的网页选区只通过 `kAXSelectedTextMarkerRangeAttribute` 加 `kAXStringForTextMarkerRangeParameterizedAttribute` 暴露，所以在同一元素上再试一次文本标记范围。仅接受字符串，用去首尾空白后的副本判断是否为空，实际保留原文空白与换行。
6. 聚焦元素没有选区时向外找：先沿 `kAXParentAttribute` 向上最多 8 层（网页选区常落在 `AXWebArea` 上），再从聚焦元素的子树开始、最后到所属窗口做广度优先搜索，最多 400 个节点（PDF 阅读器的文字层在子节点里）。每个元素在发消息前都设置 AX 消息超时，所有读取共用一次触发预算，预算用尽后读取返回 nil，搜索随之结束。
7. 仍然找不到就复制选区：保存剪贴板，合成 ⌘C，最多轮询 20×20ms 等剪贴板变化，取到非空文本后立即把剪贴板放回；拿不到新内容仍返回 `.unreadable`。密码字段在第 4 步已经返回 `.secure`，不会走到这里。
8. 选区范围（`SelectedRange`）只在放置浮窗需要跟随选区时读取：解码 `kAXSelectedTextRangeAttribute`，经 CF 类型与 AXValue 类型检查。范围缺失只影响放置位置，不影响翻译。
9. 回到主线程，确认操作未过期、未取消且前台应用仍为原 PID，才接收结果。成功时先保存 `Selection`、导入输入，再显示浮窗并启动对应模型请求。

读取文字成功不等于写回成功。写回不再比较捕获时的文本与选区范围：先按捕获到的元素直接尝试辅助功能写入（快，且不碰剪贴板），元素拒绝这一写入时改走粘贴——把结果放进剪贴板、把所属应用前置、合成 ⌘V，停留 350ms 让目标应用读完剪贴板后放回用户原来的内容。仅在无辅助功能权限、所属应用已退出或无法前置时拒绝，此时结果仍可复制。

## 响应时间与并发

- 建议初始参数：单次 AX 消息超时 **100 ms**，从触发起的总等待预算 **150 ms**。这是待实机验证的工程值，不是系统保证。
- 总预算覆盖排队与全部 AX 读取；每步开始前检查是否已过期，避免多次调用逐项累积等待。
- 到达总预算即按 `.unreadable` 呈现恢复入口；已经执行的同步 AX 调用可能稍后才返回。总超时只停止接收结果，不宣称已终止系统调用。
- 串行队列最多保留一个执行中的读取和一个最新待处理操作；新的触发取代旧待处理操作，避免连续快捷键造成无界排队。
- 使用 `PanelController` 的操作标识机制统一约束读取与模型请求。新触发、Esc 关闭或取消均使旧标识失效；迟到结果不得改输入、弹出浮窗、请求模型或恢复替换意图。
- UI 状态只在主线程更新。工作队列内部持有 AX 对象；实现时遵守 Swift 并发隔离规则，不为跨执行器传递对象而随意添加 `@unchecked Sendable`。

## Electron 兼容

部分 Electron 应用未主动建立辅助功能树，可在应用 AX 对象上尝试设置 `AXManualAccessibility = true`，再读取焦点控件。

此属性属于应用兼容约定，不是所有应用都支持的公共 AX 属性。设置失败不能单独判定读取失败，仍尝试标准读取；首次设置后辅助功能树也可能尚未就绪。本次按超时策略退出，由用户重新触发，不增加固定睡眠或后台轮询。

兼容边界：当前实现对所有前台应用无条件尝试设置该属性（非 Electron 应用返回错误并被忽略），随后走标准读取。尚未在真实 Electron 应用上实测，支持范围待实机验证后记录。

## 权限、错误与隐私

| 结果 | 处理 |
|---|---|
| `.permission` | 显示辅助功能权限提示及系统设置入口；不在每次读取时弹授权对话框 |
| `.secure` | 不访问文本内容；界面按无法读取呈现 |
| `.unreadable` | 无选区、应用不支持、属性异常、来源变化或超时；不发起无原文请求 |
| 成功 | 仅当前有效操作导入文字并执行对应处理 |

工具栏尚未展开时显示紧凑提示；已展开时保留内容区并显示错误。用户主动选择手动输入后进入完整窗口，该输入不继承外部选区的写回权限。具体交互遵循[产品定义](../spec/product.md)与[错误呈现决策](../spec/processing/decisions/BDR-0002-preserve-open-toolbar-on-error.md)。

仅在用户触发时读取，不记录选中文字、文档路径或 AX 属性内容到诊断日志。`AXUIElement` 和来源上下文只保留于当前操作，不持久化为可恢复的写回权限。复制回退与写回粘贴都会临时改写剪贴板，并在各自完成后放回用户原来的内容。

## 实施顺序（已完成）

1. **修正捕获顺序与来源一致性**：沿用 `SelectionBridge`，先判密码字段再取文字，通过固定 PID 查找焦点控件，补齐返回类型检查，复用一次读取的原文。
2. **使读取有界且不阻塞 UI**：将 `PanelController.read` 接口改为可异步完成，接入工作队列、总预算及操作标识；保留现有失败呈现。
3. **验证应用兼容性**：加入 Electron 的按需兼容处理，实测后记录支持范围；不提前建立应用适配器框架。

每一步仅改动对应读取链路并补充必要测试，不在本方案中扩展写回、历史或快捷键配置。

## 验收

自动化检查（已覆盖）：

- [x] 密码字段：记录属性调用，断言从未请求文本和选区（`secureFieldNeverReadsTextOrRange`）。
- [x] 文本只读取一次，选区范围经类型检查后解码（`textIsReadOnceAndTheRangeIsDecoded`）。
- [x] 选区在聚焦元素、祖先、子树与网页文本标记范围里都能找到，空白选区不当作选区（`searchFindsSelectionOnAnAncestor`、`searchFindsSelectionInADescendant`、`searchReadsSelectionThroughAWebKitMarkerRange`、`searchSkipsBlankSelections`、`searchWithoutAnySelectionIsNil`）。
- [x] 复制回退只在搜索落空时运行，密码字段永不触发，剪贴板被放回（`copyFallbackReadsWhenTheSearchFindsNothing`、`copyFallbackIsSkippedForASecureField`、`copyFallbackIsSkippedWhenTheSearchSucceeds`、`copyFallbackRestoresThePreviousPasteboard`、`copyFallbackWithoutANewCopyIsNil`）。
- [x] 写回先直写、后粘贴，无权限或无法前置时拒绝（`directWriteIsUsedWhenTheElementAcceptsIt`、`pasteIsUsedWhenTheDirectWriteFails`、`pasteRefusesWithoutFrontingTheApp`、`replaceRefusesWithoutAccessibilityPermission`）。
- [x] 超时只先给出提示：迟到但有效的读取仍会生效，关闭后到达的读取被丢弃（`readPastBudgetShowsUnreadableThenAcceptsTheLateAnswer`、`lateReadAfterCloseIsIgnored`）。
- [x] 连续触发只接收最新操作，待处理读取不累积（`rapidTriggersAcceptOnlyLatestRead`、`keepsOneRunningAndLatestPending`）。
- [x] 缺失、错误类型、空白选区安全失败，保留空白与 Unicode（`wrongTypesFailSafely`、`blankOrMissingIsUnreadable`、`missingFocusedElementIsUnreadable`）。

待补：

- [ ] 捕获期间切换前台应用被拒绝：代码已在主线程比对 PID，尚无自动化测试。
- [ ] AX 主路径前后剪贴板内容与 `changeCount` 不变：代码不访问剪贴板，尚无检查。
- [ ] 实机：TextEdit、Safari、Chrome 与至少一个 Electron 编辑器，逐项记录读取成功、手动输入降级、首次授权后重试和焦点切换；另验证密码框、未授权、无选区及目标应用无响应。100／150 ms 参数随实测调整。

单元测试通过不能替代跨应用实测；应用支持清单以实测为准。
