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
      When 因未能写回原应用而替换失败
      Then 翻译历史仍保留原文和译文

    Scenario: 请求失败
      When 翻译或润色请求失败或取消
      Then 不保存为成功历史

  Rule: 历史可查找并复用
    Scenario: 组合筛选与搜索
      Given 用户有多条翻译与润色记录
      When 用户按润色筛选并搜索原文中的词语
      Then 只显示匹配的润色记录
      And 可打开详情并发起学习请求

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

  Rule: 历史详情使用学习流程加入生词本
    Scenario: 学习已有历史
      Given 用户选中一条历史记录
      When 用户点击详情右下角的学习按钮
      Then 原文收起，结果留在上方，学习列表在下方展开并按需请求
      And 点击词条即时切换收藏
      And 不直接保存整条原文作为生词

    Scenario: 分栏与工具栏
      Given 用户打开历史记录
      Then 列表和详情分别滚动，工具栏半透明
      And 筛选在工具栏左侧，搜索位于最右侧，删除在右侧
      And 详情右下角提供学习与复制结果按钮
      And 不提供编辑或导出按钮

  Scenario: 数量随列表滚动
    When 查看历史列表
    Then 不显示重复的历史记录窗口标题
    And 记录数量作为列表首行的灰色非选择标签随内容滚动

  Scenario: 浏览相邻条目与空状态
    When 查看列表
    Then 数量居中显示在第一项上方的滚动留白，不增加顶部安全留白
    And 工具栏上一条和下一条按当前筛选顺序切换，边界禁用
    And 空库可前往翻译，无匹配结果可清除筛选

  Scenario: 多选删除与独立导航组
    When 使用 Command 或 Shift 在列表中选择多条记录
    Then 删除前确认所选数量，只删除所选记录
    And 多选时学习和上一条下一条不可用
    And 上一条下一条在右侧独立工具栏组中

  Scenario: 一级筛选
    When 打开筛选菜单
    Then 直接显示全部类型、翻译与润色，无二级菜单

  Scenario: Notes 式工具栏搜索
    When 查看历史记录
    Then 系统搜索位于工具栏最右侧，与导航及内容动作分组分离
