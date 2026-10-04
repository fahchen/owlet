Feature: 释义语言
  用户得到的释义使用自己正在练习的语言，而不是固定的母语。

  Background:
    Given 目标映射为「英语 → 简体中文」与「简体中文 → 英语」
    And 兜底目标为简体中文

  Rule: 翻译场景下释义严格使用本次目标语言
    Scenario: 读英文时收藏英文表达
      Given 用户把一段英文翻译成中文
      When 用户从原文收藏 "follow up"
      Then 释义是中文

    Scenario: 写中文时收藏中文表达
      Given 用户把一段中文翻译成英文
      When 用户从原文收藏 "把问题收敛一下"
      Then 释义是英文

    Scenario: 从译文一侧收藏仍用目标语言
      Given 用户把一段中文翻译成英文
      When 用户从译文收藏 "follow up"
      Then 释义是英文，而不是中文

  Rule: 润色场景下释义语言按目标映射查原文语言
    Scenario: 润色英文
      Given 用户润色一段英文
      When 用户展开学习区
      Then 推荐与释义是中文

    Scenario: 润色中文
      Given 用户润色一段中文
      When 用户展开学习区
      Then 推荐与释义是英文

    Scenario: 原文语言不在映射表中
      Given 用户润色一段日语
      When 用户展开学习区
      Then 推荐与释义使用兜底目标语言

  Rule: 释义语言随条目保存，事后生成沿用
    Scenario: 映射表改动不影响旧条目
      Given 用户在「中文 → 英语」翻译时收藏了一条中文表达
      And 之后把映射改为「中文 → 日语」
      When 用户在生词本中重新生成该条目的释义
      Then 释义仍是英文

    Scenario: 从历史详情收藏翻译记录
      Given 一条把英文翻译成中文的历史记录
      When 用户从该记录的学习区收藏表达
      Then 释义是中文

    Scenario: 从历史详情收藏润色记录
      Given 一条润色中文的历史记录
      When 用户从该记录的学习区收藏表达
      Then 释义是英文

  Rule: 升级前的条目不回填
    Scenario: 旧条目保持原有释义
      Given 升级前收藏的条目带有中文释义
      When 用户升级后打开生词本
      Then 该条目释义内容不变
      And 其释义语言记为简体中文
