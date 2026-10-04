Feature: 统一收藏
  用户可以主动保存词汇、短语或整句及其语境。

  Rule: 收藏不依赖学习推荐
    Scenario Outline: 手动选择内容入库
      Given 学习推荐关闭
      And 用户正在查看 "<来源>"
      When 用户选择一个 "<内容>" 并收藏
      Then 条目立即保存且不要求先填写表单
      And 保留表达、语言与原句语境
      Examples:
        | 来源 | 内容 |
        | 原文 | 词汇 |
        | 翻译结果 | 短语 |
        | 润色结果 | 整句 |
        | 历史详情 | 短语 |

    Scenario: 收藏润色表达
      Given 用户查看润色结果
      When 用户收藏改进后的表达
      Then 条目保留修改前后的对照

    Scenario: 已有语境释义
      Given 被收藏的内容已有语境释义
      When 用户收藏该内容
      Then 释义随条目一起保存

    Scenario: 缺失释义且补充失败
      Given 用户手选的内容没有语境释义
      When 用户收藏后补充释义失败
      Then 已保存的表达及原句仍存在
      And 用户可以重试补充释义

  Rule: 重复表达可以追加语境
    Scenario: 同一英语表达出现在新原句中
      Given 生词本已收录英语表达 "follow up"
      When 用户从另一个原句收藏 "follow up" 并选择追加语境
      Then 原条目增加新语境
      And 旧语境不被覆盖

    Scenario: 不同语言的同形表达
      Given 生词本已收录中文表达 "手紙"
      When 用户收藏日语表达 "手紙"
      Then 保存为不同语言的条目
      And 不自动合并两者的语境

    Scenario: 重复提交同一语境
      Given 同一表达的当前语境已经保存
      When 用户再次提交同一收藏
      Then 不重复追加相同语境

  Rule: 收藏记录来源入口与原文所在的 App
    Scenario Outline: 来源入口
      When 用户通过 "<入口>" 收藏一个表达
      Then 该语境的来源入口记为 "<来源>"
      Examples:
        | 入口 | 来源 |
        | 手选原文或结果 | 划选 |
        | 学习区勾选 | 学习推荐 |
        | 历史详情学习区 | 历史 |

    Scenario: 来源 App 随链路传递
      Given 用户在邮件应用中划选文本并触发翻译
      When 用户从学习区收藏一个表达
      Then 该语境的来源 App 是邮件应用

    Scenario: 从历史收藏沿用历史的来源 App
      Given 一条原文来自 Slack 的历史记录
      When 用户从该记录的学习区收藏表达
      Then 该语境的来源 App 是 Slack

    Scenario: 手动输入没有来源 App
      Given 用户在主窗口手动输入文本并翻译
      When 用户收藏一个表达
      Then 该语境没有来源 App
