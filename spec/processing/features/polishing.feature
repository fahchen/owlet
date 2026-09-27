Feature: 润色
  用户可以改善表达并查看修改对照。

  Rule: 保留语言与原意并提供一个结果
    Scenario: 修正英语语法
      Given 原文为 "She go to work every day."
      When 用户调用润色快捷键
      Then 结果为保留原意的正确英语表达
      And 展示原文与结果的修改对照
      And 不提供多个风格版本
      And 原选区尚未被替换

    Scenario: 润色日语
      Given 原文是一段日语工作沟通内容
      When 用户执行润色
      Then 结果仍为日语
      And 不添加原文没有的事实或承诺

  Rule: 修改对照不依赖学习内容开关
    Scenario: 关闭学习仍可使用润色结果
      Given 润色学习内容开关关闭
      When 润色成功
      Then 展示润色结果和修改对照
      And 不自动生成学习推荐
      And 用户可以复制结果或主动替换原选区
