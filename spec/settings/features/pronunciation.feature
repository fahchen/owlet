# English: pronunciation.feature · 简体中文: pronunciation.zh-CN.feature
Feature: Configure the reading notation per language
  Each language in the settings "Languages" group has a reading notation; vocabulary reading fill-in and reading lookup both request readings in it (BDR-0006).

  Rule: One reading notation per language, with a per-language default
    Scenario Outline: Default notation
      Given the user has not changed the reading notation settings
      When the user opens the "Languages" group in settings
      Then the reading notation for "<language>" is "<notation>"
      Examples:
        | language | notation |
        | English | IPA |
        | Japanese | Kana |
        | 简体中文 | Pinyin |
        | French | IPA |

    Scenario Outline: Only languages with competing notations offer a choice
      When the user views the reading notation for "<language>"
      Then the options are "<options>"
      Examples:
        | language | options |
        | Japanese | Kana, Romaji |
        | 简体中文 | Pinyin, Zhuyin |
        | 繁體中文 | Pinyin, Zhuyin |
        | English | IPA |

  Rule: Changes take effect immediately and only affect later requests
    Scenario: Look up a word after changing the Japanese notation
      Given the user changes the Japanese reading notation to Romaji
      When the user looks up "推敲" in Japanese text
      Then the lookup request uses Romaji
      And earlier results looked up with Kana are not reused under the new setting
