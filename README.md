# Owlet

macOS 26+ 翻译、润色与个人生词本。

## 产品与计划

- [产品定义](spec/product.md)
- [BDD 行为规格](spec/README.md)
- [视觉与交互规则](spec/DESIGN.md)
- [Liquid Glass 组件对照](docs/liquid-glass-components.md)
- [Panel 调试、测试与截图](docs/panel-debugging-and-testing.md)
- [未实现功能清单](docs/unimplemented-features.md)
- [阅读查词第一步](spec/vocabulary/features/word-lookup.feature)：五类区域均已实现（T48–T51），待最终验收，决策见 [BDR-0008](spec/vocabulary/decisions/BDR-0008-reading-word-lookup.md)。
- [实现计划](tasks/plan.md)
- [任务清单](tasks/todo.md)

## 设计图

浏览器单文件原型（`design/`）已删除，不再维护：设计以 `spec/DESIGN.md`、
[Liquid Glass 组件对照](docs/liquid-glass-components.md) 与应用本身为准，
行为规格见 `spec/`，实现进度见 [未实现功能清单](docs/unimplemented-features.md)。

## 生产构建

Release、通用二进制（arm64 + x86_64）、验证后打包到 `dist/`（已在 `.gitignore` 里）：

```sh
mise run prod                       # 现在：ad-hoc 签名
mise run prod -- --arch arm64       # 只要本机架构，快一些
mise run prod -- --team Z98NKJSF69  # 有证书后：Apple Development 签名
```

脚本是 [scripts/prod-build.sh](scripts/prod-build.sh)，做的事：构建 → 校验（bundle id、最低系统版本、图标、签名可验证、不带 `get-task-allow`）→ 用 `ditto` 打包并打印 SHA-256。

两种签名的差别只在权限与提示：ad-hoc 的包拷到另一台 Mac 需要右键打开一次，而且**每次重编都要重新授权辅助功能**；`--team` 指定证书后签名带上 Team ID，授权一次就长期有效，但因为没有公证，首次打开仍会提示一次。用 `scp` 或 `rsync` 传，别用 AirDrop——前者不写 quarantine 标记。

`project.yml` 没有设 `MARKETING_VERSION`，所以产物名字用提交号（`Owlet-<commit>-universal.zip`）；想要版本号就在 `project.yml` 里加上这个设置，脚本会自动改用它。

## 开发

原生应用已实现原型中已实现的部分：文本处理、快捷键、设置、浮动面板与菜单栏；提案画面与尚未实现的功能见 [未实现功能清单](docs/unimplemented-features.md)。

```sh
mise run setup    # 安装工具及 pre-commit hook
mise run check    # lint + 生成工程 + 测试
mise run format   # 格式化 Swift
mise tasks        # 全部任务
```

浮窗布局按 Figma Owlet 设计更新：原文条与独立状态条、结果与学习双栏，使用系统 Liquid Glass。

通用设置中的“玻璃效果”仅影响浮窗：更透明／更高对比度（默认），即时生效并持久保留。

浮窗从处理状态以弹簧动效展开为结果面板；遵循系统减少动态效果设置。

浮窗学习界面以弹簧动效展开；点击词条整行立即切换词库收藏状态，取消立即移除，不需确认或提交；完整窗口学习流程保持不变。
