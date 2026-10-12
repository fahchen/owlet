Feature: 按源语言决定翻译目标
  翻译的目标语言由本地检测的源语言和用户配置的映射决定，未命中时用兜底目标。

  Rule: 映射表决定翻译目标
    Scenario: 表为空时使用兜底目标
      Given 用户尚未添加任何映射
      And 兜底目标为简体中文
      And 原文为 "Could you send me the report?"
      When 用户执行翻译
      Then 目标语言为简体中文

    Scenario: 命中映射
      Given 用户添加映射 "英语 → 日语"
      When 用户翻译英语文本
      Then 目标语言为日语
      And 结果使用日语

    Scenario: 源语言未识别时使用兜底目标
      Given 原文过短或无法可靠检测语言
      When 用户执行翻译
      Then 使用兜底目标语言

    Scenario: 源语言未列出时使用兜底目标
      Given 原文为法语
      And 映射表中没有法语
      When 用户执行翻译
      Then 使用兜底目标语言

    Scenario: 一个源语言只对应一个目标
      Given 用户已添加映射 "英语 → 日语"
      When 用户为英语添加映射 "英语 → 中文"
      Then 英语只保留 "中文" 一个目标
      And 不再存在重复的英语行

  Rule: 源语言在发请求前本地检测
    Scenario: 不因检测结果改变返回校验
      Given 本地检测判定原文为英语
      When 模型返回的源语言与本地判定不同
      Then 只要返回的目标语言与请求一致，结果仍然有效

    Scenario: 混写取主导语言
      Given 原文以中文为主并夹有英文术语
      When 用户执行翻译
      Then 源语言按中文处理
      And 按中文对应的映射选择目标

  Rule: 翻译并替换复用同一映射
    Scenario: 与普通翻译解析一致
      Given 映射将英语指向日语
      When 用户对英语选区调用翻译并替换
      Then 目标语言同样为日语
      And 写回内容为日语译文

  Rule: 润色不受映射影响并保持语言混写
    Scenario: 润色不显示目标语言控件
      Given 用户在文本处理页切换为润色
      Then 不显示目标语言控件

    Scenario: 润色保持原文语言
      Given 映射将英语指向日语
      And 原文为英语
      When 用户执行润色
      Then 结果仍为英语
      And 不因映射而改变语言

    Scenario: 混写不被归一
      Given 原文为中文并夹有英文术语
      When 用户执行润色
      Then 英文术语仍为英文
      And 不翻译或转写任何片段

  Rule: 工具栏自动与手动覆盖
    Scenario: 默认为自动
      Given 用户未手动选择目标语言
      When 用户翻译英语文本
      Then 按映射或兜底决定目标
      And 控件显示自动与解析出的目标语言

    Scenario: 手动选择持久覆盖
      Given 用户在文本处理页显式选择日语
      When 用户翻译英语文本
      Then 目标语言为日语
      When 用户重启应用并再次翻译英语文本
      Then 目标语言仍为日语

    Scenario: 切回自动恢复映射
      Given 用户此前显式选择了日语
      When 用户把目标语言切回自动
      Then 后续翻译重新按映射或兜底决定目标

  Rule: 母语只影响学习内容
    Scenario: 位置与默认值
      Given 用户打开设置的「语言」页
      Then 映射表旁有「母语」多选，默认未指定
      And 候选语言就是应用在用的那些语言，不列系统全部语言

    Scenario: 可以选多个母语
      Given 用户同时掌握简体中文与英语
      When 用户把两者都设为母语
      Then 两种语言的表达都不进学习内容
      And 其它语言的表达仍可被推荐

    Scenario: 不参与释义语言的计算
      Given 用户把母语设为简体中文
      And 映射将英语指向简体中文
      When 用户把英语翻译成简体中文并收藏一条表达
      Then 释义语言仍是本次目标语言，即简体中文
      And 母语设置不改变释义语言

    Scenario: 持久化
      Given 用户把母语设为日语
      When 用户重启应用
      Then 母语仍为日语

    Scenario: 语言选择里移除了某个母语
      Given 用户把英语设为母语
      When 用户从「语言」页移除英语
      Then 母语列表里也不再有英语

  Rule: 设置持久化与迁移
    Scenario: 映射与兜底目标持久化
      Given 用户添加映射并修改兜底目标
      When 用户重启应用
      Then 映射与兜底目标保持不变

    Scenario: 沿用旧的目标语言设置
      Given 用户在此功能之前已把目标语言保存为日语
      When 用户升级后打开设置
      Then 兜底目标为日语
      And 映射表为空
