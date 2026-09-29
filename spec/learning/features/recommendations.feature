Feature: 可选学习内容
  用户决定是否从翻译与润色中获取学习推荐。

  Rule: 学习推荐默认关闭且分别控制
    Scenario: 首次使用
      Given 用户未修改学习设置
      When 用户分别执行翻译与润色
      Then 两种操作都不自动请求或展示学习推荐

    Scenario: 仅开启翻译学习
      Given 用户开启翻译学习且关闭润色学习
      When 用户分别完成翻译与润色
      Then 翻译结果成功后自动发起独立的学习请求
      And 润色不生成学习推荐

    Scenario: 单次展开
      Given 翻译学习开关关闭
      When 用户展开结果下方的“学习”区
      Then 才发起本次独立的学习内容请求
      And 长期设置仍为关闭
      And 下一次翻译不自动生成学习内容

    Scenario: 再次展开已生成的学习表达
      Given 本次学习表达已成功生成
      When 用户收起后再次展开
      Then 展示已有条目而不重复请求

  Rule: 推荐服务于理解和表达且不强凑数量
    Scenario: 润色中的风格建议
      Given 润色学习开关开启
      And 原文语法正确但有可改善的风格表达
      When 用户查看学习内容
      Then 用中文说明修改前后差异及理由
      And 不将纯风格偏好标为语法错误

    Scenario: 没有值得推荐的内容
      Given 学习开关开启
      When 本次结果没有值得推荐的词汇、搭配或句式
      Then 可以没有推荐条目
      And 主要结果仍可使用

  Rule: 学习内容不阻塞主要动作且不自动收藏
    Scenario: 直接替换不等待学习内容
      Given 用户开启翻译学习并执行翻译并替换
      When 译文已生成且原选区有效
      And 学习内容仍在生成
      Then 译文直接写回
      And 不自动添加收藏

    Scenario: 学习生成失败
      Given 用户已有翻译结果
      When 学习内容生成失败
      Then 翻译结果仍可复制
      And 用户可重试学习内容生成

    Scenario: 勾选推荐入库
      Given 展示了三个学习推荐
      When 用户只勾选其中两个并点击“加入生词本”
      Then 生词本仅新增被选中的内容

    Scenario: 学习控件使用原生组件
      Given 主结果已成功生成
      When 用户展开学习区
      Then 使用原生 DisclosureGroup 与复选框展示条目
      And 学习请求沿用本次翻译或润色的结果与语言信息
      And 不另设释义语言选择器
