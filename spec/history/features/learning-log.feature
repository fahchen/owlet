Feature: 历史作为学习本
  用户回看历史时能看到那天翻了什么、在哪里遇到的、从中收藏了哪些词。

  Rule: 历史记录原文所在的 App
    Scenario: 划选触发的翻译
      Given 用户在邮件应用中划选文本并触发翻译
      When 结果成功生成
      Then 历史记录的来源 App 是邮件应用

    Scenario: 手动输入的翻译
      Given 用户在主窗口手动输入文本并翻译
      When 结果成功生成
      Then 历史记录没有来源 App

  Rule: 历史列表按天分组，最新在前
    Scenario: 跨天的记录
      Given 用户今天有 3 条记录、昨天有 5 条
      When 用户打开历史
      Then 记录分为两组，今天的一组在前

  Rule: 历史可按有收藏与来源 App 筛选，与翻译／润色筛选叠加
    Scenario: 只看有学习产出的润色
      Given 用户有多条翻译与润色记录，其中部分收藏过表达
      When 用户选择润色并勾选「有收藏」
      Then 只显示收藏过表达的润色记录

    Scenario: 只看来自某个 App 的记录
      Given 用户有来自邮件应用与 Slack 的记录
      When 用户选择来源 App 为 Slack
      Then 只显示原文来自 Slack 的记录

  Rule: 历史详情关联从该记录收藏的词条
    Scenario: 查看收藏了哪些词
      Given 用户从一条记录收藏了 "follow up" 与 "bandwidth"
      When 用户打开该记录的详情
      Then 详情列出这两个词条
      And 选择任一词条可打开生词本中的对应条目

    Scenario: 词条删除后关联减少
      Given 用户从一条记录收藏了 "follow up" 与 "bandwidth"
      When 用户在生词本中删除 "bandwidth"
      Then 该记录的详情只列出 "follow up"

    Scenario: 历史删除不影响词条
      Given 用户从一条记录收藏了 "follow up"
      When 用户删除该记录
      Then 生词本中的 "follow up" 及其语境仍在
