[English](roadmap.md) · [简体中文](roadmap.zh-CN.md)

# Owlet · 路线图

还没收尾的事。行为以 `spec/` 为准；已发布的改动见 [CHANGELOG.md](../CHANGELOG.md)。新工作在这里登记一条，写明验收条件与验证方式；发布并验证后删掉该条。

## 待验收

已实现，但部分证据只能由人或真实环境给出。

| 事项 | 还剩什么 | 位置 |
| --- | --- | --- |
| 按 Figma 画板重做的浮窗 | 对照画板的视觉复核：圆角、错误文字颜色、活跃玻璃、交互状态。 | [Panel 调试与测试](panel-debugging-and-testing.zh-CN.md) |
| 阅读查词第一步 | 五类区域均已可用；待验收：真实系统语音发音、真实 VoiceOver、安装版。 | [word-lookup.feature](../spec/vocabulary/features/word-lookup.feature)、[BDR-0008](../spec/vocabulary/decisions/BDR-0008-reading-word-lookup.md) |
| 学习推荐的纠正重试 | 用真实模型复验：一次纠正能修好违约的返回。 | [LLM 契约](../spec/llm/contract.md) |
| 选中文字读取 | 辅助功能路径、⌘C 兜底与粘贴写回已实现；在各真实应用上的兼容性仍需手测。 | [selected-text-capture.zh-CN.md](selected-text-capture.zh-CN.md) |

## 设计就绪，未实现

- **模型返回的流式显示。** 只改「何时看见」，不改请求契约、本地校验与写回。等待对替换入口的决定。见 [streaming-output.md](streaming-output.md)。

## 尚未进入产品定义的提案

- **屏幕区域 OCR 输入。** 在屏幕上框一个矩形，用 Vision 识别其中文字；只能复制，没有可写回的地方。见 [screen-region-input.zh-CN.md](screen-region-input.zh-CN.md)。
- **连续语音输入。** 见 [speech-input.zh-CN.md](speech-input.zh-CN.md)。暂不做。

## 首版不做

复习、间隔重复与掌握度；自动收藏；同步与账号；多版本润色与语气模板。见 [product.zh-CN.md](../spec/product.md) 的「首版不做」。
