# 安装、共享运行环境与一次任务启动

## 将 Skill 链接交给 Agent

`https://github.com/bryce-code-world/skills/tree/main/ai-multi-media-kit`

请使用当前 Agent 自己的 Skill 安装方式获取**整个目录**，包含 `SKILL.md`、`scripts`、`docs`、`knowledge-templates` 与所有子 Skills。无需手动下载 ZIP，也无需预装 Python。**宿主能读取 Skill 不代表能调用本机文件或终端**；若只能文本生成，不得宣称已成片或发布。

**先发现、再决定要不要安装运行时**：每个 Agent 只需安装本身能识别的 Skill 入口。第一次已有其他 Agent 创建的工具工作区时，读本机共享索引，核对 `config/workspace.json` 的工具、知识库、输出三个目录，直接复用，不重复询问或重新安装 Python/FFmpeg。只有确无有效工作区且用户明确指定三目录，才执行初始化；第三目录可省略，默认 `<install_root>/outputs`。

## 不同 Agent 复用共享目录

首次初始化完成后，同一设备/系统用户共享安装路径索引：

- Windows：`%LOCALAPPDATA%\ai-multi-media-kit\local-install.json`
- macOS / Linux：`${XDG_CONFIG_HOME:-~/.config}/ai-multi-media-kit/local-install.json`

**发现有效记录立即复用；不要执行 SETUP/init_workspace。** 可用已有 Python 执行 `scripts/workspace_locator.py show` 只读输出 `install_root`、`knowledge_root`、`output_root` 和启动器绝对路径；然后按实际任务运行 `doctor`，只补装必要且确实缺少的免费依赖。共享索引缺失时可尝试本 Skill 目录的旧版记录；如果用户知道旧工具路径，可用 `scripts/workspace_locator.py inspect --install-root <已有工具目录>` 只读检查，再用 `register --install-root <已有工具目录>` 恢复索引，不重新下载工具。**索引损坏、三目录不一致或无法访问，必须停止并报错，不能自动新建。** 确需第二套环境需用户另行明确授权并传 `-NewWorkspace`（Windows）或 `--new-workspace`（Unix/初始化脚本）。纯云端隔离 Agent 无法自动访问本地索引。

## 初始化本地工具

Windows PowerShell 5.1+：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\SETUP-WINDOWS.ps1 -InstallRoot "D:\自选工具目录" -KnowledgeRoot "D:\自选企业知识库" -OutputRoot "D:\自选视频项目" -NonInteractive
```

Linux/macOS：

```bash
bash ./SETUP-UNIX.sh --install-root "$HOME/media-tools" --knowledge-root "$HOME/company-knowledge" --output-root "$HOME/video-projects" --non-interactive
```

**上面的安装命令只适用于首次新建环境。** 即使从其他 Agent 再次执行安装器，只要发现已登记环境，也会在下载安装前返回 `REUSE_EXISTING_WORKSPACE`，不覆盖或迁移已有资料。Python 3.12/uv、便携 Git 和 FFmpeg 优先安装到工具目录，项目成果在 `output_root/<内容ID>/`，批量选题在 `output_root/_plans/`；不改系统 PATH。首次在线安装、平台登录和真实发布仍需按环境验证。

## 升级已有工作区而不覆盖资料

重新安装 Skill 源码不会自动覆盖用户的旧运行环境或独立项目成果目录。应由 Agent 使用**新获取的 Skill 源码目录**下的 `scripts/upgrade_core.py --root <已有工具目录> --apply`，先备份将覆盖的 Skill 自有文件，再更新；用户知识库、outputs、账号与 runtime 不变。当前版本 `--apply` 不要求额外升级口令。完成后从原绝对路径重新运行 `doctor` 和回归检查。只运行已有工作区内部的旧版升级脚本可能无法获取新源码，不能误报已更新。

## 快速成片（避免冗余配置）

已经有共享工具工作区时，Agent 可直接执行 `RUN-STUDIO-WINDOWS.ps1 -Task studio quick --spec <分镜.json> --topic <主题> --agent <宿主>`，不需要重新初始化工具、知识库或七个平台。先用 `--dry-run` 只读检查，再生成 MP4 和可编辑 Remotion 工程。必须已安装 Node/npm 及 video-shotcraft；未安装时明确报告，不自动申请付费服务。

**此模式只是技术预览**，不代表脚本、读音和成片质量已获批准，更不会直接发布。具体格式见 [快速创作指南](QUICK_VIDEO.md)。

## 自动化日常执行

Agent 使用已初始化工具目录的绝对路径调用启动器：

```powershell
& "<工具目录>\RUN-STUDIO-WINDOWS.ps1" -Task doctor --scope core --strict
& "<工具目录>\RUN-STUDIO-WINDOWS.ps1" -Task studio new --topic first-video --agent workbuddy --model GLM-5.3-Flash --title "我的第一条视频"
& "<工具目录>\RUN-STUDIO-WINDOWS.ps1" -Task installer --component mpt
```

安装器默认仅展示计划。在实际需要且**已核实免费、属于初始任务范围**时，Agent 可以加 `--install` 执行安装，无需用户另输 `INSTALL`。不得借此启用未知费用的云服务。

之后 Agent 自行读取 `brand.md`、`audience.md`、`review-rules.md`，完成编稿、AI 审核、素材、实际渲染、视频 AI 验收、平台包。**制作任务不需要中间阶段审批**；默认至多三轮纠错。

如果原始用户请求中明确要求“发布到指定平台的指定账号”，创建内容时可以在 `studio new` 添加 `--publish-target 平台:账号`，但制作/导出不能推断为公开发布。后续 `studio publish --execute` 不要求再次批准，只能按该范围执行。无实际投稿工具或作品链接时不能宣称已发布。详见 [内容数据](CONTENT_SCHEMA.md)、[素材](MATERIAL_SOURCES.md)、[兼容](AGENT_COMPATIBILITY.md)。
## 新项目测试入口

新任务用 `studio new --topic <共同主题> --agent <实际宿主> --model <已核实的模型名称> --title "主题"` 自动生成同时含主题、Agent、模型标签、轮次的目录；上例 workbuddy/GLM 只是示意，必须换成当前宿主真实值，模型未知则省略整个 `--model` 参数且目录标 `model-unknown`，原始 `model_id` 为 null，不猜测。用 `studio list --topic` 查看同主题成果。

V0.10 新项目还需明确 `editorial_intent` 和 `focus_alignment`，TTS 前执行 `speech-plan`，处理已知风险词并同步字幕。烧录字幕先对渲染器声明的正文/字幕 bbox 执行 `scripts/subtitle_layout.py --layout` 预检，并从最终 MP4 的每个字幕镜头抽帧核对不遮挡正文，不能仅靠 SRT 正确或字幕可读判 PASS。只有真实试听才能填写成片 `pronunciation_check`；不能把文本预检或 ASR 当作发音验证。详细字段见 [内容契约](CONTENT_SCHEMA.md)。

进行本套件介绍视频测试时，使用 [测试提示词](TEST_PROMPT.md) 和 [专用产品定位](examples/ai-multi-media-kit-introduction.md)：主线是视频自动化工作流，安装与跨 Agent 复用只是技术测试和辅助优势。
