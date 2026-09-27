Feature: 快捷入口与浮窗
  用户可以通过键盘从其他应用处理文本。

  Rule: 三种动作分别配置快捷键
    Scenario: 配置不同入口
      When 用户分别设置翻译、润色、翻译并替换的快捷键
      Then 每个快捷键调用对应动作

    Scenario: 快捷键注册失败
      Given 所选快捷键无法注册
      When 用户保存快捷键
      Then 应用明确提示注册失败
      And 不将其显示为可用快捷键

  Rule: 浮窗支持键盘操作及问题恢复
    Scenario: 键盘关闭浮窗
      Given 文本处理浮窗已打开
      When 用户按下 Esc
      Then 浮窗关闭

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
      And 快捷键页显示“未设置”

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

    Scenario: 翻译控件排列
      Given 用户打开完整应用的文本处理页面
      When 用户选择翻译
      Then 右上角从左到右显示目标语言和翻译或润色选择
      And 底部不重复显示这两个选择

    Scenario: 润色不选择目标语言
      Given 用户在完整应用的文本处理页面
      When 用户切换为润色
      Then 右上角保留处理方式选择但不显示目标语言选择
      When 用户切回翻译
      Then 恢复显示之前选择的目标语言
