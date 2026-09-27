Feature: 翻译
  用户可以将选中或输入的文本翻译为目标语言。

  Rule: 自动识别原文语言并记住目标语言
    Scenario: 首次翻译英文
      Given 用户未设置目标语言
      And 原文为 "Could you send me the report?"
      When 用户执行翻译
      Then 结果表达请求发送报告的含义且使用中文
      And 原文语言识别为英语

    Scenario: 记住切换后的目标语言
      Given 用户将目标语言切换为日语
      When 用户重启应用并翻译中文文本
      Then 目标语言仍为日语
      And 结果使用日语并保留原意

  Rule: 没有可读取的选区仍可翻译
    Scenario: 手动输入
      Given 当前没有可读取的选中文本
      When 用户调用翻译快捷键
      Then 浮窗允许输入或粘贴文本
      When 用户输入 "お疲れさまです" 并执行翻译
      Then 浮窗显示目标语言译文

  Rule: 普通翻译不直接写回
    Scenario: 查看并复制译文
      Given 用户通过普通翻译入口获得译文
      Then 原选区内容保持不变
      When 用户复制结果
      Then 剪贴板包含译文

  Rule: 处理失败不得呈现为成功
    Scenario: 服务拒绝请求
      Given 翻译服务返回认证失败
      When 用户执行翻译
      Then 用户看到可理解的错误并可在修正配置后重试
      And 原文保持不变

    Scenario: 旧请求晚于新请求完成
      Given 用户对文本 A 发起翻译
      And 随后对文本 B 发起新翻译
      When 文本 A 的结果晚于文本 B 返回
      Then 当前结果仍属于文本 B
