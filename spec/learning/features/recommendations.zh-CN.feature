# English: recommendations.feature · 简体中文: recommendations.zh-CN.feature
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

  Rule: 学习内容不含母语
    Scenario: 读日语时排除母语
      Given 用户把母语设为简体中文
      And 原文为日语、目标为简体中文
      When 翻译成功并请求学习内容
      Then 推荐条目不含简体中文表达
      And 日语表达仍可被推荐

    Scenario: 润色母语文本时不产生学习内容
      Given 用户把母语设为简体中文
      And 原文为简体中文
      When 润色成功
      Then 不发起学习请求，也没有学习入口
      And 主要结果仍可使用

    Scenario: 润色非母语文本照常推荐
      Given 用户把母语设为简体中文
      And 原文为英语
      When 润色成功并请求学习内容
      Then 推荐英语表达

    Scenario: 未设置母语时行为与之前一致
      Given 用户未设置母语
      When 翻译或润色成功并请求学习内容
      Then 原文与译文两侧的表达都可被推荐

    Scenario: 模型不听话时本地兜底
      Given 用户把母语设为简体中文
      When 模型返回了简体中文的推荐条目
      Then 该条目在展示前被丢弃

  Rule: 推荐服务于理解和表达且不强凑数量
    Scenario: 润色中的风格建议
      Given 润色学习开关开启
      And 原文语法正确但有可改善的风格表达
      When 用户查看学习内容
      Then 说明修改前后差异及理由
      And 不将纯风格偏好标为语法错误

    Scenario: 没有值得推荐的内容
      Given 学习开关开启
      When 本次结果没有值得推荐的词汇、搭配或句式
      Then 可以没有推荐条目
      And 主要结果仍可使用

    Scenario: 推荐词在句中用了活用形
      Given 一句日语原文里的表达是 "跳ね上がっている"
      When 模型推荐这一表达并给出字典形 "跳ね上がる"
      Then 该推荐可用，不因为词形与原形不同被判为格式错误
      And 条目以 "跳ね上がっている" 收藏，并把 "跳ね上がる" 记为原形
      And 原形与词形相同时不重复记原形

  Rule: 学习内容不阻塞主要动作且不自动收藏
    Scenario: 浮窗逐条收藏
      Given 浮窗已展示学习推荐
      When 用户点击某条推荐
      Then 仅将该条推荐及其释义加入生词本
      And 保存成功后显示选中状态
      And 保存失败时保留重试入口

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

    Scenario: 完整窗口学习与浮窗一致
      Given 完整窗口主结果已成功生成
      When 用户点击右下角的学习按钮
      Then 学习列表与浮窗相同，点击词条即时切换收藏
      And 学习请求沿用本次翻译或润色的结果与语言信息
      And 不另设释义语言选择器

  Rule: 浮窗学习词条即时切换收藏
    Scenario: 取消词条选中
      Given 浮窗词条已经存在于生词本并显示选中
      When 用户再次点击词条
      Then 该词条立即从生词本移除并显示未选中
      And 不需要确认或额外提交
      And 删除失败时保留选中状态并提示失败

    Scenario: 再次打开学习界面
      Given 词条已经加入生词本
      When 用户再次打开包含该词条的学习界面
      Then 该词条仍显示选中

    Scenario: 结果切换为学习布局
      Given 浮窗正在显示翻译结果
      When 用户展开学习
      Then 结果平滑重排为左右双栏并带弹簧过渡
      And 系统启用减少动态效果时直接切换
