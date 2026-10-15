# English: shortcuts.feature · 简体中文: shortcuts.zh-CN.feature
Feature: 快捷入口与浮窗
  用户可以通过键盘从其他应用处理文本。

  Rule: 四种动作分别配置快捷键
    Scenario: 配置不同入口
      When 用户分别设置翻译、润色、翻译并替换、润色并替换的快捷键
      Then 每个快捷键调用对应动作
      And 润色并替换在结果生成后直接写回原选区

  Rule: 按钮都有固定快捷键与悬停提示
    Scenario: 悬停查看动作与按键
      When 用户把指针停在浮窗或主窗口的图标按钮上
      Then 显示动作名称与对应按键
      And 不激活应用的浮窗里同样显示
      And 设置窗口的控件不显示提示

    Scenario: 复制尊重选区
      Given 浮窗或主窗口已有结果
      When 用户按下 ⌘C
      Then 选中文字时复制所选内容
      And 未选中文字时复制当前结果

    Scenario: 快捷键页列出固定按键
      When 用户打开快捷键设置
      Then 固定按键按浮窗、翻译与润色、生词本与历史记录分组列出
      And 固定按键不能更改

    Scenario: 快捷键注册失败
      Given 所选快捷键无法注册
      When 用户保存快捷键
      Then 应用明确提示注册失败
      And 不将其显示为可用快捷键

  Rule: 浮窗支持键盘操作及问题恢复
    Scenario: 键盘关闭浮窗
      Given 文本处理浮窗已打开
      And 当前没有打开查词卡
      When 用户按下 Esc
      Then 浮窗关闭

    Scenario: 失去焦点不关闭浮窗
      Given 文本处理浮窗已打开
      When 浮窗失去键盘焦点
      Then 浮窗保持打开

    Scenario: 点击浮窗外部关闭
      Given 文本处理浮窗已打开
      When 用户点击浮窗以外的区域
      Then 浮窗关闭

    Scenario: 点击浮窗内部不关闭
      Given 文本处理浮窗已打开
      When 用户点击浮窗内部
      Then 浮窗保持打开

    Scenario: 未授权读取外部选区
      Given 应用没有读取外部选区所需权限
      And 浮动工具栏尚未展开
      When 用户调用普通翻译快捷键
      Then 显示紧凑的权限提示和行内权限设置入口
      And 不展开完整浮动工具栏

  Rule: 即时操作与内容管理分开呈现
    Scenario Outline: 所有快捷键均唤起浮动工具栏
      Given 用户正在其他应用中阅读文本
      And 已取得选中文字且所需权限和服务配置齐备
      When 用户调用 "<操作>" 快捷键
      Then 显示无侧栏的紧凑浮动工具栏
      And 不打开完整管理窗口
      And 可以按需展开结果与学习内容
      Examples:
        | 操作 |
        | 翻译 |
        | 润色 |
        | 翻译并替换 |
        | 润色并替换 |

    Scenario: 从工具栏进入设置
      Given 浮动工具栏已经打开
      When 用户打开设置
      Then 在完整管理窗口中显示设置
      And 浮动工具栏仍由全局快捷键唤起

    Scenario: 查看积累的内容
      Given 用户在浮动工具栏中
      When 用户打开生词本或历史
      Then 在完整管理窗口中查看对应内容
      And 首版不展示复习流程

  Rule: 首次快捷操作处理中保持紧凑并在完成后展示结果
    Scenario Outline: 处理所选文本
      Given 用户选中了文本
      And 浮动工具栏尚未展开
      When 用户调用 "<操作>" 快捷键
      Then 显示包含处理指示、文本摘要和加载状态的紧凑浮条
      And 可按 Esc 关闭并取消操作
      And 不显示完整结果占位区
      When 处理完成
      Then 平滑展开结果视图
      Examples:
        | 操作 |
        | 翻译 |
        | 润色 |
        | 翻译并替换 |

    Scenario: 减少动态效果
      Given 用户开启了减少动态效果
      When 文本处理完成
      Then 直接显示结果视图而不播放展开动画

  Rule: 快捷键可以重新录制
    Scenario: 录制新组合
      Given 用户打开快捷键设置
      When 用户点击翻译快捷键并按下新组合键
      And 保存设置
      Then 后续按新组合进入翻译浮层
      And 原组合不再触发翻译
      And 重启后保留新组合

    Scenario: 取消录制
      Given 用户正在录制快捷键
      When 用户按 Esc
      Then 取消本次录制并保留原组合
      And 不关闭设置窗口

    Scenario: 与另一动作冲突
      Given 润色已使用某个快捷键
      When 用户为翻译录制相同快捷键
      Then 提示冲突并继续等待输入
      And 已生效的两个快捷键都不变

    Scenario: 首次使用无默认快捷键
      Given 用户尚未录制翻译快捷键
      When 用户按下任意组合
      Then 不触发翻译
      And 快捷键页显示“录制”

  Rule: 完整应用统一处理翻译和润色
    Scenario: 在应用内切换处理方式
      Given 用户打开完整应用的文本处理页面
      When 用户输入或粘贴文本
      Then 可在同一页面选择翻译或润色并执行
      And 无需切换两个 tab 或侧栏页面
      And 结果可以复制

    Scenario: 侧栏不提供选区替换动作
      When 用户查看完整窗口左侧导航
      Then 只存在一个文本处理入口
      And 不存在翻译并替换导航项
      And 独立翻译并替换快捷键仍可唤起浮层

    Scenario: 工具栏切换处理方式
      Given 用户打开完整应用的翻译与润色页面
      Then 工具栏左侧是仅图标的翻译／润色分段控件
      And 内容是一张四周留有边距的玻璃卡片
      And 当前 pane 里原文与结果两侧同时可见，各是一个带背景的分组
      And 目标语言显示在译文一侧的分组标题上
      And 复制结果与提交浮在内容右下角，处理中换成取消
      When 用户切换到另一个 tab
      Then 用同一段原文显示该操作的结果，不重复请求

    Scenario: 润色不选择目标语言
      Given 用户在完整应用的文本处理页面
      When 用户切换为润色
      Then 润色 pane 不显示目标语言选择
      When 用户切回翻译 pane
      Then 恢复显示之前选择的目标语言
