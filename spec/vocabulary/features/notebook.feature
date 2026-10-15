Feature: 生词本管理
  用户可以查找、查看和删除生词本内容。

  Rule: 生词本可持久查看
    Scenario: 重启后查看
      Given 用户已收藏一个日语短语
      When 用户重启应用并打开生词本
      Then 该短语及语境仍可查看

    Scenario: 搜索与语言筛选
      Given 生词本包含英语和日语条目
      When 用户选择日语筛选并输入搜索词
      Then 仅显示符合搜索内容的日语条目

    Scenario: 语言、标签与重点筛选叠加
      Given 生词本包含多种语言、多个标签与部分重点条目
      When 用户选择英语、标签 "工作" 并勾选仅重点
      Then 只显示同时满足三者的条目

    Scenario: 多个标签取并集
      Given 生词本中有条目分别带标签 "工作" 与 "邮件"
      When 用户同时选择标签 "工作" 与 "邮件"
      Then 显示带任一标签的条目

    Scenario: 按来源 App 筛选
      Given 生词本中有在 Slack 与邮件应用遇到的英语条目
      When 用户选择英语并选择来源 App 为 Slack
      Then 只显示在 Slack 遇到的英语条目

    Scenario: 删除条目
      Given 用户已收藏一个条目
      When 用户删除该条目并重启应用
      Then 生词本不再包含该条目

  Rule: 收藏不随历史删除
    Scenario: 清空来源历史
      Given 用户从历史记录收藏了一个表达
      When 用户清空全部历史
      Then 收藏及其原句语境仍可查看
      And 语境仍显示来源入口与来源 App
      But 不再能跳转到该历史记录

  Rule: 使用原生分栏管理生词本
    Scenario: 列表与详情独立滚动
      Given 生词本包含足够多的条目和长语境
      When 用户选中条目并滚动详情
      Then 列表保持自身滚动位置
      And 工具栏中搜索与筛选为一组，删除为右侧操作
      And 不提供导出或复制按钮

  Scenario: 数量随生词列表滚动
    When 查看生词本
    Then 不显示重复的生词本窗口标题
    And 表达数量作为列表首行的灰色非选择标签随内容滚动

  Scenario: 浏览相邻条目与空状态
    When 查看列表
    Then 数量居中显示在第一项上方的滚动留白，不增加顶部安全留白
    And 工具栏上一条和下一条按当前筛选顺序切换，边界禁用
    And 空库可前往翻译，无匹配结果可清除筛选

  Scenario: 多选删除与独立导航组
    When 使用 Command 或 Shift 在列表中选择多个表达
    Then 删除前确认所选数量，只删除所选表达与其语境
    And 多选时上一条下一条不可用
    And 上一条下一条在右侧独立工具栏组中

  Scenario: 一级语言筛选
    When 打开筛选菜单
    Then 直接显示全部语言及各语言，无二级菜单

  Scenario: Notes 式工具栏搜索
    When 查看生词本
    Then 系统搜索位于工具栏最右侧，与导航及内容动作分组分离
