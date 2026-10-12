# 首版实现任务清单

状态：里程碑 1（T01–T07）已实现并有单元测试覆盖；里程碑 2–5（T08–T25）尚未实施。依赖、技术建议与构建命令见 `tasks/plan.md`。文件路径均为拟定，根目录为 `Owlet/`，测试位于 `OwletTests/`；不为凑文件数创建额外抽象。每个任务控制在一次集中工作内，若实际超过约 5 个业务文件或两小时，应在实施前进一步拆分。

任务按里程碑排列，同一里程碑内按依赖排序：

1. 里程碑 1：翻译与润色选中文本（T01–T07）——已实现；快捷键和 Prompt 使用固定默认值。
2. 里程碑 2：生词本与学习内容（T08–T11）——未实施。
3. 里程碑 3：更多设置（T12–T14）——未实施；设置页与服务控件已就位，见该里程碑说明。
4. 里程碑 4：历史（T15–T17）——未实施。
5. 里程碑 5：Liquid Glass 组件迁移（T18–T25）——未开始；部分原生组件已采用，见该里程碑说明。它不改行为，只把界面换成原生组件；组件对照、令牌退役表与验收清单见 [docs/liquid-glass-components.md](../docs/liquid-glass-components.md)。

# 里程碑 1：翻译与润色选中文本

## T01：手动输入翻译

- [x] 完成

**缺口：**真实服务端到端翻译与语言选择位置未记录手动验证结果。

**说明：**交付可启动的最小原生应用；用户配置服务后输入文本即可翻译。

**验收条件：**
- [x] Base URL、模型可保存，Key 仅写入 Keychain；缺少配置时提示原因并提供服务配置入口。
- [x] 输入文本得到译文并可复制；目标语言在主窗口右上角选择，底部不重复显示，默认中文且重启保留；处理方式选择随 T07 加入。
- [x] 网络、认证、空响应错误可见且可重试；新请求不会被旧响应覆盖。

**验证：**
- [x] `mise run test`。
- [ ] 固定响应检查请求构造、错误与旧响应隔离；实际服务手动翻译中英日文本，检查语言选择位置及配置入口。

**依赖：**无

**预计文件：**OwletApp.swift、TranslationView.swift、ModelClient.swift、SettingsStore.swift、ModelClientTests.swift

**规模：**M

## T02：JSON 响应契约

- [x] 完成

**说明：**落实 `spec/llm/contract.md` 的翻译响应校验，使用内置默认 Prompt；润色随 T07、学习随 T10 按消费者增加字段。Prompt 编辑见 T12。

**验收条件：**
- [x] 主响应按 JSON Schema 解码；源文拼接按 NFC＋空白折叠比较，语言按主子标签（中文加书写系统）比较，结果非空；仅接受包裹整条消息的单个代码围栏；源文作为数据独立传入。
- [x] 非 JSON 或无效结果提示格式错误，截断与拒绝各自提示；均可重试，不写回、不视为成功结果。
- [x] 支持时使用供应商结构化输出，发送的 Schema 去掉不支持的关键字、本地照常校验；不支持时仍严格校验，不回退纯文本。

**验证：**
- [x] `mise run test`：固定有效／无效 JSON 覆盖缺字段、错误类型、源文遗漏、仅空白／换行差异通过、目标语言不匹配、`en-US`／`zh-CN` 等价、单围栏通过、围栏外文字拒绝、截断、拒绝，以及片段末尾空格正确的多句响应。

**依赖：**T01

**预计文件：**ModelClient.swift、ModelResponse.swift、DefaultPrompts.swift、ModelResponseTests.swift

**规模：**S–M

## T03：快捷键录制

- [x] 完成

**缺口：**录制交互（Esc 取消、Delete 清除）与系统占用注册失败尚未记录手动验证；动作间冲突已有单元测试。

**说明：**无默认快捷键，用户在主窗口“快捷键”页录制后才可全局触发。本任务只加入翻译动作，润色、翻译并替换随 T06、T07 各自加入。

**验收条件：**
- [x] 点击录制，Esc 取消，Delete 清除；保存后全局注册并持久化，重启后生效。
- [x] 系统占用或注册失败明确提示；动作之间的冲突检查随第二个动作（T06）加入。
- [x] 未绑定时该动作不触发，快捷键页与菜单栏显示“未设置”。

**验证：**
- [x] `mise run test`：持久化与清除。
- [ ] 手测录制、重启、清除及系统占用组合。

**依赖：**T02

**预计文件：**ShortcutController.swift、ShortcutSettingsView.swift、SettingsStore.swift、ShortcutControllerTests.swift

**规模：**M

## T04：快捷键读取选区并翻译

- [x] 完成

**缺口：**真实应用中读取选区与 `toolbar-errors.feature` 各错误路径为手测项，尚未记录。

**说明：**在外部应用完成选区到浮窗译文的完整路径；快捷键来自 T03。

**验收条件：**
- [x] 已录制的翻译快捷键唤起浮窗；未设置时菜单栏提示前往快捷键页。
- [x] 唤起前捕获来源与选区，首次处理显示紧凑提示，成功后展开；已展开后重新处理或遇错保持展开，在内容区显示错误与恢复入口；Esc 关闭并取消。
- [x] 打开前权限、配置、读取或请求失败不展开完整工具栏，行内提供对应权限／服务设置或手动输入入口；手动输入进入完整窗口，不读取密码内容。

**验证：**
- [x] `mise run test`。
- [ ] 在 TextEdit 和浏览器文本手测成功及不支持的路径；记录兼容边界。
- [ ] 按 `toolbar-errors.feature` 检查打开前及展开后的权限、配置、读取、连接、认证和格式错误，以及取消。

**依赖：**T03

**预计文件：**ShortcutController.swift、SelectionBridge.swift、PanelController.swift、TranslationView.swift、SelectionBridgeTests.swift

**规模：**M

## T05：安全替换原选区

- [x] 完成

**缺口：**无。拒绝路径由 `SelectionBridgeTests` 的写回用例与 `PanelControllerTests.refusedWriteBackKeepsTheResult`、`readOnlySelectionIsReportedAsUnwritable` 覆盖。

**说明：**让当前结果可由用户主动写回原选区。

**验收条件：**
- [x] 复制始终可用；替换只在用户主动触发后执行。
- [x] 不再比对来源元素、文档、原文与选区（应用在面板取得焦点后会重建辅助功能树，比对必然失败）；改为粘贴后用元素文本确认是否落盘，未落盘就不关闭面板，在内容区提示并提供复制入口。
- [x] 一次替换成功后不重复写回；新操作不复用旧操作的来源。

**验证：**
- [x] `mise run test`：只读选区不发送按键、粘贴前后文本对比、不可编辑 role、无权限与无法前置、重复触发只消费一次来源（`readOnlySelectionIsNeverTypedInto`、`pasteReplacesTheSelectionAndRestoresTheClipboard`、`pasteThatTheAppIgnoresIsRefused`、`onlyEditableTextRolesTakeAPaste`、`pasteRefusesWithoutFrontingTheApp`、`replaceRefusesWithoutAccessibilityPermission`）。
- [x] 手测有效替换（2026-09-27：Safari 输入框内替换成功）。
- [ ] 手测切换应用与编辑原文后的拒绝路径。

**依赖：**T04

**预计文件：**SelectionBridge.swift、PanelController.swift、TranslationView.swift、SelectionBridgeTests.swift

**规模：**M

## T06：翻译并直接替换

- [x] 完成

**缺口：**无。原先 disabled 的 `successWritesOnce`、`newRequestSupersedesOld`、`plainTranslateDoesNotWrite` 已重新启用并通过——挂起的根因是面板测试抢真实窗口的 key，而 `PanelController` 又从 `UserDefaults.standard` 读目标语言，两处都已修好；`refusedWriteKeepsResult` 由同义的 `refusedWriteBackKeepsTheResult` 取代后删除。

**说明：**复用翻译与安全写回，提供无需再次点击替换的独立快捷操作。

**验收条件：**
- [x] 快捷键页加入该动作并检查与已有动作冲突；已录制快捷键按当前目标语言翻译有效选区；完成后直接替换一次，无二次确认。验证见 `pasteReplacesTheSelectionAndRestoresTheClipboard`。
- [x] 无有效选区时仅显示紧凑提示及手动输入入口，不自动写回；失败、取消、过期响应及写回被拒均不写回，已有译文可复制。
- [x] 错误沿用 T04 规则：未展开时紧凑提示，已展开时在内容区呈现；恢复操作不绕过写回校验。

**验证：**
- [x] `mise run test`：成功仅写回一次、取消后迟到响应、新请求覆盖、无选区不写回、只读选区一个键都不发、无权限与无法前置应用时拒绝。
- [ ] 手测完整快捷流程。

**依赖：**T05

**预计文件：**ShortcutController.swift、PanelController.swift、SelectionBridge.swift、SelectionBridgeTests.swift

**规模：**M

## T07：润色选中文本

- [x] 完成

**缺口：**中英日手测与右上角控件顺序、润色切换后的语言保留未记录；操作类型与润色契约已有单元测试。

**说明：**增加独立润色快捷入口，复用文本处理和安全写回流程。

**验收条件：**
- [x] 快捷键页加入润色动作，冲突检查覆盖三个动作；保持原语言及原意，只给一个润色结果；响应按润色契约校验。
- [x] 原文与润色结果各显示一次，均为普通文本，无差异背景、删除线或对照开关；结果可复制和安全替换。
- [x] 主窗口右上角依次为目标语言和处理方式；润色隐藏目标语言，切回翻译恢复之前选择；错误沿用打开前／展开后规则。

**验证：**
- [x] `mise run test`：操作类型、润色契约与提示约束。
- [ ] 中英日各手测一例，检查普通原文与单一结果、复制及写回；验证右上角控件顺序与语言保留。

**依赖：**T06

**预计文件：**Operation.swift、ModelClient.swift、ModelResponse.swift、TranslationView.swift、OperationTests.swift

**规模：**M

## 检查点 A：里程碑 1

- [ ] `mise run check` 通过。
- [ ] 在支持的应用完成选区 → 翻译／润色 → 复制／替换，以及翻译并直接替换；权限拒绝和失效选区不误写。
- [ ] 同一错误在打开前使用紧凑提示，展开后保留界面；恢复入口有效，Esc 关闭并取消。
- [ ] 记录演示步骤、兼容边界与未解决问题，供用户审阅。

# 里程碑 2：生词本与学习内容

## T08：手动收藏与生词本列表

- [x] 完成

**缺口：**无。搜索／筛选／编辑／删除／导出由 T09 补齐。

**说明：**无论学习是否展开，都能从当前结果主动收藏内容。从历史收藏见 T17。

**验收条件：**
- [ ] 当前原文和结果中的词汇／短语／整句均可选择收藏，点击即保存，无强制表单。
- [ ] 保存表达、语言、独立原句快照和润色对照；缺少释义时由明确收藏操作补充中文释义。
- [ ] 生词本可列出与查看，重启保留；补充释义失败不撤销已收藏内容，提供重试。

**验证：**
- [ ] `mise run test`：持久化、释义补充失败与重试。
- [ ] 手测从翻译和润色结果分别收藏。

**依赖：**T07

**预计文件：**VocabularyEntry.swift、VocabularyStore.swift、VocabularyView.swift、CollectionAction.swift、VocabularyStoreTests.swift

**规模：**M

## T09：收藏管理与导出

- [x] 完成

**缺口：**无。重复表达追加语境属 T11。

**说明：**完成生词本中的查找、修订和数据导出。

**验收条件：**
- [ ] 支持搜索、语言筛选、详情编辑和删除；词汇、短语、整句统一处理。
- [ ] UTF-8 JSON 导出包含表达、语言、全部语境和润色对照。
- [ ] 取消或写入失败不改动本地内容。

**验证：**
- [ ] `mise run test`：筛选与编辑；解析导出 JSON，检查日文、中文、换行和引号完整性。

**依赖：**T08

**预计文件：**VocabularyView.swift、VocabularyStore.swift、VocabularyExport.swift、VocabularyStoreTests.swift、VocabularyExportTests.swift

**规模：**M

## T10：学习内容及勾选收藏

- [x] 完成

**缺口：**无。学习表达区块在浮层与主窗口都可用；自动请求开关属 T13。

**说明：**用户点击“生成”后单独请求学习表达，并接入收藏流程。自动请求开关见 T13。

**验收条件：**
- [ ] 默认不请求；点击生成后展示中文解释的词汇、搭配或句式，允许无推荐且不强凑数量；收起后再展开复用本次结果。
- [ ] 推荐可勾选收藏；生成失败不影响主要结果，重试不重复收藏，过期响应不串到新操作。
- [ ] 学习生成不阻塞写回，不自动收藏。

**验证：**
- [ ] `mise run test`：未点击不请求、格式异常、响应交错与复用。
- [ ] 手测翻译与润色的勾选入库。

**依赖：**T08

**预计文件：**LearningContent.swift、LearningView.swift、ModelClient.swift、LearningContentTests.swift

**规模：**M

## T11：重复表达追加语境

- [x] 完成

**缺口：**无。同一语言同一表达再次收藏时追加语境，同一语境不重复追加，不同语言始终是不同条目。

**说明：**同语言重复表达复用已有条目并保留新上下文。

**验收条件：**
- [ ] 再次收藏同语言、完全匹配的表达时追加语境，不创建重复条目；仅去首尾空白，不做词干或大小写推断。
- [ ] 不同语言同形表达分别保存；同一语境重复提交不重复追加。
- [ ] 详情和导出包含追加后的语境，原有释义及润色对照不被覆盖。

**验证：**
- [ ] `mise run test`：同形异语言、新语境追加、重复提交和导出完整性。
- [ ] 手测从当前结果与学习推荐追加同一表达。

**依赖：**T09、T10

**预计文件：**VocabularyStore.swift、CollectionAction.swift、VocabularyView.swift、VocabularyStoreTests.swift

**规模：**M

## 检查点 B：里程碑 2

- [ ] `mise run check` 通过。
- [ ] 当前结果与学习推荐可收藏；生词本可管理、导出，重复表达追加语境。
- [ ] 记录演示步骤与未解决问题，供用户审阅。

# 里程碑 3：更多设置

说明：设置已作为主窗口侧边栏页实现（`OwletApp.swift` 的 `MainView` 与 `ServiceSettingsView.swift`），服务商、Base URL、API Key、模型名称、思考强度、浮窗位置控件及 DeepSeek 模型列表加载均已实现；T12–T14、T26 已实现。

## T12：自定义 System Prompt

- [x] 完成

**缺口：**无。

**说明：**翻译、润色 Prompt 分别可查看、编辑与恢复默认。

**验收条件：**
- [ ] 显示默认 Prompt，可编辑保存、查看默认及恢复；拒绝空白，重启保留，保存只影响后续请求。
- [ ] 用户 Prompt 不解除 JSON 契约；格式错误提示中提供对应操作的提示词设置入口。
- [ ] 可展开查看 JSON 返回示例。

**验证：**
- [ ] `mise run test`：自定义 Prompt 仍按契约校验。
- [ ] 手测自定义、重启保留、恢复默认、空白拒绝及格式错误入口。

**依赖：**T07

**预计文件：**SettingsStore.swift、PromptSettingsView.swift、ModelClient.swift、SettingsStoreTests.swift

**规模：**M

## T13：学习表达自动请求开关

- [x] 完成

**缺口：**无。开关在设置页「学习」分组，默认关闭，两个操作各自控制。

**说明：**翻译、润色各自的“自动请求学习表达”开关。

**验收条件：**
- [ ] 两个开关独立且默认关闭，重启保留。
- [ ] 开启后每次处理成功自动请求学习表达；关闭时不请求。
- [ ] 翻译并替换沿用翻译开关，学习请求不阻塞写回。

**验证：**
- [ ] `mise run test`：开关组合下的请求次数。

**依赖：**T10

**预计文件：**SettingsStore.swift、SettingsView.swift、LearningView.swift、LearningContentTests.swift

**规模：**S

## T14：翻译显示方式

- [x] 完成

**缺口：**无。

**说明：**落实 `translation.feature` 中“原文／译文分区”与“逐句对照”两种显示。

**验收条件：**
- [ ] 默认分区显示；设置中可改为逐句对照，保存后持久化，完整窗口与浮层共用。
- [ ] 逐句对照按响应配对成组，上方原文、下方译文，不按标点或显示行猜测。
- [ ] 切换不重新请求模型；复制与替换只输出译文。

**验证：**
- [ ] `mise run test`：切换不触发请求。
- [ ] 手测长文本两种方式及复制。

**依赖：**T07

**预计文件：**SettingsStore.swift、SettingsView.swift、TranslationView.swift

**规模：**S

## T26：思考强度设置

- [x] 完成

**缺口：**无。默认「自动」不发送参数，保持现有行为；DeepSeek 默认开启思考且强度最高，用户可在设置中调低或关闭。

**说明：**在设置页增加思考强度选项，请求按当前模型映射后带上 `reasoning_effort`。

**验收条件：**
- [x] 选项为自动／关闭／低／中／高／最高，默认自动；保存后持久化，主请求、学习请求与补充释义都生效。
- [x] 按模型映射：DeepSeek 的 `medium` 发 `high`，o-series 的 `关闭`／`最高` 钳到 `low`／`high`，GPT-6 Astra 的 `关闭` 发 `minimal`，非推理模型与自动不发送；JSON 返回契约与本地校验不变。

**验证：**
- [x] `mise run test`：默认自动与非法值回退、各模型映射与钳位、非推理模型不发、主／学习请求携带参数。
- [ ] 手测 DeepSeek 下关闭与自动的返回时长差异。

**依赖：**T01

**预计文件：**SettingsStore.swift、ServiceSettingsView.swift、ModelEffort.swift、ModelClient.swift、EffortTests.swift、ModelEffortTests.swift、ModelClientTests.swift

**规模：**S

## 检查点 C：里程碑 3

- [ ] `mise run check` 通过。
- [ ] Prompt、快捷键、学习开关与显示方式均可保存、重启保留并即时生效。
- [ ] 记录演示步骤与未解决问题，供用户审阅。

# 里程碑 4：历史

## T15：持久化历史及详情

- [x] 完成

**缺口：**无。搜索、筛选与删除由 T16 补齐。

**说明：**让完成的翻译和润色重启后仍可查看。

**验收条件：**
- [ ] 每次成功生成结果保存原文、结果、操作类型、语言与时间；翻译并替换计为翻译，写回失败仍保存译文，失败或取消不保存。
- [ ] 历史列表与详情重启后可读取，详情可复制。
- [ ] 历史不持有外部选区写回能力；存储失败明确提示且不丢失屏幕上的结果。

**验证：**
- [ ] `mise run test`：写入、重开、重复完成和失败路径。
- [ ] 手测从三种操作进入历史。

**依赖：**T07

**预计文件：**HistoryRecord.swift、HistoryStore.swift、HistoryView.swift、Operation.swift、HistoryStoreTests.swift

**规模：**M

## T16：历史搜索与删除

- [x] 完成

**缺口：**无。从历史收藏属 T17。

**说明：**完成历史的查找及清理。

**验收条件：**
- [ ] 支持按内容搜索和按翻译／润色筛选，可组合使用。
- [ ] 支持删除单条及确认后清空全部，重启后生效。
- [ ] 无记录或无匹配时显示空状态，不自动过期。

**验证：**
- [ ] `mise run test`：组合查询与删除。
- [ ] 手测取消清空、确认清空和空状态。

**依赖：**T15

**预计文件：**HistoryStore.swift、HistoryView.swift、HistoryStoreTests.swift

**规模：**M

## T17：从历史收藏

- [x] 完成

**缺口：**无。历史详情底部是复制与 prominent 的收藏。

**说明：**历史详情复用收藏流程，收藏与历史生命周期独立。

**验收条件：**
- [ ] 历史中的词汇／短语／整句可收藏，保存独立原句快照；同语言重复表达追加语境。
- [ ] 删除历史或清空历史不影响收藏及其语境。

**验证：**
- [ ] `mise run test`：删除、清空历史后收藏完整。
- [ ] 手测从历史收藏后清空历史。

**依赖：**T16、T11

**预计文件：**HistoryView.swift、CollectionAction.swift、VocabularyStoreTests.swift

**规模：**S

# 里程碑 5：Liquid Glass 组件迁移

不改产品行为，只把界面换成原生组件。组件对照、令牌退役表、文案规则、例外与验收清单见 [docs/liquid-glass-components.md](../docs/liquid-glass-components.md)。

说明：本里程碑尚未开始，T18–T25 均未完成。当前实现已采用部分原生组件：主窗口为 `NavigationSplitView`（`OwletApp.swift` 的 `MainView`，侧边栏用 `List(selection:)` + `Section`，对应 T20 的一部分）；文本处理工具栏使用分段 `Picker`（翻译｜润色）与目标语言弹出式菜单（对应 T21 的一部分）；浮窗、设置与快捷键按钮使用 `.glass`／`.glassProminent`（`PanelController.swift`、`ExpandedPanel.swift`、`ShortcutSettingsView.swift`、`ServiceSettingsView.swift`，对应 T18 的一部分）；设置与快捷键页使用 `.formStyle(.grouped)`；文本处理页与设置页使用 `.safeAreaBar` 页脚。仍未完成的主要子项：T18 的内容区 `.bordered`／`.borderedProminent` 划分与外观验收；T19 的独立 Settings 窗口与分栏；T20 的 `.badge` 计数，以及确认工具栏自带的侧边栏收起／展开按钮可用；`Show/Hide Sidebar (⌃⌘S)` 需要显式 `SidebarCommands()`，未添加；T21 的跨整窗工具栏与删除底部动作栏；T22 的 720pt 响应式双栏；T23 的列表、搜索与 `ContentUnavailableView`；T24 的呼吸边框与动作行；T25 的七组菜单与文案收口。T12、T14、T22、T23 的界面现以提案画面记在 `design/index.html`（画面上带“未实现”徽标，总览里各自成区），仅供实现参考，不代表已经落地。

## T18：退役自定义令牌与按钮样式

- [x] 完成

**缺口：**无。应用内没有自定义颜色令牌，按钮统一用 `.glass` / `.glassProminent`。

**说明：**删除 `RoseGlass` 与全部自绘窗口零件，改用系统语义色与系统按钮。

**验收条件：**
- [ ] 代码中不存在硬编码色值、自定义圆角、描边、渐变、阴影与自定义 `ButtonStyle`；玫瑰色只剩应用 `AccentColor` 资源一个出口。
- [ ] 内容区按钮用 `.bordered` / `.borderedProminent`；浮窗与工具栏按钮用 `.glass` / `.glassProminent`；每屏最多一个 prominent 动作。
- [ ] 浅色与深色外观都不回退为单色错位；`Increase Contrast` 下有更强描边。

**验证：**
- [ ] 浅色／深色／`Reduce Transparency`／`Increase Contrast` 四种设置下截图对比。
- [ ] 全局搜索 `Color(red:`、`cornerRadius`、`shadow(`、`ButtonStyle` 无业务命中。

**依赖：**无（可与里程碑 1–4 并行，但建议先做）

**预计文件：**PanelController.swift、TranslationView.swift、SettingsForm.swift、ServiceSettingsView.swift

**规模：**M

## T19：设置改为独立 Settings 窗口（已否决，不实现）

- [ ] 完成

**缺口：****已否决**：应用与设计都把设置作为主窗口的侧栏页面（`spec/DESIGN.md` §2.2 第 11 条记为未采纳的建议），不实现独立 Settings 窗口。

**说明：**把设置从主窗口的一个页面改成系统设置窗口。

**验收条件：**
- [ ] `⌘,` 打开独立设置窗口，分栏为通用／显示／提示词／服务；工具栏不可自定义、常驻且始终标示当前分栏；最小化与缩放置灰；再次打开回到上次分栏。
- [ ] 主窗口侧边栏与工具栏都不再出现设置入口；应用菜单保留 `Settings…`。

**验证：**
- [ ] 逐条对照 `settings.md › Desktop (macOS)`。
- [ ] 从三个快捷键入口进入设置的路径保持可用。

**依赖：**T18

**预计文件：**OwletApp.swift、ServiceSettingsView.swift、SettingsForm.swift

**规模：**M

## T20：主窗口改 NavigationSplitView

- [x] 完成

**缺口：**无。主窗口使用系统 `NavigationSplitView` 与 `List(selection:)`。

**说明：**侧边栏改为系统 source list，并可收起。

**验收条件：**
- [ ] 侧边栏用 `List(selection:)` 与 `Section`，计数用 `.badge`；选中态是系统外观。
- [ ] 工具栏的侧边栏切换、视图菜单 `Show/Hide Sidebar`（`⌃⌘S`）与窗口缩放都能收起／展开，状态持久化；收起后功能与展开时完全一致。
- [ ] 侧边栏底部不再放任何动作；`本地` 角标删除，数据位置说明移入设置。

**验证：**
- [ ] 收起／展开后逐页检查导航与选中态。
- [ ] `Full Keyboard Access` 下键盘可达侧边栏每一项。

**依赖：**T18

**预计文件：**OwletApp.swift

**规模：**M

## T21：工具栏与动作区

- [x] 完成

**缺口：**前两条验收条件**已被推翻**：应用与设计都保留底部操作栏（`spec/DESIGN.md` §2.2 #6 记为未采纳的建议），工具栏只承载目标语言与翻译／润色选择。第三条已完成：`文本处理` 菜单提供目标语言与处理方式两个子菜单、按当前操作命名的提交项（⌘↩）与复制结果（⌘⇧C），快捷键由菜单项持有，按钮保留悬停提示。

**说明：**统一工具栏跨整窗，底部动作栏删除。

**验收条件：**
- [ ] 工具栏居中为目标语言弹出式按钮（仅翻译适用）与 `翻译｜润色` 分段控件，trailing 端是唯一的 prominent 动作；窄窗口时系统自动 overflow。
- [ ] 主窗口不再有底部动作栏；窗口缩到最小高度时动作仍可见。
- [ ] 每个工具栏项都能在菜单栏找到对应命令与快捷键。

**验证：**
- [ ] 窄窗口与最小高度截图。
- [ ] 逐项核对菜单栏命令。

**依赖：**T20

**预计文件：**OwletApp.swift、TranslationView.swift

**规模：**M

## T22：文本处理页响应式

- [x] 完成

**缺口：**无。

**说明：**内容区足够宽时原文与译文并排，不足时上下堆叠。

**验收条件：**
- [ ] 阈值 720pt：不低于时两栏并排，中间一道发丝分隔；低于时上下堆叠并保留原分隔线。
- [ ] 没有结果时原文占满整宽，不留下空栏。
- [ ] 两种排列都能直接编辑原文、选中结果、复制；学习表达与状态行始终跨全宽。

**验证：**
- [ ] 从 500pt 到满宽连续拖动窗口，检查无跳变、无截断、无重排抖动。
- [ ] 两种排列下分别跑一次翻译与润色。

**依赖：**T21

**预计文件：**TranslationView.swift

**规模：**S–M

## T23：列表、搜索与空状态

- [x] 完成

**缺口：**无。生词本与历史都有列表、详情、工具栏搜索、语言／类型筛选、`ContentUnavailableView` 空状态与无匹配状态；删除是行内按钮（设计图同样画出行内删除，不是悬停才出现）。

**说明：**生词本与历史换成系统 List、工具栏搜索框与系统空状态。

**验收条件：**
- [ ] 搜索框位于工具栏 trailing 端，边打边搜，有值时可一键清除；筛选是弹出式按钮。
- [ ] 空列表、无匹配、有数据三态都使用 `ContentUnavailableView`；空状态给出下一步动作。
- [ ] 行内删除不再常驻，鼠标悬停或键盘聚焦时才出现；删除同时可从上下文菜单触发；清空历史走 destructive 且需确认。
- [ ] 列表 → 详情用导航层级，返回用系统返回按钮。

**验证：**
- [ ] 空、无匹配、单条、多条四种数据量下逐屏检查。
- [ ] 悬停、键盘聚焦与上下文菜单三种路径都能删除。

**依赖：**T20

**预计文件：**VocabularyView.swift、HistoryView.swift

**规模：**M

## T24：浮窗呼吸边框与动作行

- [x] 完成

**缺口：**动作行已实现。落地的边缘不是单色描边，而是强调色圆环加上沿边框绕行的 conic 光泽与向内的柔和辉光（`ProcessingEdge` 与 `PanelSurface.sheen`），处理中呼吸并且绕行，Reduce Motion 下静止在一个亮度。原「单色、无渐变、不新增自绘阴影」这条验收条件因此**已被推翻**，以实现的观感为准。设计图的边缘仍画成单色描边，待补光泽与辉光。

**说明：**处理中用整圈边框呼吸，动作行只放动作。

**验收条件：**
- [ ] 呼吸只作用于面板边缘，单色、无渐变、不新增自绘边框与阴影；紧凑态与展开态共用；面板尺寸与位置不变。
- [ ] `Reduce Motion` 下呼吸静止为稳定状态，不丢失标记；状态文字始终存在，动效不是唯一载体。
- [~] 紧凑条不显示终止按钮 —— **与实现不符**：紧凑条保留「停止」按钮，Esc 在处理中取消、否则关闭。
- [ ] 动作行 leading 端是 `收藏选中内容`（无结果时不显示），trailing 端是 `复制` 与唯一的 prominent 动作；动作行内不出现提示文案。
- [~] `⌘↩` / `Esc` 等快捷键不再画在按钮上 —— **已被推翻**：用户要求按钮上直接显示（`替换 ⌘↩`、`复制 ⌘⇧C`），并且这三个键现在列在快捷键页的「面板内」分组里。这条属于 `spec/DESIGN.md` 的三条提案之一，见 [未实现功能清单](../docs/unimplemented-features.md)。

**验证：**
- [ ] 处理中／失败／取消／成功／未能写回五态截图。
- [ ] 开启 `Reduce Motion` 与 `Reduce Transparency` 各跑一遍。

**依赖：**T18

**预计文件：**PanelController.swift、ExpandedPanel.swift

**规模：**M

## T25：菜单栏与文案收口

- [x] 完成

**缺口：**菜单已完成（含 `SidebarCommands`）；面板与工具栏的文案收口属 T21。

**说明：**补齐菜单栏，并按文案规则统一叫法。

**验收条件：**
- [ ] 应用、文件、编辑、显示、处理、窗口、帮助七组菜单就位；`Settings… (⌘,)`、`Show/Hide Sidebar (⌃⌘S)`、`Undo/Redo/Cut/Copy/Paste/Select All` 由系统提供。
- [ ] 菜单栏常驻入口点击展开菜单，不是 popover。
- [ ] 全部按钮改动词，宾语交给上下文；同一动作在不同屏叫法一致（`翻译`、`润色`、`复制`、`保存`、`收藏`、`导出…`）。
- [ ] 界面不再出现“快捷键未设置”之类的空心提示。

**验证：**
- [ ] 逐项对照 `the-menu-bar.md` 的菜单顺序与项目。
- [ ] 全局搜索按钮文案，确认无 `…文本`、`…译文`、`保存…` 这类重复宾语。

**依赖：**T19、T21、T24

**预计文件：**OwletApp.swift、MenuCommands.swift

**规模：**M

## T26：按源语言决定翻译目标

- [x] 完成

**缺口：**无。

**说明：**落实 BDR-0003：发请求前在本地检测源语言，按用户配置的「源语言 → 目标语言」映射决定目标，未命中用兜底目标。映射表初始为空，兜底目标沿用原来的目标语言设置。

**验收条件：**
- [x] 源语言由 `NLLanguageRecognizer` 在发请求前检测；置信度或领先幅度不足、以及过短文本走兜底。检测只用于选目标，返回契约与校验不变。
- [x] 映射表按源语言一对一并持久化；兜底目标独立设置；旧的目标语言设置直接成为兜底目标，不需要迁移写入。
- [x] 工具栏、浮动面板与文本处理菜单共用「自动／指定」控件；显式选择持久覆盖映射，切回自动恢复。
- [x] 翻译并替换复用同一解析；润色不显示该控件。
- [x] 语言选项取自系统清单（`Locale`），中文保留 `zh-Hans`／`zh-Hant`；应用不再维护自有语言列表。
- [x] 润色默认 Prompt 补混写规则，`DefaultPrompts.polish` 与 `spec/llm/default-prompts.json` 同步。

**验证：**
- [x] `mise run test`：`TargetMappingTests`、`LanguageDetectorTests`、`LanguageTagTests`，以及 `PanelControllerTests` 的映射与钉住用例。
- [x] 设计图同步：`settings-targets`、`settings-targets-rows`、`workspace-auto`、`workspace-target-pinned` 不再是提案画面。

**依赖：**T14

**预计文件：**LanguageDetector.swift、LanguageTag.swift、TargetMapping.swift、TargetLanguagePicker.swift、TargetMappingSettingsView.swift、SettingsStore.swift、TranslationView.swift、ExpandedPanel.swift、PanelController.swift、OwletApp.swift

**规模：**M

## T27：模型失败原因可见与调试页

- [x] 完成

**缺口：**无。

**说明：**契约失败拆成可行动的原因（结构／目标语言／原文拼接），错误文案统一为中文；新增隐藏「调试」页，记录最近若干次请求体、模型原始返回与失败原因，可一键复制。

**验收条件：**
- [x] `ModelError` 区分 `format`／`sourceMismatch`／`targetMismatch`，文案为中文；主窗口与浮窗共用同一套文案。
- [x] 面板的恢复入口按「是否契约失败」路由到提示词设置。
- [x] 设置页「调试」开关控制侧边栏「调试」页；关闭即隐藏并清空，数据只在内存。
- [x] 调试页显示请求体、模型原始返回、失败原因，以及原文拼接不一致时的首个差异；单条与全部可复制，不含 API Key。
- [x] 未开启时不记录；关闭开关时同时清掉已捕获的内容，内存里不留原文。

**验证：**
- [x] `mise run test`：`DebugLogTests`、`ModelResponseTests` 的拆分用例、`PromptContractTests`、`PromptRouteTests`。
- [x] 真实 DeepSeek 调用核对：同一请求返回合规 JSON，说明问题在本地校验路径，调试页用于取证。

**依赖：**无

**规模：**M

## T28：语言子集

- [x] 完成

**说明：**系统语言清单有六百多项，不便在每个选择目标语言的地方每次翻。新增「语言」分组维护一个子集，其余所有选语言的地方只用这个子集。

**验收条件：**
- [x] 设置页「语言」分组：已选语言逐行列出、可删除（至少保留一种），`添加语言` 处才展示完整系统清单。
- [x] 默认子集为 `zh-Hans`、`en`、`ja`，持久化并保持顺序。
- [x] 目标语言控件、兜底目标、映射表的源／目标列都只提供子集内的语言。
- [x] 移除一种语言时，引用它的映射行一并删除；兜底目标改到子集内第一个；已钉住的目标回到自动。

**验证：**
- [x] `mise run test`：`TargetMappingTests` 的子集、顺序、移除清理用例。
- [x] 设计图同步：新增 `settings-languages`，映射表样例改用子集内的语言。

**依赖：**T26

**规模：**S

## T29：设置改为独立窗口并按标签页分组

- [x] 完成

**说明：**按 Apple HIG 的 Settings 与 SwiftUI 的 `Settings` scene 重做设置：独立设置窗口（App 菜单与 ⌘, 打开，主窗口侧栏不再有设置入口），内部四个标签页 + 开关打开后的调试页，每页再用分组分节；任务专属的「翻译显示方式」移到文本处理页。本任务推翻 T19 的「保持侧栏页面」决定。

**验收条件：**
- [x] `Settings` scene 提供 App 菜单项与 ⌘,；主窗口侧栏去掉设置与调试入口。
- [x] 标签页：通用、语言、模型、Prompt；开关打开后多一个调试页。每页内用 `Section` 分组。
- [x] 标签页选择持久化，重新打开回到上次的页。
- [x] 取消整页保存按钮，改为即时生效：API Key 与 Prompt 在编辑框失焦时提交。
- [x] 翻译显示方式一度移到文本处理页工具栏，随后按用户要求移回设置的「通用」页；切换仍不重新请求。
- [x] 面板的服务错误与契约错误分别打开模型页与 Prompt 页。

**验证：**
- [x] `mise run test`：`ServiceModelOptionsTests`、`PromptSettingsTests` 随结构调整。
- [x] 设计图与逐屏组件对照同步。

**依赖：**T26、T28

**规模：**M

## T30：拆掉自建的两组应用菜单

- [x] 完成

**说明：**App 菜单里的 `处理` 与 `文本处理` 两组菜单与界面重复（目标语言、处理方式、提交、复制都在工具栏与底部操作栏上），且 HIG 建议不要在自有窗口里另开一套平行入口。`⌘↩` 与 `⌘⇧C` 原本由菜单项持有，现移到对应的按钮上。

**验收条件：**
- [x] App 菜单不再有 `处理`、`文本处理`；菜单栏图标菜单照旧。
- [x] `⌘↩`（提交）与 `⌘⇧C`（复制）移到文本处理页底部的按钮上，行为与之前一致。
- [x] `TextProcessingCommands` 及其测试随之删除。

**验证：**
- [x] `mise run test`（删掉一个只剩菜单验证的测试文件）。

**依赖：**T29

**规模：**S

## T31：调试页改成列表与展开

- [x] 完成

**说明：**调试页原来把「可能的失败原因」清单和每次交换的说明都画在页面上，信息量比数据本身还大。改成只显示捕获到的内容：`List(.inset)` 一行一条，行内是操作名、原文摘要（超长截断）与时间，行尾的 disclosure 展开三段原始内容。复制与清空移到窗口工具栏。

**验收条件：**
- [x] 页面上不再有解释性文案。
- [x] 每条一行：`翻译／润色` + 摘要（`.lineLimit(1)`、`.truncationMode(.tail)`）+ 时间 + 行尾展开。
- [x] 展开后显示失败原因、原文差异（若有）与提交原文／模型原始返回／请求体，可复制这一条。
- [x] 不嵌套同方向的滚动视图（List 是唯一的纵向滚动容器）。

**验证：**
- [x] `mise run test`：`DebugLogTests` 补摘要与全部报告的用例。
- [x] 设计图：新增 `settings-debug-open`，总数 67 个状态。

**依赖：**T27

**规模：**S

## T32：翻译与润色页搬进工具栏，快捷键搬进设置

- [x] 完成

**说明：**按 HIG 的 Toolbars 把这一页的动作从自建的底部操作栏搬进窗口工具栏；快捷键页从侧栏搬进设置窗口；侧栏去掉「随手处理」组名并按分组重排。

**验收条件：**
- [x] 处理方式最后按 HIG Tab views 做成内容区顶边的 `TabView`（翻译／润色两个 pane，四周留边距），窗口工具栏不再放这一页的控件；目标语言在译文一侧的分组标题上，两个动作是右下角浮起的独立图标按钮。
- [x] 两个动作先搬到工具栏，再按反馈改成内容右下角浮起的两颗独立玻璃图标按钮（`.overlay(alignment: .bottomTrailing)` + `.labelStyle(.iconOnly)` + `.help()`，滚动内容留出 40pt 底部内边距）；macOS 没有底部工具栏（`.bottomBar` 仅 iOS/Catalyst）。
- [x] 页面改名为「翻译与润色」（侧栏、窗口标题）。
- [x] 两侧始终存在（还没有结果时也在），各是一个 `GroupBox`（背景区隔，没有分割线）：宽窗口左右平分宽度，窄窗口上下平分高度，各带最小高度并各自滚动；原文输入撑满所在分组并留内边距。分组不再写标题、标题位放配置它们的控件：原文一侧是源语言选择（默认自动跟随检测，显式选择只用于查映射），译文一侧是「译文／学习」分段控件（HIG：切换同一窗口内的视图），目标语言移进译文组内。
- [x] 学习表达跟在译文／润色下面（属于结果，跟在整页下面不对）。
- [x] 侧栏：第一项无分组标题，保留「我的积累」，去掉快捷键项。
- [x] 快捷键成为设置的第五个标签页（权限、录制、清除、冲突提示照旧）。
- [x] 工具栏项同时是菜单命令（`复制结果` ⌘⇧C 进「编辑」，`翻译文本`／`润色文本` ⌘↩ 进「文件」），快捷键由菜单项持有。

**验证：**
- [x] `mise run check`。
- [x] 设计图：90 张里 33 张受影响（侧栏、工具栏、设置标签页），快捷键三个画面改为设置页。

**依赖：**T29、T30

**规模：**M

## 检查点 M5：组件对照验收

- [ ] [docs/liquid-glass-components.md](../docs/liquid-glass-components.md) 第 8 节的十条验收清单逐条通过。
- [ ] 风险最高的三处例外（内联提示行、快捷键录制、逐句对照）各自有实现说明与回退路径。

## 检查点 D：首版完整验收

- [ ] `mise run check` 通过。
- [ ] 逐项对照产品定义；三个快捷入口、设置、收藏、历史全程可用，不包含复习或同步。
- [ ] 记录演示步骤、兼容边界与未解决问题，供用户审阅。

## 开始实施前

- [ ] 用户审阅并认可计划及技术起点。
- [x] 工程初始化已核实 Xcode、macOS 26 SDK、Deployment Target 26.0 与 `mise run check`。

## T33：按确认设计落地原生工作台与管理分栏

**状态：**已实现；取代 T32 中内容区 tab、结果内学习及管理页动作的旧布局约定。

**验收：**
- [x] 翻译／润色使用原生工具栏、`GroupBox`，语言选择与标题同排靠右，SF Symbols 图标提供帮助说明。
- [x] 学习独立位于下方，原生 `DisclosureGroup` 展开即请求，复用已生成内容；原生复选框勾选后“加入生词本”。
- [x] 生词本／历史使用原生分栏，列表与详情分别滚动；搜索／筛选与右侧动作分组。
- [x] 移除管理页导出、复制、编辑按钮；历史学习入口展开推荐，不直接收藏整条记录。
- [x] 不手绘颜色、边框、圆角、按钮或折叠控件。

**验证：**`mise run format`、`mise run check`；启动应用验证工具栏、分栏滚动与展开学习。HTML 原型仅作布局参考，不重新生成已退役的 `design/` 截图。

**验证记录：**格式与全量检查通过；已启动原生应用并检查工作台及历史页的系统工具栏、搜索框与分栏结构。学习请求沿用模拟传输测试，未在人工检查中调用真实模型；窄窗展开学习的边界由外层原生 ScrollView 保证可达，尚未完成实际窗口缩放检查。

T33 补充：用户允许正文容器使用 Liquid Glass；工作台三处内容容器采用系统 glassEffect，正文仍使用系统文字样式。

T33 补充：历史页去掉重复窗口标题；数量改为列表首行的系统 secondary 标签，禁用选择并随列表滚动。

T33 补充：生词本采用相同处理，去掉重复标题，表达数量作为随列表滚动的 secondary 首行标签。

T33 补充：数量居中且不占列表顶部额外安全留白；两页补齐可操作的空库/无匹配状态；上一条、下一条按筛选结果切换并在边界禁用。验证含 AdjacentSelectionTests。

## T34：窗口点击空白结束编辑（已完成）

主窗口与设置使用同一 AppKit 事件监听结束文本编辑，保留原点击、不干扰选字/滚动和浮动面板。验证：EndEditingOnBackgroundClickTests 与全量检查。

T34 验证：`mise run format`、`mise run check` 通过；原生窗口实测点击原文标题后，焦点从 TextEditor 回到窗口。搜索与设置复用同一处理，未修改用户设置进行人工测试。

## T35：还原页面布局与管理页多选（已完成）

验收：工作台无重复标题，模式切换标题/编辑器不跳动、学习常驻；管理详情还原独立元信息与正文层次；原生多选、删除确认数量、导航独立分组。验证：布局阈值测试、批量删除隔离/级联测试、format/check、原生应用检查。

T35 验证：format/check 通过；原生截图确认标题移除、学习常驻，翻译/润色切换前后标题与容器位置一致。批量删除以内存数据库验证，只删除所选且语境正确级联，未操作用户真实记录。

## T36：系统配色与导航细节（已实现）

移除粉色覆盖、侧栏系统默认样式、学习灯泡图标、筛选一级菜单。验证 format/check 和原生窗口。

T36 验证：format/check 与 dev 构建重启通过；最终人工界面检查因 Mac 锁屏未完成。

## T37：工具栏搜索焦点（已实现）

两页使用原生 NSSearchField，单独工具栏项取消额外玻璃背景，焦点环包围完整搜索控件。验证 format/check 及原生窗口。

T37：全量检查和开发构建通过；原生窗口确认使用系统 search text field，已移除旧的局部焦点环与外层胶囊叠加结构。

## T38：Notes 式工具栏（已实现）

管理页原生工具栏按筛选、上下条、内容动作分组，右端为系统搜索项；移除搜索显隐按钮及 AppKit 桥接。验证全量检查和原生窗口。

T38 验证：format/check 和 dev 通过；实际窗口已确认独立玻璃组及最右侧系统搜索框。

## T39：贯穿式窗口工具栏（已实现）

系统统一工具栏：左侧筛选、中间上下条、右侧内容动作和搜索，保留原生分栏。原生窗口确认分隔线止于工具栏下方，列表首行、数量及详情完整显示；验证构建和全量检查。

## T40：工作台分栏统一（已实现）

原文与结果使用与管理页一致的原生可调整分栏，保留独立滚动、语言标题同排与底部学习。验收：宽屏拖动分栏、窄屏可访问、模式切换不抖动；format/check 和原生窗口验证。

## T41：按页面层级拆分过长的源码文件（已实现）

验收：翻译、生词本、学习和快捷浮窗归入各自目录；控制逻辑、窗口实现、视图和独立模型各有明确文件；接口与行为不变；format/check 通过。

T41：将浮窗源码和对应测试置于 `App/Panel/`，提取文字处理模型、生词本详情组件、学习反馈及共用显示辅助；选区读取与写回分文件，类型与方法名对应实际职责。`mise run format` 与 `mise run check` 通过。

## T42：按 Figma 重构 panel（实现已落地，待视觉复核）

验收：独立原文条与状态条、上下原文／结果及左右结果／学习、逐条收藏、关闭取消、原生玻璃；app 主界面不改。验证：format/check、原生浮窗状态检查。

T42：已核对指定画板实例与 master；组合动作采用原生 Segmented Control，独立动作采用 glass／borderless Button。mise run format、mise run check 与 mise run dev 均通过；初期 computer use 受锁屏阻断；后续已通过系统窗口截图导出各态，hover、按下与完整视觉验收仍未完成。

T42 二次视觉核对：按指定实例读出正文 17/22、图标 13 Medium 与 36pt 按钮，修正直角、独立页脚挤压与分段标签丢图标。已用隔离选区／权限和环境变量 DeepSeek Key 验证真实翻译；真实学习响应未过结构校验，按错误态处理。原生玻璃已在同背景预览中核对，但默认系统圆角与 Figma 34pt 仍有差异，尚未作为完全视觉对齐验收。

## T43：浮窗玻璃效果设置（已实现）

验收：通用设置提供更透明／更高对比度，默认后者；所有浮窗玻璃表面即时切换并持久化，不改变主窗口外观。验证：隔离设置测试、format/check。

T43：采用原生 clear／regular 玻璃，设置与全部 panel 表面及玻璃按钮共用持久化选择；隔离存储测试、mise run format、mise run check、mise run dev 通过。

## T44：panel 展开动效与动作布局（已实现）

验收：请求完成以原生 spring 连续展开，减少动态效果时禁用；学习收藏图标垂直居中，结果动作离底边和右边24pt。验证：format/check、五态原生截图。

T44：窗口与内容使用同一原生 spring；初次展示及减少动态效果时直接定位，学习收藏图标居中、底部动作内缩24pt。format/check 通过。

## T45：学习展开与即时收藏切换（已实现）

验收：结果切换学习采用原生 spring，尊重减少动态效果；词条整行可切换，选中立即入库、取消立即删除，无确认；已有收藏保持选中，失败保留状态。验证：隔离存储回归、format/check、原生截图。

T45：学习布局采用原生 spring；词条整行通过持久化词库判断选中，点击立即收藏／删除，不弹确认；存储失败保留原状态。新增无模型调用的反复切换、去重、其他词条保留回归，format/check 通过。

T45 排版修正：学习译文使用原生两端对齐文本，分隔线上下内缩24pt；窗口截图核对完整文本与末行对齐。底部原生 glass 按钮的活跃材质与 hover 视觉复核仍待完成。

## T46：沉淀 panel 调试与测试流程（已完成）

记录 Figma 组件核对、隔离预览、七态系统截图、真实模型联调、失败尝试与未验收项；用户确认的设计倾向归入 spec/DESIGN.md；README 与组件表已链接。验证：文档链接及 git diff --check。见 `docs/panel-debugging-and-testing.md`。

## T47：阅读查词卡第一步（T48–T51 已实现，待最终验收）

依据：[查词规格](../spec/vocabulary/features/word-lookup.feature)、[BDR-0008](../spec/vocabulary/decisions/BDR-0008-reading-word-lookup.md)、[模型契约](../spec/llm/contract.md#阅读查词)。讨论与备选保留在 [意图记录](../docs/intent/word-lookup.md)。Suikou 审阅结论已转为项目文档，下面 T48–T51 为执行顺序；文档完成不等于功能完成。

**总验收：**

- 只读正文单击单词可查；选区只显示原生工具栏，明确「查询」或「查询所选」才打开卡片。中日文系统分词、手选优先；双击、拖拽、复制不误发请求。
- 学习行保留点击收藏／取消收藏，选中与查询不改变收藏；可编辑原文与字段继续编辑。五类阅读区域均可访问同一卡片。
- 语境覆盖完整选区，仅解释文中义；缺原句有说明。释义语言遵循 BDR-0005，读音体系遵循 BDR-0006；实际词形为标题，已知且不同的原形次级显示。
- 精确复用与跨句旧解释分开；旧解释标来源，用户明确重查。仅有限内存缓存，失败明确重试，同条件请求合并，迟到响应不覆盖或重开卡片，配置改变不误命中。
- 系统 TTS 手动朗读词形，切换／关闭停止，无可用语音有禁用说明。Esc 先关卡片并回正文，工具栏与卡片不误关浮窗；键盘与 VoiceOver 可查询和获知状态。
- 独立 lookup 契约在本地校验，失败不冒充成功；不入库、不改已有释义、不写回正文。不加输入框、全局查词快捷键、查询历史或外部音频。

**验证：**实现时用注入模型／语音与隔离存储覆盖契约、请求复用、竞态、失败恢复及不写回；真实原生窗口验证命中、手势、焦点、辅助功能与语音可用性。Swift 改动先 format 再 check。当前仅完成文档同步，尚无查词原生验收证据。

## T48：浮窗选区查词的首个完整路径（已实现）

范围：先在浮窗只读结果接入选区工具栏／右键、局部语境快照、独立 lookup 请求及原生卡片；随首个消费者加入所需的内存复用、原形／读音、手动系统 TTS、错误恢复与关闭保护。复用现有客户端及诊断，不预建持久表、通用文本框架或未使用接口。

验收：实现前先验证原生选区承载、popover 焦点、Esc 与学习行拖拽可行性，记录输入／语境上限及超限提示，不能静默截断。首条路径完整满足 T47 的语言、复用、失败、发音、键盘／VoiceOver 与不写回边界；原文仍可编辑。

验证：注入响应覆盖有效／非法返回、相同请求合并、跨句来源与重查、失败明确重试、关闭／切换后迟到响应；隔离存储证明查询不写库，原生验证工具栏、复制、Esc 与语音缺失。完成后 format/check，记录可复现证据。

T48 结果（2026-10-11）：

- 实现：`Owlet/Lookup/`（快照与上限、`$defs.lookup` 校验、有界内存复用、系统 TTS、popover 与卡片、只读 `NSTextView`），`ModelClient.lookup` 复用传输、供应商格式与调试页；浮窗结果改用 `LookupText`（`PanelJustifiedText` 仍供主窗口与历史使用，T50 再替换）；Esc 经 `PanelController.run(.cancel)` 先关弹出层。
- 上限：查询 300 字、语境 1200 字（见契约与 feature 新场景）。
- 自动验证：`mise run format`、`mise run check` 退出码 0，296 项测试通过；`OwletTests/Lookup/LookupTests.swift` 覆盖快照／上限、契约（结构、文本、释义语言、已知语言、整句空值、调试捕获不含 Key）、同条件合并与复用、跨句来源与重查、重查失败保留旧解释、失败不自动重发、六类不兼容差异、无语境精确复用、设置变化、未配置、容量、迟到响应不覆盖／不重开、工具栏只查当前选区、切换／关闭停止发音、Esc 分层且不写回／不入库／不改原文。
- 原生验证：`python3 scripts/panel-preview.py --panel`（真实 `PanelController`／`FloatingPanel`，非激活 accessory 应用，注入模型）以 CGEvent 合成鼠标键盘、`screencapture` 与 AX 树核对。通过：双击选词出现工具栏且不请求；工具栏不夺焦点、Shift+→ 扩选连续；工具栏／右键「查询所选」／Return 打开卡片，查询范围等于手选；加载→结果；⌘C 复制选区；Esc 先关卡片并把焦点与选区还给正文，再按 Esc 关浮窗；点击卡片不关浮窗、点击外部关浮窗；跨句旧解释标来源→重查（加载中保留旧解释）→当前句；契约失败→关闭再开不重发→重试成功；加载中关闭后不弹回；A→B 快速切换只留 B；`--no-voice` 时发音禁用并显示「暂无系统语音」；AX 暴露选中文本、自定义动作「查询所选」、加载 BusyIndicator、失败文本与重试／重查按钮，经 AX 执行该动作可打开卡片；学习双栏两端对齐保持。修正：正文改 `NSColor.textColor`（`labelColor` 在玻璃上偏灰），⌘C 由文本视图自行处理（非激活应用不经编辑菜单）。
- 学习行可行性（为 T51）：把原生文本放进现有整行 `Button` 时，单击和拖拽都会切换收藏、文本无法选中。T51 须由文本自身区分单击（转交收藏）与拖拽，不能直接嵌入现有按钮。
- 未验证：真实系统语音的实际发声（无法收音，只确认按钮可用与停止调用）；真实 VoiceOver 朗读与公告（仅 AX API 模拟）；深色、提高对比度下的卡片；真实 Owlet 快捷键路径与真实模型。

## T49：只读正文单击查词与悬停提示（已实现）

范围：在首个结果区域增加真实文字命中、系统分词、手选优先及 DESIGN 的封闭悬停例外，不改变布局与选区。

验收：中英文及日文可查；空白／标点不查询邻词；双击选词、拖拽与复制不误触单击请求；已选文本不叠悬停。只在确认原生手势可共存后扩展，不以最近字符索引冒充命中。

验证：原生窗口检查词边界、行末、换行、中日文、单击／双击／拖拽；浅深色与提高对比度核对悬停、选区及 I-beam，补必要命中／请求回归，format/check。

T49 结果（2026-10-11，新 main 样式）：

- 实现：`LookupTextView` 单击在系统双击间隔（`NSEvent.doubleClickInterval`）内无第二次点击、且未产生选区时查询所在词；命中先要求点落在字形矩形内，再用 `NLTokenizer(.word)` 取词，空白、标点、行末与行间不命中。悬停以 `selectedTextBackgroundColor` 30% 临时属性标出命中词，与选区相交时不显示；鼠标移动时显式设 I-beam。
- 自动验证：`LookupWordHitTests` 覆盖英文词与空格／引号／句号、日文 `翻訳`／`文学` 与括号／句号、中文 `典故` 与逗号；format/check 退出码 0。
- 原生验证（`--panel`，合成鼠标键盘，每步先确认浮窗在场）：单击 0.25 秒时未出卡、间隔后出卡且标题为所点词；双击只选词并出工具栏、不出卡；拖拽只选区并出工具栏，⌘C 复制所选；词间空隙与行末单击不查询；日文命中 `古い`／`文学`／`翻訳`／`故事`／`吟味`，「」与、不命中；中文命中 `推敲`／`翻译`／`境界` 等系统分词；悬停只标命中词、不叠选区、I-beam，浅色／深色／高对比浅／深色截图均可见且与选区可区分（外观为进程级设置，未改系统设置）。
- 未验证：系统「提高对比度」设置本身对玻璃的影响；真实 Owlet 路径。

## T50：其余只读阅读区域复用查词（已实现）

范围：文本处理页只读结果（含逐句对照）、生词本只读详情与语境、历史详情；沿用同一卡片与来源快照，不预定统一替换文本控件。

验收：各区域均可单击及选区查询，保留复制与既有动作；跨区域精确复用，释义语言继承来源，可编辑字段仍可编辑，不覆盖保存内容。

验证：逐区域原生操作与语言／上下文快照回归，确认页面切换停止发音且旧响应不弹回；隔离数据验证不写回，format/check。

T50 结果（2026-10-11）：

- 实现：presenter 经 `EnvironmentValues.lookups` 注入，浮窗与主窗口各一个，共用应用级 `LookupStore`（跨区域精确复用）。文本处理页结果与逐句对照、生词本表达／语境／润色前后、历史原文与结果改用 `LookupText`；删除 `PanelJustifiedText`。文本视图离开窗口（切页、关窗）即关闭其工具栏或卡片，Esc 经 `cancelOperation` 先关卡片。来源：结果按 BDR-0005；逐句对照原文用原文语言、释义语言同结果；历史翻译记录原文语言未知（未存）；生词本释义语言暂为简体中文（ponytail，待 BDR-0005 按条目保存）。
- 自动验证：format/check 退出码 0，306 项通过；新增历史／生词本来源、离窗关卡、两区域共用 store 只请求一次且不改已存条目。
- 原生验证（`python3 scripts/panel-preview.py --main`，夹具模型与内存存储，合成鼠标键盘并先确认窗口在场）：文本处理页结果单击出卡、Esc 关卡、原文点击后输入与删除正常且不出卡；逐句对照原文（中文）与译文均可查；生词本表达出卡，语境查询加载中切到历史页后卡片关闭且不弹回；历史结果出卡，原文语言未知时发音禁用并显示「暂无系统语音」，双击出工具栏、⌘C 复制所选。
- 未验证：真实 Owlet 数据与真实模型；生词本编辑字段（当前详情页无编辑控件）。

## T51：学习行选区查词与完整回归（已实现）

范围：浮窗与主窗口学习表达式的选区查询，保留整行收藏切换；完成 T47 全部区域的交互及辅助功能验收。

验收：点击仍收藏／取消，拖拽、工具栏与右键查词不改变收藏；现有收藏失败处理保留。键盘与 VoiceOver 可发现查询、重试、发音与关闭动作，并获知来源及加载／失败状态。

验证：隔离词库回归收藏反复切换与查询互不干扰；真实原生窗口完成五区域、焦点／Esc、复制、语音及辅助功能检查，format/check。同步实现状态与证据后才关闭 T47；第二步另立任务。

T51 结果（2026-10-11）：

- 实现：学习行拆成书签按钮（`.plain`，辅助功能值为已收藏／未收藏）、表达 `LookupText` 与释义；行用 `onTapGesture` 收藏并保留悬停背景。表达文字的单击在系统双击间隔后才切换收藏，双击与拖拽只选中；选区查询以该条 `context` 为语境（`LookupTextView.sentence`）。释义语言：翻译取本次目标，润色按映射。浮窗、文本处理页、历史详情的学习行都继承所在窗口的 presenter。
- 自动验证：format/check 退出码 0，307 项通过；新增学习表达在原句内定位的回归，原有收藏切换／去重／失败回归仍通过。
- 原生验证（默认预览窗口 ⌘5，夹具学习与内存词库）：点表达文字 0.15 秒时未切换、间隔后切换一次；点释义、行内空白、书签各即时切换；拖拽选中出工具栏、不改收藏；双击选中整词、不改收藏；经辅助功能动作查询所选，卡片按原句解释，收藏仍为未收藏；行悬停背景正常。

T47 总验收对照（2026-10-11）：五类区域均可查（浮窗、文本处理页含逐句对照、生词本、历史详情、学习行）；选区只出工具栏，单击／工具栏／右键／Return／辅助功能动作触发；中日文系统分词；双击、拖拽、复制不误发；学习行收藏与查询互不干扰；释义语言按来源；跨句旧解释标来源并由用户重查；失败重试、同条件合并、迟到不覆盖不重开、设置改变不误命中；发音手动、切换关闭停止、无语音禁用并说明；Esc 先关卡片；不入库不写回。仍未验证、因此 T47 暂不关闭：①系统语音实际发声；②真实 VoiceOver 朗读与公告（仅 AX API 模拟）；③真实 Owlet 安装版配真实模型与真实数据；④系统「提高对比度」设置本身。

## T52：查词快路径改为 ⌘ 单击（已实现）

用户 2026-10-11 要求：查词由单击改为 ⌘ 单击；按住 ⌘ 时鼠标下的词显示悬停提示、光标变手形。

验收：不按 ⌘ 的单击、双击、拖拽、复制回到系统文本行为且不查询；⌘ 单击立即查询所点的词，五类区域一致；学习行 ⌘ 单击只查询、不收藏，普通点击仍收藏；按下或松开 ⌘ 时不移动鼠标也即时更新提示与光标。

结果：`LookupTextView` 在 ⌘ 按下的 mouseDown 中按真实命中取词并立即查询，随后自己吞掉 mouse up，免得学习行的点击手势也收藏；普通单击交还 NSTextView，不再等双击间隔。鼠标在文本内时用本地 flagsChanged 监视器跟踪 ⌘，按住时淡化选中色 30% 加手形光标，否则 I-beam 无提示。原生验证（`--panel` 与默认预览 ⌘5，合成带 ⌘ 的鼠标与 flagsChanged 事件）：不按 ⌘ 悬停为 I-beam 无提示；按下 ⌘ 不移动即出现提示与手形；按住移动提示跟随；松开即消失；普通单击不查询；⌘ 单击立即出卡；双击仍选词出工具栏；学习行 ⌘ 单击出卡且收藏不变，普通点击表达与释义照常切换收藏。format/check 通过。

## T53：学习契约区分词形与原形（已实现）

依据 [BDR-0009](../spec/learning/decisions/BDR-0009-learning-lemma.md)。真实 DeepSeek 调用的学习推荐稳定报 `.format`：模型返回字典形（`跳ね上がる`），语境里是活用形（`跳ね上がっている`），而本地校验要求 `text` 逐字出现在 `context` 中。

范围：契约加可空 `lemma`，`text` 限定为语境中的实际词形；生词本按词形收藏、原形作次级信息；顺带把 BDR-0005 的释义语言随条目保存落实（原为 `ponytail` 占位）。

验收：

- [x] `$defs.learning` 的每个 item 含 `lemma`（可空字符串，列入 `required`）；`text` 必须逐字出现在 `context` 中。
- [x] `LearningResult.parse` 接受与词形不同的 `lemma`，拒绝空白 `lemma` 与重复词形的 `lemma`；缺 `lemma` 键仍按格式错误处理。
- [x] 学习与补释义两处 prompt 都写明分工并给出示例。
- [x] 勾选学习推荐入库时，条目存词形，另存 `lemma` 与释义语言；同一表达再次收藏只填空、不覆盖。
- [x] 生词本详情在表达下方次级显示不同的原形；导出带 `lemma`（`version` 升到 2）。
- [x] 补释义沿用条目已记的释义语言，不再写死简体中文。

验证：`mise run format`、`mise run check` 退出码 0；新增 `LearningContentTests.aLemmaThatDiffersFromTheSentenceFormIsAccepted`（跳ね上がっている／跳ね上がる）与 `aCollectedRecommendationKeepsItsLemma`，`malformedPayloadsAreFormatErrors` 增两条 `lemma` 用例，导出用例断言原形与空原形。未验证：真实 DeepSeek 返回 `lemma` 的稳定性（本地校验只保证形状）。

## T54：修查词分支首轮审阅的三个缺陷（已实现）

来源：`codex exec review --base main` 对 `main..word-lookup` 的首轮审阅，三个 P2 均已确认是缺陷。

验收：

- [x] 语境语言归因：`VocabularyContext` 记自己的语言（`language`），从译文一侧收藏时语境语言取原文语言，不再套用条目语言；历史翻译记录的原文语言从未保存，留空并回退条目语言，不猜。
- [x] 「无原句语境」可达：`LookupText` 增加 `hasSentence`，生词本表达这类没有源句的文本查询时走 `LookupQuery.withoutContext`，卡片显示「无原句语境」，不再把表达本身冒充成语境。
- [x] 重试重盖章：`LookupPresenter.requestCurrent()` 先 `store.stamped(query)` 再请求并更新卡片，换模型或改读音体系后请求与缓存键一致，切回旧模型不会命中另一个模型的答案。

验证：`mise run format`、`mise run check` 退出码 0；新增 `LookupReviewFixTests`（无语境查询、空白选区拒绝、重试重盖章）与 `VocabularyDraftTests.aTranslatedResultKeepsTheSourceSentenceLanguage`。未验证：真实窗口里生词本表达的「无原句语境」卡片观感。

## T55：查词卡可显式加入生词本（已实现）

依据 [BDR-0010](../spec/vocabulary/decisions/BDR-0010-collect-from-lookup.md)，用户 2026-10-11 要求「查询的单词要支持可以加入生词本」。部分取代 BDR-0008 的「查词不入库」。

验收：

- [x] 卡片一个 `加入生词本`／`已收藏` 书签动作，点一下入库、再点一下移除，不确认、不跳页、卡片保持打开。2026-10-11 用户看过首版后要求改为图标并放到 `发音` 左侧，配色与学习行一致（`bookmark`／`bookmark.fill`，已收藏为强调色）。
- [x] 保存内容全部来自本次查词：查询词形、本次语境、本次释义、释义语言、已知原形；不另发模型请求。
- [x] 复用生词本既有规则：同语言同表达复用条目并追加语境，已有释义与原句不被覆盖，无语境查询不伪造原句。
- [x] 文本语言未知（区域未提供、模型也未返回）时不提供该动作；未接入生词本时卡片保持只读。
- [x] 取消收藏删除同一条目；保存或删除失败只更新状态，不改生词本内容。
- [x] 浮窗与主窗口共用应用级生词本，卡片收藏后生词本页立即可见。

验证：`mise run format`、`mise run check` 退出码 0；新增 `LookupCollectionTests` 五条（保存释义与原形不二次请求、语言来自模型回答、无语境不存语境、另一句追加且保留原释义、取消收藏）。预览端到端（`OWLET_PREVIEW_CARD_CHECK=1 python3 scripts/panel-preview.py --panel`）走真实 `LookupPresenter` 与内存生词本：查询命中后 before=false → 加入 after=true、条目有释义与 1 条语境 → 取消 removed=false，输出 `CARD-CHECK PASS`。已用 `mise run dev` 启动应用确认可运行。未验证：本书写环境的 `screencapture` 无屏幕录制权限（`could not create image from display`），因此我无法自己截图核对卡片版式，图标与 `发音` 的并排观感需用户确认；真实模型下的入库结果同样待验。预览新增 `查词卡` 状态（菜单 ⌘6）可在不依赖 popover 的情况下查看卡片版式。

## T56：学习推荐契约失败时纠正一次（已实现，待真实模型复验）

2026-10-11 用户提供「学习推荐」调试页原始返回，证实失败原因与 BDR-0009 的预判不同：三条日语推荐**全部**返回字典形 `text`（`跳ね上がる`／`史上最高値をつける`／`拍車がかかる`），语境里却是活用形，三条都不通过「`text` 逐字出现在 `context`」；同时三条把 `lemma` 原样复制成 `text`，违反「不同才给原形」。即 `json_object` 下模型把 `text` 当词典形、`lemma` 当重复字段。

两层修法：

1. **prompt 措辞**（根因）。原示例 `take a step back` 词形等于原形，模型无从学到「`text` 抄词汇形」。把 `context`／`text`／`lemma` 三项分工拆成短句，示例换成词形≠原形的 `跳ね上がっている`／`跳ね上がる`，并写明不得给字典形、不得重复 `text`。学习与补释义两处同步。
2. **一次纠正重试**。校验失败时不再原样重问：`LearningResult.diagnose` 指出打破的具体规则，第二次请求带上模型自己被拒的回复与这些规则，让它只改该改的地方。只纠正一次，纠正后仍不合规则照样失败；截断、拒绝、空响应与传输错误都不是契约失败，不触发重试。

验收：

- [x] `LearningResult.diagnose` 区分：非 JSON、顶层键不对、缺键、多键、`text`／`language`／`meaning`／`context` 空白或类型错、`kind` 非法、`text` 不在语境中、`lemma` 重复 `text`。
- [x] 第二次请求是独立一次交换（调试页标题「学习推荐（纠正）」），带 `assistant` 原回复与用户纠正说明。
- [x] 纠正后成功则返回结果；仍失败则抛第二次的错误；传输失败与空响应只请求一次。
- [x] 两次提示词都不再示范「词形等于原形」的条目。

验证：`mise run format`、`mise run check` 退出码 0；`LearningContentTests` 新增三条——用用户原始失败回复复现并断言第二次请求确实带回了该回复与「not in its context」规则、第二次仍错时只请求两次、传输失败只请求一次。

**真实模型复验（2026-10-11 21:27，用户提供调试页返回）**：同一段日语、`deepseek-flash`、`reasoning_effort: none`，**首轮即通过**——调试页只有一条「学习推荐」、无失败原因，说明新措辞生效、纠正重试未被触发。返回 10 条逐条核对全部合规：`跳ね上がる`／`史上最高値をつける`／`拍車がかかる` 三条旧失败项现在分别是 `跳ね上がっている`（`lemma` 跳ね上がる）、`史上最高値をつけて`、`拍車がかかっている`，都在语境中；`lemma` 只在两条真正不同时给出（`跳ね上がる`、`映す`），其余为 `null`，不再复制 `text`。

两处观感变化，供判断是否需要收紧：①条目数从 3 升到 10，措辞变清楚后模型更愿意多推荐（契约允许 `items: []`，但没有上限）；②这次同时推荐了中文侧的表达（`现货交易价格正在飙升`、`比期货高出五成`），与 BDR-0005「翻译场景释义=目标语言、可从任一侧收藏」一致，但读日语时是否需要中文条目属产品取舍。

## T57：查词也做一次纠正重试；卡片收藏按钮改原生玻璃（已实现）

用户 2026-10-11 决定：学习推荐条目不设上限（有多少返多少）；把学习那套纠正重试也接到查词；卡片上「加入词库」的按钮改成 liquid glass，与发音按钮一致。

验收：

- [x] 查词契约失败后用 `LookupResult.diagnose` 指出具体问题（缺键／多键、可空键该写 null、`text` 不等于选区、`definition_language` 不符、已知语言没回或回错、非空字段空白或类型错）并再请求一次。
- [x] 可纠正的三类都触发纠正：结构不符、源文拼接不一致、目标语言不一致——用户 2026-10-11 实际撞上的是第三类。
- [x] 只纠正一次；第二次仍不合格照原错误抛；传输、截断、拒绝、空响应不触发；连 JSON 都不是的回复不触发（没有可指出的规则）。
- [x] 两次往返都进调试页，第二条标题为「查词 · zh-Hans（纠正）」。
- [x] 学习与查词共用一条规则：只有能指出具体规则的回复才值得再问一次。
- [x] 查词卡收藏按钮与发音按钮同形：都是 `CardGlassButton`（`.glass`、圆形边框、36pt、13pt 字形），不再各写一份；已收藏用强调色。
- [x] 学习推荐不设条目上限。

验证：`mise run format`、lint 与 generate 通过；`xcodebuild … CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual test` 退出码 0，328 项测试通过。新增 `LookupRetryTests` 三条（漏可空键被纠正且第二次请求带回了原回复与缺键说明、第二次仍错只请求两次、传输失败只请求一次）、`LookupCollectionTests.aStoredWordReadsAsCollectedWhenTheCardReopens`，学习侧三条同规则回归。

**本会话末的环境限制**：`mise run check` 的 test 步骤在本 shell 里失败于 `Command CodeSign failed`——`Signing.local.xcconfig` 用 `Apple Development` 证书，而非交互 shell 无法解锁钥匙串（`security find-identity` 能看到该证书，但读不到私钥）。同一条命令加 `CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual` 即通过。这是环境问题，不是代码问题；交互终端里的 `mise run check` 不受影响（交接文档 2026-10-11 已记录同一现象）。

未验证：真实 `deepseek-flash` 在查词上的纠正效果——仍缺「查词 · zh-Hans」的原始返回。

## T58：发音停止的无谓拆队列（已修）；音频噪声确认非应用成因

2026-10-11 用户点发音后 console 出现四条：`layoutSubtreeIfNeeded` 警告、`AddInstanceForFactory: No factory registered`、`AUCrashHandler.mm:126 invalidated`、`AVAudioBuffer.mm:291 mBuffers[0].mDataByteSize (0) should be non-zero`，以及 `AudioQueue underflow #N: injecting silence …`。

**已修**：`LookupSpeech.live` 的 `stop()` 原本无条件 `stopSpeaking(at: .immediate)`，而卡片关闭、切换查询、打开卡片都会调用它——一次都没播过也一样。对静音合成器做立即停止就是立刻拆掉它的音频队列。现在 `LiveSpeech` 用 delegate 回调（`didStart`／`didFinish`／`didCancel`）记住「真的有声音在播」，无事可做时直接返回；顺带把每次调用都枚举全部已安装语音改为按语言缓存。`mise run check` 退出码 0。

**未能归因、且已确认不是应用造成的（2026-10-11 第二轮实测）**：

- 用户用 Xcode Build and Run、默认扬声器、真机点发音仍看到 `AVAudioBuffer.mm:291` 与 `AudioQueue underflow #1 … minInFlight=3 … refills=58`。
- 追加实测，全部无噪声：独立探针（直接 `AVSpeechSynthesizer`，正常播完／播 0.4 秒后 `.immediate` 打断／`.word` 打断）；按应用调用形状写的探针（静音 stop 两次 → speak → 1.2 秒后 stop），stdout 与 stderr 都为空；预览钩子（静音 stop、连点六次、打断播放）。
- `minInFlight=3` 说明队列里**始终有在途缓冲**，不是"没人喂数据"；`refills=58` 说明它在正常补充。即设备侧一次缓冲欠载播报。
- 日志中的 `AddInstanceForFactory: No factory registered for id <CFUUID …>`、`AUCrashHandler.mm:126 invalidated`、`AVAudioBuffer.mm:291` 全属 coreaudiod 与音频单元层。应用不创建、不配置、不入队任何 `AVAudioBuffer`，也没有 `AVAudioSession` 代码，全仓只有一句 `AVSpeechSynthesizer.speak`。
- 结论：**这些是 CoreAudio 在新建音频单元与拆队列时的固有记录，应用这层没有可改的余地**。判据是「有没有可听的卡顿」——没有就当作已知噪声放着；有才值得换 TTS 实现或显式配置音频会话（都要评估代价）。不要再为这几条日志改应用代码。

**顺带澄清**：`layoutSubtreeIfNeeded` 那条警告**不来自应用**。全仓只有两处调用它——`OwletTests/App/Panel/PanelMetricsTests.swift` 与 `scripts/PanelPreview.swift` 的 `--screenshots` 模式。Xcode 的 console 是累积的，用户那份日志里混着此前跑测试的输出，因此出现了这条。
**顺带澄清**：`layoutSubtreeIfNeeded` 那条警告**不来自应用**。全仓只有两处调用它——`OwletTests/App/Panel/PanelMetricsTests.swift` 与 `scripts/PanelPreview.swift` 的 `--screenshots` 模式，都是测试／预览路径。用户 console 里出现它，说明当时跑的是预览而非 app。

## T60：母语只影响学习内容 + 释义语言按当下映射（已实现）

依据 [BDR-0012](../spec/learning/decisions/BDR-0012-native-language.md)，以及 [BDR-0005](../spec/learning/decisions/BDR-0005-definition-language.md) 2026-10-12 的 §3 修订。用户要求「一起考虑」，决策经五轮问答定下（每轮一个），实现后由用户统一测试。

范围与取舍：母语是「这是我的语言」这个**事实**的单选，不是一份排除名单——黑名单要求用户预先想到所有不学的语言。它**只影响学习内容包含哪些条目**，不参与释义语言的计算；两种操作的学习推荐都受它约束（润色母语文本不产生学习内容，也不发请求）。释义语言改为**生成与重新生成时按当下映射算**，条目上的语言字段改为记录已存释义实际的语言；旧条目不自动重算（映射一改就批量重发会触发 N 次调用且要处理部分失败），详情给一次一条的重新生成入口。

验收：

- [x] `SettingsStore.nativeLanguage`（默认空＝未指定）与 `learnsFrom(_:)`；比较用 `LanguageTag.same`，避免 `zh-Hans`／`zh-Hant` 前缀相混。
- [x] 「语言」页映射表旁的单选，候选来自 `SettingsStore.languages()`；footer 说明它**不改变释义语言**。
- [x] 学习请求按母语过滤：提示词条目 `learningSkipNative`（发给模型，不本地化）+ 返回后按 `item.language` 本地兜底。
- [x] 润色母语文本：`LearningRequest.from` 返回 nil → 不发请求、不显示学习入口（入口与请求都由它派生）；历史详情用同一判据。
- [x] `CollectionAction.fillMeaning` 与 `VocabularyEntry.lookupOrigin` 改用当下映射（`CollectionAction.mapping` 可注入）。
- [x] 条目记已存释义的语言；`currentMeaningLanguage` / `meaningLanguageIsStale` 为纯函数；详情在两者不一致时显示「用%@重新生成」。
- [x] 6 条测试（母语条目被丢弃、未设母语时全保留、润色母语不请求、翻译有一侧是母语仍请求、fillMeaning 按映射并更新条目语言、无释义不判过期）。
- [x] 新文案 4 条进 `strings/translations.json`，目录 239 → 243 条；顺带修掉 `TargetMappingSettingsView` footer 的 i18n 漏网。

验证：`mise run lint` 退出码 0（格式、空白、目录与数据源一致）。**测试未能运行**——本机全工程无法编译（`swift-plugin-server` 报 malformed response，3600+ 个 `@Observable` macro 展开失败），按用户要求留到最后统一测试。
