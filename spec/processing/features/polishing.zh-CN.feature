# English: polishing.feature · 简体中文: polishing.zh-CN.feature
Feature: 润色
  用户可以阅读原文及改善后的表达。

  Rule: 保留语言与原意并提供一个结果
    Scenario: 修正英语语法
      Given 原文为 "She go to work every day."
      When 用户调用润色快捷键
      Then 结果为保留原意的正确英语表达
      And 原文与润色结果分别以普通文本显示且各出现一次
      And 不使用差异背景色或删除线
      And 不提供修改对照开关
      And 不提供多个风格版本
      And 原选区尚未被替换

    Scenario: 润色日语
      Given 原文是一段日语工作沟通内容
      When 用户执行润色
      Then 结果仍为日语
      And 不添加原文没有的事实或承诺

  Rule: 原文和润色结果不依赖学习内容开关
    Scenario: 关闭学习仍可使用润色结果
      Given 润色学习内容开关关闭
      When 润色成功
      Then 展示普通原文和润色结果
      And 不自动生成学习推荐
      And 用户可以复制结果或主动替换原选区
