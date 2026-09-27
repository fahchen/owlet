Feature: 生词本管理
  用户可以查找、维护并导出自己的收藏。

  Rule: 收藏可持久查看和修改
    Scenario: 重启后查看与编辑
      Given 用户已收藏一个日语短语
      When 用户重启应用并打开生词本
      Then 该短语及语境仍可查看
      When 用户修改中文释义并保存
      Then 再次打开条目时显示修改后的释义

    Scenario: 搜索与语言筛选
      Given 生词本包含英语和日语条目
      When 用户选择日语筛选并输入搜索词
      Then 仅显示符合搜索内容的日语条目

    Scenario: 删除条目
      Given 用户已收藏一个条目
      When 用户删除该条目并重启应用
      Then 生词本不再包含该条目

  Rule: 导出保留收藏内容
    Scenario: 导出多语种收藏
      Given 收藏包含中英日表达、多条语境及润色对照
      When 用户导出生词本
      Then 导出内容包含这些表达、语言、释义、语境及对照
      And 中文和日文内容完整可读

    Scenario: 导出失败
      Given 用户已有收藏
      When 导出失败或用户取消导出
      Then 本地收藏不受影响

  Rule: 收藏不随历史删除
    Scenario: 清空来源历史
      Given 用户从历史记录收藏了一个表达
      When 用户清空全部历史
      Then 收藏及其原句语境仍可查看
