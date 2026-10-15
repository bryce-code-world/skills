---
name: ai-multi-media-kit
description: 面向兼容 Agent Skills 的本地 AI Agent，利用企业知识库和免费/已授权工具自动完成短视频选题、脚本、AI 审核返工、素材匹配、FFmpeg/MoneyPrinterTurbo 成片、平台适配及明确授权范围内的发布；首次安装、共享环境诊断和全链路交付同样适用。
---

# ai-multi-media-kit — 一次任务、自主生产

面向 Codex、WorkBuddy、Claude Code 等实际支持 Agent Skills 的宿主；支持 Skill 不等于支持本机文件、终端、账号和发布能力。先读 [AGENTS.md](AGENTS.md) 和 [Agent 兼容指南](docs/AGENT_COMPATIBILITY.md)，再执行。

## 初始化与复用

1. 当前 Agent 只需用自身方式安装/加载 **Skill 入口**。**每次开始必须先只读发现**：检查 Windows `%LOCALAPPDATA%/ai-multi-media-kit/local-install.json` 或 macOS/Linux `${XDG_CONFIG_HOME:-~/.config}/ai-multi-media-kit/local-install.json`；共享记录缺失时检查当前 Skill 的旧版 `config/local-install.json`。能运行 Python 时执行 `scripts/workspace_locator.py show`；否则读取 JSON 并核对 `<install_root>/config/workspace.json` 的工具、知识库、`output_root` 三个实际目录。
2. **发现有效工作区即复用并停止初始化**：不再次询问三个目录，不运行 SETUP / `init_workspace.py`，不再次安装已存在的 Python、uv、FFmpeg 或第三方依赖。直接调用现有工作区的绝对路径启动器，需要时运行 `doctor` 检查实际缺失能力。即使用户再次提供同一组路径，也只能复用，不得创建第二套工具/知识库/输出环境。
3. **发现缺失才允许新建**：若共享索引不存在、但用户已给出旧工具路径，先用 `workspace_locator.py inspect --install-root <旧目录>` 验证 `workspace.json`，可按需 `register` 恢复索引，不运行安装器。若索引损坏、目录失效、三路径冲突，则停止并报告，**不得静默回退或转而新建**。只有确认确无已有工作区且用户明确选择三个目录，才能调用 `SETUP-WINDOWS.ps1` 或 `SETUP-UNIX.sh`；输出目录缺省兼容 `<install_root>/outputs`。用户确实要创建另一套环境时，需明确授权并指定 `-NewWorkspace` / `--new-workspace`，Agent 不得自行加此选项。
4. 已复用环境但 `doctor` 发现本任务需要的缺失工具时，只补齐该项经验证免费、合法的依赖；不得以“新 Agent 初次安装”为由重装全套。不同 Agent 可先后接管同一项目，但不应**同时写入同一内容 ID**；接管前确认前一 Agent 的写入已结束。宿主专属登录态/MCP 注册可能仍需检查；登录或验证码由用户本人操作，不修改系统 PATH。

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
