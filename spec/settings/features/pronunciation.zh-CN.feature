# English: pronunciation.feature · 简体中文: pronunciation.zh-CN.feature
Feature: 按语言配置读音体系
  设置「语言」分组里每种语言有一个读音体系，生词本补充读音与阅读查词都按它请求读音（BDR-0006）。

  Rule: 每种语言一个读音体系，默认值按语言决定
    Scenario Outline: 默认体系
      Given 用户未修改读音体系设置
      When 用户打开设置的「语言」分组
      Then "<语言>" 的读音体系为 "<体系>"
      Examples:
        | 语言 | 体系 |
        | 英语 | IPA |
        | 日语 | 假名 |
        | 简体中文 | 拼音 |
        | 法语 | IPA |

    Scenario Outline: 只有存在分歧的语言可选
      When 用户查看 "<语言>" 的读音体系
      Then 可选项为 "<可选>"
      Examples:
        | 语言 | 可选 |
        | 日语 | 假名、罗马字 |
        | 简体中文 | 拼音、注音 |
        | 繁體中文 | 拼音、注音 |
        | 英语 | IPA |

  Rule: 改动即时生效，只影响之后的请求
    Scenario: 改日语读音体系后查词
      Given 用户把日语的读音体系改为罗马字
      When 用户在日语正文中查询 "推敲"
      Then 查词请求使用罗马字
      And 之前以假名查到的结果不按新设置复用
