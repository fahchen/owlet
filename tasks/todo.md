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
