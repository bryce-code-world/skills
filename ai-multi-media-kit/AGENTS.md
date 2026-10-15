# AI Media Studio — 工作区 Agent 规则

本工作区以 `SKILL.md` 为跨 Agent 入口；初始化工作区的业务子 Skill 在 `.agents/skills/ai-media-*/SKILL.md`。先核对宿主实际具备的本地文件、终端、网络与账号能力，再执行，不将只读文档能力冒充视频或发布能力。

- **一次任务授权**：用户下达内容任务即授权该任务范围内的选题、脚本、AI 审核、合法素材检索、免费工具安装与成片制作，无需逐阶段人工批准。仅当原始用户任务明确指定了**公开发布的平台与账号**，才能在 `studio new --publish-target platform:account` 登记该范围；制作/导出任务不等于公开发布授权。由 Agent 依据真实用户消息设置任务范围，禁止虚构或扩大。
- **AI 质量闭环**：脚本经 `review.json` 全项 PASS 且无待核事实才能制作；视频经 `video/review.json` 全项 PASS，绑定当前脚本、成片及审核标准哈希，才能打包、发布。发现问题自主修正并重新审核，默认最多 3 轮，仍无法达到标准则如实交付阻塞，不伪造 PASS，也不将质量判断交给用户。
- **人工参与边界**：原则上只在平台登录、扫码、验证码等宿主无法代办的身份步骤暂停；登录完成后续跑原任务。超出任务范围、收费或未经授权的第三方行为不得自动执行：优先换用已许可的免费方案，不能降级为擅自付费或公开发布。
- **安装与共享环境**：首次初始化按 `SETUP-WINDOWS.ps1` / `SETUP-UNIX.sh` 使用用户指定的工具目录和独立知识库目录。Windows 共享索引在 `%LOCALAPPDATA%/ai-multi-media-kit/local-install.json`，macOS/Linux 在 `${XDG_CONFIG_HOME:-~/.config}/ai-multi-media-kit/local-install.json`；再次使用须同 `config/workspace.json` 核对。不修改系统 PATH、不覆盖用户资产、不向 Git 提交本机安装路径或密钥。按需安装免费第三方工具，先检查固定来源、许可及费用；原任务范围内调用安装器 `--install`，不再要求终端口令。
- **素材与数据**：以 `knowledge_root/materials` 为默认本地素材源，其他目录只在任务允许的范围内登记。保留原视频和许可元数据，按需使用 AI 核实镜头；索引文本匹配不是视觉识别。未经核实授权的素材不得使用，未经确认免费的 API 或素材服务不得使用。不得输出或保存 Cookie、API Key、账号密码、敏感第三方日志。
- **安全发布**：`studio package` 只生成发布包；`studio publish --execute` 必须严格匹配内容创建时记录的平台及账号，不再弹出 `PUBLISH` 确认。平台返回码不等于发布成功；链接须在对应平台核验，提交状态不明禁止重复盲发。未接入可靠投稿适配的公众号/知乎等只能交付发布包，不声称已发。
- **版本与可恢复性**：内容 ID 不覆盖、脚本与成片更新后旧 AI 审核失效；原任务的发布范围不可事后静默扩张。优先既有 FFmpeg/CLI/MCP，不为自动化重写成熟能力。所有产物保存在 `outputs/`，记录真实成功、失败和不可验证项。
- **执行入口**：在具备本机权限的宿主使用绝对路径 `RUN-STUDIO-WINDOWS.ps1` / `run-studio.sh`。Codex 专属的 `start-codex.*`、`configure_mcp.py` 不是其他 Agent 的前提。离线演示、真实 FFmpeg 成片、MPT 集成和平台发布分别验收。
