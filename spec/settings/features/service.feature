Feature: 自行配置模型服务
  用户使用自己的兼容服务与 API Key。

  Rule: 用户决定请求发送到哪里
    Scenario: 保存服务配置
      When 用户设置兼容接口地址、API Key 与模型名
      And 用户执行翻译
      Then 使用该服务与模型处理文本
      And 应用说明处理文本会发送到配置的服务

    Scenario: 未完成配置
      Given 必需的模型服务配置缺失
      When 用户发起翻译
      Then 提示用户补齐配置
      And 不将请求发送到其他默认服务

  Rule: 私密凭证与本地内容受保护
    Scenario: 凭证不随内容导出
      Given 用户已配置 API Key 并收藏表达
      When 用户导出生词本
      Then 导出内容不包含 API Key

    Scenario: 内容本地保留
      Given 用户已生成历史并保存收藏
      When 用户重启应用
      Then 可在本机读取这些内容
      And 不需要登录应用账号或开启同步

  Rule: 用户可以自定义 System Prompt
    Scenario: 查看默认并保存自定义内容
      Given 用户未修改翻译 System Prompt
      When 用户打开设置
      Then 显示完整默认翻译 Prompt
      When 用户编辑并保存翻译 Prompt
      Then 后续翻译和翻译并替换使用该配置
      And 润色 Prompt 不受影响

    Scenario: 恢复默认
      Given 用户已有自定义润色 Prompt
      When 用户恢复润色默认 Prompt 并保存
      Then 后续润色使用显示的默认内容

    Scenario: 拒绝空白 Prompt
      When 用户尝试保存仅含空白的 System Prompt
      Then 提示不能保存
      And 已生效的配置不变

  Rule: 自定义 Prompt 不解除 JSON 返回契约
    Scenario: 返回非 JSON 文本
      Given 用户执行翻译并替换
      When 模型返回无法通过 JSON 契约校验的内容
      Then 提示返回格式不符合要求
      And 不替换原文也不写成成功历史

    Scenario: JSON 配对缺失原文
      Given 原文包含两个句子
      When 模型返回的 JSON 仅覆盖第一个句子
      Then 拒绝该结果并保留原文
