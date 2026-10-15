# English: editing.feature · 简体中文: editing.zh-CN.feature
Feature: 生词本编辑
  用户可以修改已收藏条目的释义、表达、语言、笔记、标签与重点标记，把生词本维护成自己的学习资料。

  Background:
    Given 生词本已收录英语表达 "follow up"
    And 该条目带有模型生成的释义

  Rule: 释义可由用户编辑，且重新生成时无条件覆盖
    Scenario: 改写释义
      When 用户把释义改成自己的措辞并重启应用
      Then 条目显示改后的释义

    Scenario: 改过的释义被重新生成覆盖
      Given 用户已改写该条目的释义
      When 用户触发重新生成释义
      Then 模型返回的释义替换用户改写的内容
      And 不出现确认提示

  Rule: 笔记与释义分开保存，自动流程不触碰笔记
    Scenario: 重新生成释义不影响笔记
      Given 用户已为该条目写下笔记
      When 用户触发重新生成释义
      Then 释义更新
      And 笔记保持原样

    Scenario: 收藏时补充释义不写入笔记
      Given 用户手选内容收藏且没有语境释义
      When 收藏后自动补充释义
      Then 笔记仍为空

  Rule: 表达与语言可改，改后与同语言已有条目重合时拒绝
    Scenario: 修正表达的多余字符
      When 用户把表达从 "follow up." 改为 "follow up"
      Then 条目的表达更新
      And 条目的语境与释义不变

    Scenario: 纠正误判的语言
      Given 生词本已收录被标为中文的表达 "手紙"
      When 用户把该条目的语言改为日语
      Then 仍是同一条目，语境不变

    Scenario: 改名撞到同语言已有条目
      Given 生词本已收录英语表达 "bandwidth" 与 "bandwith"
      When 用户把 "bandwith" 改为 "bandwidth"
      Then 修改被拒绝并说明原因
      And 两条目都保持原值

  Rule: 编辑即时生效，无需确认保存
    Scenario: 切换条目后笔记仍在
      When 用户在笔记中输入内容后选择另一条目再回来
      Then 笔记显示刚才输入的内容
      And 没有保存按钮，也没有「未保存更改」的状态

  Rule: 标签自由输入，输入时可见已用过的标签
    Scenario: 复用已有标签
      Given 另一条目已带有标签 "工作"
      When 用户为 "follow up" 添加标签并开始输入
      Then "工作" 出现在候选中

    Scenario: 新标签
      When 用户输入从未用过的标签 "面试" 并确认
      Then 该条目带有标签 "面试"

    Scenario: 标签随最后一个条目消失
      Given 只有一条目带有标签 "面试"
      When 用户删除该条目
      Then "面试" 不再出现在任何候选或筛选中

  Rule: 条目可标记为重点
    Scenario: 重点标记持久
      When 用户将 "follow up" 标记为重点并重启应用
      Then 该条目仍显示为重点
