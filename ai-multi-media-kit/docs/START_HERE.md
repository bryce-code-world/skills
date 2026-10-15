# 安装、共享运行环境与一次任务启动

## 将 Skill 链接交给 Agent

`https://github.com/bryce-code-world/skills/tree/main/ai-multi-media-kit`

请使用当前 Agent 自己的 Skill 安装方式获取**整个目录**，包含 `SKILL.md`、`scripts`、`docs`、`knowledge-templates` 与所有子 Skills。无需手动下载 ZIP，也无需预装 Python。**宿主能读取 Skill 不代表能调用本机文件或终端**；若只能文本生成，不得宣称已成片或发布。

首次配置请指定两个不相互嵌套的目录：**工具工作区**与**企业知识库**。若已经有本机共享路径索引，先读取并核对路径，合法存在即复用，不要复制另一套工作区。

## 不同 Agent 复用共享目录

首次初始化完成后，同一设备/系统用户共享安装路径索引：

- Windows：`%LOCALAPPDATA%\ai-multi-media-kit\local-install.json`
- macOS / Linux：`${XDG_CONFIG_HOME:-~/.config}/ai-multi-media-kit/local-install.json`

必须与 `<install_root>/config/workspace.json` 双向核对，不能在路径失效时擅自全盘扫描、重装或迁移原数据。旧版的主 Skill `config/local-install.json` 只在共享索引缺失时作为只读回退。需要恢复现有工作区时，可用其自有 Python 执行 `scripts/workspace_locator.py register --install-root <已有工具目录>`。纯云端隔离 Agent 无法自动使用 Windows 本地索引。

## 初始化本地工具

Windows PowerShell 5.1+：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\SETUP-WINDOWS.ps1 -InstallRoot "D:\自选工具目录" -KnowledgeRoot "D:\自选企业知识库" -NonInteractive
```

Linux/macOS：

```bash
bash ./SETUP-UNIX.sh
```

引导器将 Python 3.12/uv、便携 Git 和 FFmpeg 优先安装到工具目录，缓存不修改系统级 PATH；再次运行复用原配置并保护用户资产。平台、证书和联网条件仍需真实验证。必须用户处理的账号登录、扫码、验证码由 Agent 暂停等待，成功后继续执行。

## 升级已有工作区而不覆盖资料

重新安装 Skill 源码不会自动覆盖用户的旧运行环境。应由 Agent 使用**新获取的 Skill 源码目录**下的 `scripts/upgrade_core.py --root <已有工具目录> --apply`，先备份将覆盖的 Skill 自有文件，再更新；用户知识库、outputs、账号与 runtime 不变。当前版本 `--apply` 不要求额外升级口令。完成后从原绝对路径重新运行 `doctor` 和回归检查。只运行已有工作区内部的旧版升级脚本可能无法获取新源码，不能误报已更新。

## 自动化日常执行

Agent 使用已初始化工具目录的绝对路径调用启动器：

```powershell
& "<工具目录>\RUN-STUDIO-WINDOWS.ps1" -Task doctor --scope core --strict
& "<工具目录>\RUN-STUDIO-WINDOWS.ps1" -Task studio new --id demo-001 --title "我的第一条视频"
& "<工具目录>\RUN-STUDIO-WINDOWS.ps1" -Task installer --component mpt
```

安装器默认仅展示计划。在实际需要且**已核实免费、属于初始任务范围**时，Agent 可以加 `--install` 执行安装，无需用户另输 `INSTALL`。不得借此启用未知费用的云服务。

之后 Agent 自行读取 `brand.md`、`audience.md`、`review-rules.md`，完成编稿、AI 审核、素材、实际渲染、视频 AI 验收、平台包。**制作任务不需要中间阶段审批**；默认至多三轮纠错。

如果原始用户请求中明确要求“发布到指定平台的指定账号”，创建内容时可以在 `studio new` 添加 `--publish-target 平台:账号`，但制作/导出不能推断为公开发布。后续 `studio publish --execute` 不要求再次批准，只能按该范围执行。无实际投稿工具或作品链接时不能宣称已发布。详见 [内容数据](CONTENT_SCHEMA.md)、[素材](MATERIAL_SOURCES.md)、[兼容](AGENT_COMPATIBILITY.md)。