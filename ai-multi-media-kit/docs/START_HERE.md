# 安装、复用与更新

单条视频先读 [QUICK_VIDEO](QUICK_VIDEO.md)；只有缺少环境或版本不匹配时才用本页。完整生产流程见 [ai-media-studio](../.agents/skills/ai-media-studio/SKILL.md)。

## 区分三个位置

| 位置 | 用途 | 怎样更新 |
| --- | --- | --- |
| Skill 源码 | 维护入口、脚本、文档和模板 | 获取已核实的仓库版本 |
| 各 Agent 的 Skill 安装目录 | 供当前宿主发现并读取入口 | 使用该宿主的安装方式更新；核实是副本还是指向源码的链接 |
| 共享工具工作区 | 执行启动器、保存配置及运行依赖 | 使用新源码中的 `upgrade_core.py` 更新自有核心 |

源码更新不会自动同步客户端的独立副本，也不会自动升级共享工作区。分别核对 `references/release.json` 和所需文件；链接安装则核实真实目标。更新前保留本地修改，不能只凭目录存在或某一处版本号声称三处均已更新。

源码：[bryce-code-world/skills/ai-multi-media-kit](https://github.com/bryce-code-world/skills/tree/main/ai-multi-media-kit)。通过宿主支持的方式获取完整目录，包括 `assets`、`scripts`、`docs`、`references`、`config`、`knowledge-templates` 和 `.agents`；只复制 `SKILL.md` 无法执行。宿主还须具备所需的本地文件与终端能力。

## 优先复用已有工作区

同一设备、系统用户的共享索引位于：

- Windows：`%LOCALAPPDATA%\ai-multi-media-kit\local-install.json`
- macOS/Linux：`${XDG_CONFIG_HOME:-~/.config}/ai-multi-media-kit/local-install.json`

用已有 Python 执行 `scripts/workspace_locator.py show`，核对索引与 `config/workspace.json` 的 `install_root`、`knowledge_root`、`output_root`，从返回的绝对路径调用启动器。有效环境直接复用，不执行 SETUP 或重新安装 Python/FFmpeg。

索引缺失时，先查 Skill 的旧版记录；已知原工具路径可用 `workspace_locator.py inspect --install-root <工具目录>` 只读验证，再用 `register --install-root <工具目录>` 恢复索引。索引损坏、路径不一致或无法访问时报告具体问题，不据此创建另一套环境。纯云端宿主无法自动访问用户电脑的索引。

## 首次初始化

仅在确无既有工作区且用户已指定工具、知识库路径时执行。成果目录可指定，省略时为 `<install_root>/outputs`。

Windows PowerShell 5.1+：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\SETUP-WINDOWS.ps1 -InstallRoot "D:\自选工具目录" -KnowledgeRoot "D:\自选知识库" -OutputRoot "D:\自选视频项目" -NonInteractive
```

Linux/macOS：

```bash
bash ./SETUP-UNIX.sh --install-root "$HOME/media-tools" --knowledge-root "$HOME/company-knowledge" --output-root "$HOME/video-projects" --non-interactive
```

安装器发现已有登记环境时返回 `REUSE_EXISTING_WORKSPACE`，不搬迁资料。确需第二套环境须有单独授权，再用 `-NewWorkspace` 或 `--new-workspace`。本地依赖放在工具目录，不修改系统 PATH；项目成果只写 `output_root/<内容ID>/`。

## 升级共享工作区

从**新源码目录**执行，先查看计划：

```text
python scripts/upgrade_core.py --root <工具目录>
python scripts/upgrade_core.py --root <工具目录> --apply
```

确认属于本次更新范围、没有覆盖未知修改或另一 Agent 同时更新后应用。脚本备份将更新的自有文件，保留用户知识库、配置、运行依赖与历史成果。只运行旧工作区里的旧升级脚本不能保证取得新源码。

完成后用原启动器运行 `doctor --scope core --strict`，再检查当前任务的必要能力。`doctor` 检查本地结构和工具存在，不代表已完成真实渲染、试听或平台发布。

## 按任务补齐依赖

- 单条快速制作：内置 Remotion 模板，需要可用 Node/npm；`studio quick --dry-run` 检查输入，不创建项目、不安装依赖。真实渲染首次需安装工程的锁定 npm 依赖，并可能下载浏览器。video-shotcraft 只在显式传入 `--shotcraft-dir` 时使用，不是默认前置。
- 素材剪辑或完整生产：按实际渲染器准备 FFmpeg、自然 TTS；仅使用 MoneyPrinterTurbo 时安装 `mpt`。
- 平台发布：只有明确的平台与账号任务才准备相应适配及登录。制作任务不要求配置多个平台或额外文本模型 API。

第三方安装器默认只显示计划，例如 `RUN-STUDIO-WINDOWS.ps1 -Task installer --component mpt`；确认当前任务确需、来源与许可允许后才加 `--install`。其 `core` 分组是 marketing/baoyu 第三方包，不是快速制作的必装集合。依赖边界见 [TOOLCHAIN](TOOLCHAIN.md)。

需要验证更新或完整生产时按需使用 [测试提示词](TEST_PROMPT.md)；不要将安装日志、路径校验和通过数放进产品宣传主线。
