Feature: 操作历史
  用户可以找回翻译与润色的原文和结果。

  Rule: 成功生成的结果自动保存
    Scenario Outline: 保存结果
      Given 用户执行 "<动作>"
      When 结果成功生成
      Then 历史保存原文、结果、语言、时间及类型 "<类型>"
      And 重启后仍可查看
      Examples:
        | 动作 | 类型 |
        | 翻译 | 翻译 |
        | 润色 | 润色 |
        | 翻译并替换 | 翻译 |

    Scenario: 译文成功但替换失败
      Given 翻译并替换已生成译文
      When 因原选区失效而未能写回
      Then 翻译历史仍保留原文和译文

    Scenario: 请求失败
      When 翻译或润色请求失败或取消
      Then 不保存为成功历史

  Rule: 历史可查找并复用
    Scenario: 组合筛选与搜索
      Given 用户有多条翻译与润色记录
      When 用户按润色筛选并搜索原文中的词语
      Then 只显示匹配的润色记录
      And 可打开详情并复制结果或手动收藏

  Rule: 历史由用户清理且不自动过期
    Scenario: 删除单条历史
      Given 用户有两条历史记录
      When 用户删除其中一条并重启
      Then 只保留另一条记录

    Scenario: 取消清空
      Given 用户有历史记录
      When 用户发起清空但取消确认
      Then 历史记录保持不变

    Scenario: 确认清空
      Given 用户有历史记录
      When 用户确认清空全部历史
      Then 历史列表为空

    Scenario: 长期保留
      Given 用户未删除已有历史
      When 用户在之后重新打开历史
      Then 不因记录年龄自动删除记录
