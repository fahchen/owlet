Feature: 自行配置模型服务
  用户使用自己的兼容服务与 API Key，设置放在独立的设置窗口里。

  Rule: 设置是独立窗口并按标签页分组
    Scenario: 从 App 菜单打开
      When 用户选择 App 菜单的「设置…」或按下 ⌘,
      Then 打开独立的设置窗口
      And 主窗口侧栏不提供设置入口

    Scenario: 标签页分组
      Given 用户打开设置
      Then 分为通用、语言、模型、Prompt 四个标签页
      And 每个标签页内的设置项再按分组显示

    Scenario: 回到上次的标签页
      Given 用户上次停留在语言标签页
      When 用户重新打开设置
      Then 直接显示语言标签页

    Scenario: 改动即时生效
      Given 用户打开设置
      Then 不存在整页的保存按钮
      When 用户修改任一项设置
      Then 该项立即生效并持久化

  Rule: 语言子集限定可选语言
    Scenario: 默认子集
      Given 用户未修改语言子集
      When 用户打开语言标签页
      Then 列出简体中文、英语、日语
      And 目标语言与映射表只提供这三种语言

    Scenario: 添加语言
      When 用户在语言标签页添加一种语言
      Then 该语言出现在目标语言与映射表的候选中

    Scenario: 移除语言时收干净
      Given 某种语言已在映射表中使用且是当前兜底目标
      When 用户移除该语言
      Then 引用它的映射行一并删除
      And 兜底目标改到子集内的第一种语言

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
    Scenario: 查看默认并提交自定义内容
      Given 用户未修改翻译 System Prompt
      When 用户打开设置
      Then 显示完整默认翻译 Prompt
      When 用户编辑翻译 Prompt 并离开编辑框
      Then 后续翻译和翻译并替换使用该配置
      And 润色 Prompt 不受影响

    Scenario: 恢复默认
      Given 用户已有自定义润色 Prompt
      When 用户恢复润色默认 Prompt 并离开编辑框
      Then 后续润色使用显示的默认内容

    Scenario: 拒绝空白 Prompt
      When 用户尝试提交仅含空白的 System Prompt
      Then 提示不能生效
      And 已生效的配置不变

  Rule: 用户可以调整思考强度
    Scenario: 沿用服务商默认
      Given 用户未设置思考强度
      When 应用组装一次请求
      Then 请求不包含思考强度参数
      And 思考行为由服务商与模型决定

    Scenario: 关闭或改变思考强度
      Given 用户将思考强度设为关闭或某一档
      When 应用组装一次请求
      Then 请求包含对应的思考强度参数
      And JSON 返回契约与本地校验不变

    Scenario: 档位按模型映射
      Given 用户选择某个思考强度档位
      When 当前模型支持该档位
      Then 请求发送该模型接受的值
      And 模型不支持该档位时发送最近的较低档

    Scenario: 模型不使用思考强度
      Given 当前模型不接受推理参数
      When 用户选择任一档位
      Then 请求不包含思考强度参数

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
