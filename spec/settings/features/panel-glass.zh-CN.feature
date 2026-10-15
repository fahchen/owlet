# English: panel-glass.feature · 简体中文: panel-glass.zh-CN.feature
Feature: 浮窗玻璃效果
  Scenario: 默认强调可读性
    Given 用户尚未选择浮窗玻璃效果
    Then 通用设置的玻璃效果为“更高对比度”

  Scenario: 切换效果并保留选择
    Given 用户打开通用设置
    When 用户将玻璃效果设为“更透明”
    Then 当前浮窗的玻璃表面立即变为更透明的效果
    And 翻译中、错误、结果与学习状态使用同一选择
    And 重启后仍保留该选择
    And 主窗口的外观不变

  Scenario: 玻璃强度由系统设置决定
    Given 用户打开通用设置
    Then “浮窗”分组说明液态玻璃及其强度在“系统设置 › 外观”中调整
    And 应用自己的选择只区分“更透明”与“更高对比度”两种玻璃变体
    And 应用不提供任何暗示可自行调整玻璃强度的控件
    And 提供打开“系统设置 › 外观”的入口
