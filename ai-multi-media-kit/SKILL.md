---
name: ai-multi-media-kit
description: 面向兼容 Agent Skills 的本地 AI Agent，利用企业知识库和免费/已授权工具自动完成短视频选题、脚本、AI 审核返工、素材匹配、FFmpeg/MoneyPrinterTurbo 成片、平台适配及明确授权范围内的发布；首次安装、共享环境诊断和全链路交付同样适用。
---

# ai-multi-media-kit — 一次任务、自主生产

面向 Codex、WorkBuddy、Claude Code 等实际支持 Agent Skills 的宿主；支持 Skill 不等于支持本机文件、终端、账号和发布能力。先读 [AGENTS.md](AGENTS.md) 和 [Agent 兼容指南](docs/AGENT_COMPATIBILITY.md)，再执行。

## 初始化与复用

1. 用当前宿主的 Skill 安装能力获取完整源码与子 Skills。检查系统用户共享索引：Windows `%LOCALAPPDATA%/ai-multi-media-kit/local-install.json` 或 macOS/Linux `${XDG_CONFIG_HOME:-~/.config}/ai-multi-media-kit/local-install.json`，同 `<install_root>/config/workspace.json` 核对。路径失效时停止猜测，核实原目录。
2. 未初始化时由用户指定互不嵌套的**工具安装目录**、**企业知识库目录**和**项目成果目录**，调用 `SETUP-WINDOWS.ps1` 或 `SETUP-UNIX.sh`（第三个目录参数为 `-OutputRoot` / `--output-root`）。成果目录未指定时兼容旧位置 `<install_root>/outputs`。已有工作区直接读取 `config/workspace.json` 的 `output_root`，不自动更改或搬迁已有内容；无需系统 Python、uv、Git 或修改 PATH。
3. 已验证为免费、且本次任务实际需要的本地工具，可用 `RUN-STUDIO-WINDOWS.ps1 -Task installer --component <组件> --install`（Linux/macOS 使用 `run-studio.sh`）按白名单安装并验证，不再要求 `INSTALL` 键盘口令；登录或验证码必须留给用户本人。

## 自动内容流水线

1. 从真实用户任务确定交付目标。默认**只制作不公开发布**。仅当该任务明确要求公开发布并给出平台及账号别名，在创建内容时添加 `studio new --id <ID> --title "主题" --publish-target douyin:main`；多个发布目标重复该参数。可用 `--task-ref` 记录原始用户消息引用。不要依据对话推断、虚构或扩大发布范围。
2. 结合知识库，调用 `ai-media-topics`、`ai-media-scripts` 形成 `brief.md`、`script.json`，根据 `ai-media-review` 生成 `review.json`。运行 `studio hash/check`；不合格自动修改再审核，最多 3 轮。**不请求用户审批脚本。**
3. 用 `ai-media-materials` 找到原有或已核实免费且允许使用的素材，通过 `materials resolve/preview` 核实镜头、版权；缺素材可自主更换合法方案，不询问用户逐个确认。选择需要免费且兼容的 FFmpeg / MPT，以 `studio render` 或 `studio import-video` 生成实际 MP4；`--rights-confirmed` 只表示 Agent 已核验素材来源/权利，绝非真人审批。
4. 自动使用 `ffprobe` 和真实视频画面/关键帧校验时长、画质、字幕、口播、镜头一致性和来源，形成 `video/review.json`。成片审核未 PASS 便返工，不得虚构画面检查、审核 PASS 或凭合成成功冒充质量验收。**不请求用户验片批准。**
5. `studio package` 仅生成待发布包。初始任务授权了公开发布的平台与账号，且该平台已有经验证投稿工具和登录态时，`studio publish --platform <p> --account <alias> --execute` 自动投稿，不再人工复批。发布状态未知时不盲重试；获取官方作品链接并核对后用 `studio confirm-published` 记录。
6. 在 `config/workspace.json` 的 `output_root` 下按 `内容ID/` 持久保存脚本、审核、素材选择、MP4、平台包与发布记录，批量选题放 `output_root/_plans/`；所有 Agent 使用同一配置定位，不把正式成果放 Skill 源码、工具运行缓存或临时目录。若工具能力不足，只报告已完成部分与阻塞，不能把模板、dry-run 当成成片。

**停止条件**：默认至多 3 轮内容返工；需要账号登录/扫码/验证码时暂停等待用户完成后继续。收费、越权发布、未经许可素材、缺失真实上传能力均不得绕过，不以“无审批”为理由突破用户原始任务范围。

## CLI 与说明

Windows `<install_root>/RUN-STUDIO-WINDOWS.ps1 -Task studio|materials|installer|doctor ...`；Unix `bash <install_root>/run-studio.sh studio|materials|installer|doctor ...`。基于当前宿主可用终端按绝对路径调用。

按需查阅：[首次安装](docs/START_HERE.md) · [内容及质量结构](docs/CONTENT_SCHEMA.md) · [素材源](docs/MATERIAL_SOURCES.md) · [工具链](docs/TOOLCHAIN.md) · [验收矩阵](docs/ACCEPTANCE_V3.md)。业务子 Skills 在 `.agents/skills/ai-media-*/SKILL.md`，宿主未自动发现时由主 Agent 按阶段直接读取。
