Feature: 把本机的 agent CLI 当作模型服务
  已在本机登录的 Claude Code、Codex CLI 或 pi 可以直接当模型服务用：应用只向它要一次回答，
  不把它当成会读写代码的编码 agent（BDR-0013）。

  Rule: 本地 agent 与 HTTP 服务并列可选
    Scenario: 选择本地 agent
      Given 用户在本机已登录某个 agent CLI
      When 用户在设置里把它选为服务商
      Then 设置页不再要求 Base URL 与 API Key
      And 翻译、润色、查词与学习都用它处理

    Scenario: 服务商列表按本机情况给出
      Given 用户在服务商列表里看到远程服务与本地 agent 两组
      When 本机没有安装某个 agent CLI
      Then 该 agent 不出现在列表里
      And 用户手动指定过路径的 agent 仍然出现
      And 当前选中的 agent 即使已不可执行也保留在列表里

    Scenario: 切到本地 agent 时主动扫描
      Given 本机已安装某个 agent CLI 且用户没有为它指定过路径
      When 用户把它选为服务商
      Then 应用自动找到它、填好可执行文件并显示版本
      And 用户不需要先点「检测」

    Scenario: 路径不可执行时视为配置缺失
      Given 用户选了本地 agent 但没有可执行文件路径，或该路径已不可执行
      When 用户发起翻译
      Then 提示用户补齐配置
      And 不把请求发到任何默认服务

    Scenario: 路径由探测或手选得到
      When 用户点「检测」
      Then 应用在登录 shell 的 PATH 里查找该 agent 并显示探测到的版本
      And 探测失败时就地说明原因，不改动已保存的路径
      And 用户手选的路径不被扫描结果覆盖，除非它已不可执行

    Scenario: 切换服务商时不留上一个服务的模型名
      Given 用户为 HTTP 服务填写了模型名
      When 用户把服务商改为本地 agent
      Then 模型名留空，改用该 agent 自己的默认模型

  Rule: 能列模型的 agent 把模型名做成列表
    Scenario: 从 agent 自己的清单里选模型
      Given 用户在设置里选了 Codex CLI 或 pi
      When 应用读取该 agent 的模型清单
      Then 模型名以下拉列表给出，第一项是该 agent 自己的默认模型
      And 清单里标记为不公开的模型不出现

    Scenario: 不列举模型的 agent 保持自由填写
      Given 用户在设置里选了 Claude Code
      Then 模型名是自由填写的文本框
      And 留空表示使用它自己的默认模型

    Scenario: 清单读取失败
      When 读取模型清单失败
      Then 在模型名行下就地提示原因并提供重试
      And 已保存的模型名不变

  Rule: 只借用模型，不用它的工具与上下文
    Scenario: 三个 agent 都关掉工具与上下文
      Given 用户在设置里选了任一本地 agent
      When 应用发起一次请求
      Then Claude Code 以禁用全部工具与全部自定义的方式运行
      And pi 以禁用工具、扩展、MCP、技能与上下文文件的方式运行
      And Codex 以只读沙箱运行、禁用 shell 工具，且不运行用户自己的 hooks
      And 三者的工作目录都是一次性的空目录

    Scenario: 不读取用户的会话与项目文件
      When 应用发起一次请求
      Then agent 不加载用户的项目配置与会话历史
      And 请求结束后临时目录被删除

  Rule: 返回仍走同一份契约
    Scenario: 提示词与原文的投递
      Given 一次翻译请求
      When 应用调用本地 agent
      Then 行为提示词与固定契约按该 agent 的通道交付
      And 用户原文不出现在命令行参数里

    Scenario: 回复按同一条路径校验
      Given 本地 agent 返回了内容
      When 应用解析该回复
      Then 结构、原文拼接与目标语言的校验与 HTTP 服务完全相同
      And 契约失败时同样只纠正一次

    Scenario: 结构化输出按 json_object 路线
      Given 所选 agent 不接受本应用的响应 Schema
      When 应用组装请求
      Then 形状写在提示词里并要求 JSON
      And 本地校验不因此放松

  Rule: 失败可诊断
    Scenario: agent 非零退出
      When agent 以非零状态退出
      Then 提示本地 agent 运行失败并带上它的错误输出
      And 不写回、不存成成功历史

    Scenario: 超时
      Given 一次请求超过了设定的超时上限
      Then 应用结束该进程并按连接类失败提示

    Scenario: 用户取消
      Given 一次本地 agent 请求正在进行
      When 用户取消
      Then 该进程被结束
      And 迟到的输出不改变界面，也不写回

    Scenario: 调试页
      Given 用户打开了调试开关
      When 一次本地 agent 请求结束
      Then 调试页记下实际执行的命令行与提示词，以及模型的原始返回
      And 记录里不含任何密钥

  Rule: 资源有界
    Scenario: 同时在跑的进程数有上限
      Given 多个请求同时发起
      Then 同时在跑的 agent 进程不超过设定上限，其余排队

    Scenario: 不留下会话文件
      When 应用调用本地 agent
      Then 各 agent 以不落盘会话的方式运行
