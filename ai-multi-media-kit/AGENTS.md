# AI Media Studio — 工作区 Agent 规则（V3）

这个工作区用于中文新媒体内容生产，采用 Agent Skills 的通用 `SKILL.md` 目录格式，不绑定 Codex 或其他模型。源码入口是 `SKILL.md`；独立工作区有 `.agents/skills/ai-media-studio/SKILL.md`，宿主不自动发现嵌套子 Skill 时按需读取。宿主的本地文件、终端与账号能力必须分别确认，详见 `docs/AGENT_COMPATIBILITY.md`。

- **数据归属**：企业知识库由 `config/workspace.json` 的 `knowledge_root` 指定。不要自动覆盖、迁移、上传企业数据；除授权范围内必要文本外，不将企业内部文件发给第三方平台。不得将 Cookie、API Key、密码、`.env` 复制到提示词或产物。
- **初始化**：不存在配置时引导使用 `SETUP-WINDOWS.cmd` / `SETUP-WINDOWS.ps1` 或 `bash SETUP-UNIX.sh`（自动安装套件内 Python，不要求系统安装）。依赖安装先用 `RUN-STUDIO-WINDOWS.ps1 -Task installer` / `bash run-studio.sh installer` 展示计划；用户批准后安装，逐个锁定 Git SHA，不假定已安装或已功能验证。
- **跨 Agent 路径记忆**：首次成功初始化后，Windows 在 `%LOCALAPPDATA%/ai-multi-media-kit/local-install.json`、macOS/Linux 在 `${XDG_CONFIG_HOME:-~/.config}/ai-multi-media-kit/local-install.json` 写一份当前系统用户级路径索引，供不同本地 Agent 共享；原主 Skill `config/local-install.json` 仅在共享索引缺失时用于旧版回退。每次和工作区的 `config/workspace.json` 双向核对，失效时停止，不猜测位置或迁移用户资料。不修改系统 PATH，不把安装记录纳入 Git。
- **真人审批**：AI 不得代表用户作出批准决定。用户在当前对话中明确批准指定内容 ID 的脚本、成片或平台/账号时，当前 Agent 可使用 `studio approve --chat-message <用户原话>` 记录批准，不再要求用户手动操作终端；原有终端口令仍可用。Agent 必须引用真实用户原话，不得推断、伪造或从 AI 输出中复制批准。审核 PASS 和版本哈希约束不变；实际公开上传仍需独立执行确认。
- **安全发布**：默认只生成发布包/dry-run。CLI 退出码不证明平台发布成功，未得到用户确认的链接时保持状态未知；不绕过平台访问限制。
- **工具排序**：已审核脚本/FFmpeg CLI > 受控现成工具 > 针对性 MCP > 新代码；尽可能避免重写现成能力。
- **素材独立与许可**：默认以 `knowledge_root/materials` 为本地素材源；其他共享目录、临时文件须显式登记。扫描只读原视频，索引存在工作区内。索引文本匹配不等于视觉识别，预览帧需 AI/人工核实。联网搜索/生成须事先授权、核对使用许可；未经验证授权的素材不得自动加入成片。
- **版本与产物**：内容 ID 不覆盖、脚本/审核/视频/发布包 SHA 防过期。发生变更重新审核/确认。所有重要输出保存到 `outputs/`，可导出但须审查敏感信息。
- **收费边界**：任何 AI Agent 的聊天订阅和第三方模型、TTS、素材及媒体 API 额度独立。未经确认不要启用收费云模型、素材、配音服务或付费投稿。
- **区分已测范围**：本地离线演示、真正 FFmpeg 视频、MPT 集成、真实平台投稿是不同的验收等级。不要混为一谈。

- **执行入口**：宿主有本机终端权限时，统一以绝对路径调用 `RUN-STUDIO-WINDOWS.ps1` / `run-studio.sh`；无需用户预装 Python、uv、Git 或修改系统 PATH。没有终端/本地目录权限时只进行文本任务，不能声称已成片/发布。安装第三方依赖要先展示来源、许可与费用并获得授权；`configure_mcp.py` 仅是 Codex 适配，其他宿主按自己的配置处理。
