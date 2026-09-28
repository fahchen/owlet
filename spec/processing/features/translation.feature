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

  Rule: 读取失败后仍可通过手动输入翻译
    Scenario: 手动输入
      Given 当前没有可读取的选中文本
      And 浮动工具栏尚未展开
      When 用户调用翻译快捷键
      Then 显示紧凑的读取失败提示和手动输入入口
      And 不展开完整浮动工具栏
      When 用户选择手动输入
      Then 在完整窗口中允许输入或粘贴文本
      When 用户输入 "お疲れさまです" 并执行翻译
      Then 完整窗口显示目标语言译文

  Rule: 普通翻译不直接写回
    Scenario: 查看并复制译文
      Given 用户通过普通翻译入口获得译文
      Then 原选区内容保持不变
      When 用户复制结果
      Then 剪贴板包含译文

  Rule: 复制结果即完成一次交互
    Scenario: 在浮窗复制译文
      Given 用户已在浮窗获得译文
      When 用户复制结果
      Then 剪贴板包含译文
      And 浮窗关闭

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

  Rule: 翻译预览逐句对齐
    Scenario: 多句英文译为中文
      Given 用户选择逐句对照显示
      And 原文包含多个英文句子
      When 中文译文生成完成
      Then 每句英文下方显示对应中文译句
      And 长句自然换行后仍保持在同一对照组
      And 复制或替换仅使用中文译文

  Rule: 翻译显示偏好可配置且持久化
    Scenario: 默认分区显示
      Given 用户未修改翻译显示方式
      When 翻译完成
      Then 完整原文与完整译文分别显示
      And 不逐句交错排列

    Scenario: 两种排列都同时显示两侧
      Given 原文与译文都已生成
      When 内容区宽度不小于 720pt
      Then 原文与译文左右平分宽度并各自滚动
      And 学习表达跟着译文一侧
      When 内容区宽度小于 720pt
      Then 原文与译文上下平分高度并各自滚动
      And 学习表达仍跟着译文一侧

    Scenario: 转为逐句对照
      Given 用户已经获得翻译结果
      When 用户在设置的通用页把显示方式切为逐句对照
      Then 完整窗口和浮层使用同一显示偏好
      And 不因显示方式改变而重新请求模型
      And 重启后仍保留逐句对照偏好
