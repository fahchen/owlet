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

  Rule: 浮窗支持键盘操作及手动输入
    Scenario: 键盘关闭浮窗
      Given 文本处理浮窗已打开
      When 用户按下 Esc
      Then 浮窗关闭

    Scenario: 未授权读取外部选区
      Given 应用没有读取外部选区所需权限
      When 用户调用普通翻译快捷键
      Then 应用说明权限状态
      And 用户仍可手动输入或粘贴文本

  Rule: 即时操作与内容管理分开呈现
    Scenario Outline: 所有快捷键均唤起浮动工具栏
      Given 用户正在其他应用中阅读文本
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
      And 可以返回浮动工具栏

    Scenario: 查看积累的内容
      Given 用户在浮动工具栏中
      When 用户打开生词本或历史
      Then 在完整管理窗口中查看对应内容
      And 首版不展示复习流程

  Rule: 处理中保持紧凑并在完成后展示结果
    Scenario Outline: 处理所选文本
      Given 用户选中了文本
      When 用户调用 "<操作>" 快捷键
      Then 显示包含小指示器、文本摘要、加载状态和取消入口的紧凑浮条
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

    Scenario: 恢复默认
      Given 翻译使用自定义快捷键且默认组合未被其他动作占用
      When 用户恢复默认并保存
      Then 翻译使用默认快捷键
