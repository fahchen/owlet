[English](icloud-sync.md) · [简体中文](icloud-sync.zh-CN.md)

# iCloud 同步

状态：设计提案，未实现。同步目前列在产品定义的「首版不做」里（`spec/product.md:124`）；本提案把「同步」移出该清单，但不动「账号体系」，需要新增 BDR 与设置页。以下内容均未实现。

## 今天的数据存放

- 一个 SwiftData 存储同时装着生词本与历史：`VocabularyEntry`、`VocabularyContext`、`HistoryRecord` 共用一个容器（[VocabularyStore.swift:149](../Owlet/Vocabulary/VocabularyStore.swift)、[HistoryRecord.swift](../Owlet/History/HistoryRecord.swift)）。
- 生词本的唯一性来自数据库约束 `#Unique<VocabularyEntry>([\.language, \.expression])`（[VocabularyEntry.swift:7](../Owlet/Vocabulary/VocabularyEntry.swift)），并配合应用层的查重（[VocabularyStore.swift:23](../Owlet/Vocabulary/VocabularyStore.swift)）。
- 设置存在 `UserDefaults`；API Key 在钥匙串。除模型请求外，应用不访问网络。
- 默认 ad-hoc 签名（[Signing.xcconfig](../Signing.xcconfig)），没有 entitlements 文件；有证书的机器可以在被忽略的 `Signing.local.xcconfig` 里指定团队。

## 选定的机制

**SwiftData + CloudKit 私有数据库**（`ModelConfiguration(cloudKitDatabase:)`，底层是 `NSPersistentCloudKitContainer`），外加 **`NSUbiquitousKeyValueStore`** 同步一组白名单设置。

| 备选 | 不选的理由 |
| --- | --- |
| 自建 CloudKit 记录 | 合并完全可控，代价是手写同步引擎；数据只是单个用户的生词本。 |
| iCloud Drive 里的一个文件 | 单文件没有记录级合并：两台设备同时写会整份丢一边；生词本与历史还得自己做文件格式和冲突处理。 |
| 第三方同步服务 | 引入账号、依赖与应用不需要的服务器；用户要的是 iCloud。 |
| 不同步，导出／导入 | 现有导出已能做（[VocabularyExport.swift](../Owlet/Vocabulary/VocabularyExport.swift)），但不满足需求。 |

CloudKit 私有数据库只有用户自己的 iCloud 账号可以访问；Apple 在传输与静态存储时加密，但**不是端到端加密**，设置页文案不得声称端到端。

## 同步什么

| 数据 | 同步 | 理由 |
| --- | --- | --- |
| 生词本条目及其语境 | 是 | 这就是功能本身。 |
| 历史 | 是（决策 1） | 同一个存储；不同步就必须拆容器。这也意味着一台 Mac 清空历史会清空所有设备。 |
| 设置白名单 | 是，走键值存储（决策 2） | 目标映射、语言子集、母语、显示方式、自定义 Prompt，以及之后的词条区块，都是用户写的内容。 |
| API Key | **否**（决策 3） | 留在各设备钥匙串。同步密钥是另一类风险。 |
| 快捷键、浮窗位置、界面语言、调试开关 | 否 | 设备本地选择；一个快捷键在一台 Mac 上合适，在另一台上可能已被占用。 |
| 查词缓存、调试记录、选区文本 | **永不** | 沿用现有隐私规则：只在内存里，从不落盘。 |

## CloudKit 对模型的代价

- 不支持 `#Unique`。数据库约束必须去掉；应用层查重保留，它已经阻止同设备重复。两台设备离线各自收藏同一个表达，仍可能出现两行。
- 每个属性都需要默认值（现在都有），关系需要按 CloudKit 的要求可选；to-many 的确切要求要在实现前对照 SDK 核实。
- 每个条目新增一个 UUID 属性。`persistentModelID` 跨存储不稳定，而合并重复需要确定性的胜者。
- 首次开启同步时现有存储要迁移；迁移本身与「已有记录会被上传」都要在真实的两台设备上核实。

## 同意与状态

- 设置项**默认关闭**。开启时说明什么会离开这台 Mac（生词本、可选的同步历史、设置白名单），以及 Apple 把它们存在用户的私有 iCloud 里。
- 同步需要带 iCloud 权限的团队签名。ad-hoc 构建无法同步；设置页显示「此构建不支持同步」，而不是静默失败。带 iCloud entitlement 但 ad-hoc 签名的应用能否正常启动，需要实测；entitlement 必须能随签名配置切换，普通本地构建保持不变。
- 没有 iCloud 账号或受限：设置页说明并指向系统设置；本地使用完全不受影响。
- 切换开关需要重启应用，因为 `ModelContainer` 在启动时选定。关闭同步停止同步、保留本地数据，且**不删除**私有数据库中的副本（决策 5）。
- 同步状态来自 CloudKit 的账号状态与持久化存储的同步事件；设置页显示上次同步状态与错误，但不阻塞生词本。

## 冲突

- SwiftData + CloudKit 以字段为单位、后写覆盖。对单个用户的两台 Mac 可以接受：较新的释义或笔记胜出，旧文字不做合并。
- 生词本可能出现重复行（同语言、同表达）。**不自动删除**：两台设备可能各自决定保留不同的一行，两个删除都会传播，最后两边都空。生词本改为提供一个**「合并重复项」**维护动作，胜者规则确定（`createdAt` 最早，UUID 兜底）：先按现有同内容规则合并语境（[VocabularyContext.hasSameContent](../Owlet/Vocabulary/VocabularyEntry.swift)），再删除落选行。动作由用户发起，显示发现多少对，绝不自动运行（决策 4）。
- 两台设备产生的相同语境只显示一次，并由同一动作合并。
- 历史是追加式，并发追加可以共存；清空与删除会传播。

## 设置走键值存储

- KVS 只是小型镜像，不是事实来源：`UserDefaults` 仍是本地权威，白名单键在修改时写入、启动时读取。
- 按 key 后写覆盖，符合「两台 Mac 同一设置，最新一次编辑生效」的预期；没有合并界面。
- 存储有硬上限（每个应用 1 MB）；当前白名单远低于上限。写入前检查上限，超出时明确失败，不截断。
- 不在白名单里的键从不读写 KVS，未来的新设置不会意外开始同步。

## 集成缝

- `VocabularyStore.makeContainer()` 是唯一选择配置的地方：默认本地，开启且构建有权限时用云端。测试继续用内存容器，不碰 CloudKit。
- 一个小的 `SyncStatus` 可观察对象（账号状态、开关、最近事件）注入设置页；测试用假实现。
- KVS 放在 `SettingMirror` 缝后面，白名单集中在一处，测试不读真实 ubiquity 存储。
- 合并动作放在 `VocabularyStore` 现有收藏逻辑旁，胜者规则集中在一个函数里，测试可直接驱动。

## 需要人决定

1. **历史。** 一起同步（建议：同一个存储、同一份同意），还是拆存储把历史留在本地。
2. **设置白名单。** 同步用户写的设置（建议），还是先只同步生词本，之后再补设置。
3. **API Key。** 各设备各自配置（建议），还是用可同步的钥匙串项让一台 Mac 用另一台的 Key。
4. **重复项。** 手动「合并重复项」（建议），还是按确定性胜者自动合并。
5. **关闭同步。** 保留云端副本（建议），还是另外提供「删除 iCloud 数据」确认项。

## 必须在真机上核实

- 带 iCloud 权限的签名构建，两台 Mac 同一 iCloud 账号：首次开启、既有记录上传、编辑、删除，以及两边离线各产生一个重复。
- 带 entitlement 的 ad-hoc 构建是否正常启动、CloudKit 报什么；设置页文案取决于结果。
- 首次开启同步时现有存储的迁移；先备份。
- 两台 Mac 间 KVS 的延迟与冲突行为。
- 一个真实规模的历史带来的 iCloud 存储增长。
- 离线与重连后的同步事件；没有同步完成时，设置页不得显示「已同步」。
