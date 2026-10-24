[English](roadmap.md) · [简体中文](roadmap.zh-CN.md)

# Owlet · 路线图

还没收尾的事。行为以 `spec/` 为准；已发布的改动见 [CHANGELOG.md](../CHANGELOG.md)。新工作在这里登记一条，写明验收条件与验证方式；发布并验证后删掉该条。

## 待补测试

| 事项 | 还剩什么 | 位置 |
| --- | --- | --- |
| 选中文字读取 | 两个自动化检查缺失：捕获期间切换前台应用已在主线程比对 PID 拒绝，但尚无测试；⌘C 回退的剪贴板放回只在拍平后的逻辑里覆盖，真实剪贴板内容与 `changeCount` 不变的端到端检查仍待补。 | [selected-text-capture.zh-CN.md](selected-text-capture.zh-CN.md) |

## 尚未进入产品定义的提案

- **iCloud 同步。** 通过 CloudKit 私有数据库在用户的多台 Mac 间同步生词本、语境、历史与一组白名单设置；默认关闭，需要团队签名的构建。把同步移出「首版不做」。见 [icloud-sync.zh-CN.md](icloud-sync.zh-CN.md)。
- **用户自定义的词条区块。** 词条的辞典内容由模型生成，按用户定义的区块排列，显示在查词卡与生词本词条中，并支持跨已保存词条批量更新。本轮只接 LLM，不接本地词典来源。见 [dictionary-blocks.zh-CN.md](dictionary-blocks.zh-CN.md)。
- **连续语音输入。** 见 [speech-input.zh-CN.md](speech-input.zh-CN.md)。暂不做。

## 首版不做

复习、间隔重复与掌握度；自动收藏；同步与账号；多版本润色与语气模板。见 [product.zh-CN.md](../spec/product.md) 的「首版不做」。
