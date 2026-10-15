# English: enrichment.feature · 简体中文: enrichment.zh-CN.feature
Feature: 按需补充条目信息
  用户收藏时只付出最少的等待，回头看词时再一键补上读音与词性，并能单独刷新任一项。

  Background:
    Given 模型服务已配置
    And 生词本已收录英语表达 "bandwidth"

  Rule: 收藏时不请求读音与词性
    Scenario: 收藏后立即查看
      When 用户收藏后立即打开该条目
      Then 条目已存在
      And 读音与词性为空

  Rule: 「补充缺失」只填空字段，不覆盖已有内容
    Scenario: 补上读音与词性
      Given 该条目有释义、无读音、无词性
      When 用户执行「补充缺失」
      Then 读音与词性填入
      And 释义保持原样

    Scenario: 保留用户改过的值
      Given 用户已把该条目的读音改成自己的标注
      And 词性为空
      When 用户执行「补充缺失」
      Then 只填入词性
      And 读音仍是用户改过的值

    Scenario: 没有缺失时不可用
      Given 该条目释义、读音、词性都已有
      Then 「补充缺失」不可用

  Rule: 释义、读音、词性各有独立「重新生成」，只覆盖该项
    Scenario: 只重新生成读音
      Given 该条目三项都已有
      When 用户对读音执行「重新生成」
      Then 读音被模型结果替换
      And 释义与词性不变

    Scenario: 改过的词性被重新生成覆盖
      Given 用户已把词性改为 verb
      When 用户对词性执行「重新生成」
      Then 词性被模型结果替换
      And 不出现确认提示

  Rule: 补充或重新生成失败不影响已有内容，可重试
    Scenario: 服务未配置
      Given 模型服务未配置
      When 用户执行「补充缺失」
      Then 提示原因
      And 条目内容不变

    Scenario: 部分成功
      Given 该条目无读音、无词性
      When 「补充缺失」返回了读音但词性失败
      Then 读音已保存
      And 词性可重试

  Rule: 整句条目不标读音与词性
    Scenario: 整句只补释义
      Given 生词本已收录整句 "I will follow up with the team tomorrow."
      When 用户查看该条目
      Then 不显示读音与词性
      And 「补充缺失」只补释义

  Rule: 读音体系由设置中该语言的配置决定，随读音一起保存
    Scenario Outline: 默认体系
      Given 用户未修改读音体系设置
      And 生词本已收录 "<语言>" 表达 "<表达>"
      When 用户执行「补充缺失」
      Then 读音使用 "<体系>"

      Examples:
        | 语言 | 表达         | 体系 |
        | 英语 | bandwidth    | IPA  |
        | 日语 | お疲れ様です | 假名 |
        | 中文 | 收敛         | 拼音 |
        | 法语 | bonjour      | IPA  |

    Scenario: 改设置不回填已有读音
      Given 生词本已有一条日语表达，读音为假名
      When 用户把日语的读音体系改为罗马字
      Then 该条目读音仍是假名
      And 之后新补充的日语读音使用罗马字
