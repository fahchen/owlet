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
