[English](README.md) · [简体中文](README.zh-CN.md)

# Owlet

Owlet 是 macOS 26 及以上的菜单栏应用：翻译与润色所选文字，把收藏的词句存进个人生词本，并保留处理历史。模型服务支持 OpenAI Chat Completions、OpenAI Responses、Anthropic Messages 与 Gemini 四种协议（内置常见厂商预设），也可用本地 agent CLI（Claude Code 或 Codex CLI）。

- 官网：https://owlet.fahchen.dev
- 下载：[Releases](https://github.com/fahchen/owlet/releases)
- 更新日志：[CHANGELOG.md](CHANGELOG.md)
- 尚未完成的事项：[路线图](docs/roadmap.zh-CN.md)

## 文档

- [产品定义](spec/product.md)
- [BDD 行为规格](spec/README.md)
- [视觉与交互规则](spec/DESIGN.md)
- [Liquid Glass 组件对照](docs/liquid-glass-components.zh-CN.md)
- [Panel 调试、测试与截图](docs/panel-debugging-and-testing.zh-CN.md)
- [选中文本获取](docs/selected-text-capture.zh-CN.md)

## 生产构建

由 [scripts/prod-build.sh](scripts/prod-build.sh) 做 Release 构建，校验后打包到 `dist/`（已在 `.gitignore` 里）：

```sh
mise run prod                       # 同时产出 universal 与 arm64 两个 zip
mise run prod -- --arch arm64       # 只要本机架构
mise run prod -- --team Z98NKJSF69  # 显式指定 Team 签名
```

脚本依次构建、校验（bundle id、最低系统版本、图标、签名可验证、不带 `get-task-allow`），再用 `ditto` 打包并打印 SHA-256。产物名为 `Owlet-<版本>-<架构>.zip`。版本取自 `project.yml` 的 `MARKETING_VERSION`（当前 `0.8.0`）；全部选项见 `scripts/prod-build.sh --help`。

产物都未公证，另一台 Mac 首次打开需右键「打开」。ad-hoc 签名的包**每次重编都要重新授权辅助功能**，有证书则授权长期有效。用 `scp` 或 `rsync` 传，别用 AirDrop，以免带上 quarantine 标记。

## 开发

```sh
mise run setup    # 安装工具及 pre-commit hook
mise run dev      # 构建并重启本机 Owlet
mise run check    # lint + 生成工程 + 测试
mise run format   # 格式化 Swift
mise tasks        # 全部任务
```

仓库约定见 [AGENTS.zh-CN.md](AGENTS.zh-CN.md)。
