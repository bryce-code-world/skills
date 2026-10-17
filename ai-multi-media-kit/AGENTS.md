# AI Media Studio — 工作区 Agent 规则

本工作区以 `SKILL.md` 为跨 Agent 入口；初始化工作区的业务子 Skill 在 `.agents/skills/ai-media-*/SKILL.md`。先核对宿主实际具备的本地文件、终端、网络与账号能力，再执行，不将只读文档能力冒充视频或发布能力。

- **创作归属与主次**：新任务使用 `studio new --topic --agent`，自动生成包含 Agent 和轮次的 ID；模型未知留空，不能从目录或文风猜测。接力创建同主题新 ID 并用 `--parent-id` 记录来源版本，不覆盖前一 Agent。brief/editorial_intent 明确核心用户价值与次级优势；测试环境、安装、复用信息默认写测试报告，不能替代介绍视频的内容主线。
- **发音准备**：新项目 TTS 前必须执行 `speech-plan`，已知风险词由 Agent 按上下文改稿并同步旁白/字幕。词典、TTS 输入稿、脚本和音色变更会使旧记录失效。READY 不等于实际发音正确；成片试听证据必须真实，不能用 ASR/能量报告替代或伪造。
- **一次任务授权**：用户下达内容任务即授权该任务范围内的选题、脚本、AI 审核、合法素材检索、免费工具安装与成片制作，无需逐阶段人工批准。仅当原始用户任务明确指定了**公开发布的平台与账号**，才能在 `studio new --publish-target platform:account` 登记该范围；制作/导出任务不等于公开发布授权。由 Agent 依据真实用户消息设置任务范围，禁止虚构或扩大。
- **双层质量闭环**：脚本经 `review.json` PASS 且无待核事实才能制作；视频经 `video/review.json` PASS 并绑定当前哈希才能打包。工程质量还必须通过工具对最终音轨的逐镜头有效发声/异常静音复核，不可用 AI 自报 PASS 代替。内容体验需对开头吸引力、实际示例、非 PPT 化镜头、语音自然度、字幕同步进行实际试听/查看与审查。未达标返工最多 3 轮；缺少试听/看视频能力不能谎称完成体验验收，也不以必要质量审核为由增加用户逐阶段审批。
- **人工参与边界**：原则上只在平台登录、扫码、验证码等宿主无法代办的身份步骤暂停；登录完成后续跑原任务。超出任务范围、收费或未经授权的第三方行为不得自动执行：优先换用已许可的免费方案，不能降级为擅自付费或公开发布。
- **跨 Agent 工作区复用（强制）**：每次使用先只读检查 Windows `%LOCALAPPDATA%/ai-multi-media-kit/local-install.json` 或 macOS/Linux `${XDG_CONFIG_HOME:-~/.config}/ai-multi-media-kit/local-install.json`，与现有 `config/workspace.json` 的工具目录、知识库及 `output_root` 双向核对；缺共享索引时先查主 Skill 旧记录，已知原工具目录时可用 `workspace_locator.py inspect` 只读验证。**已有有效环境必须直接复用**，不得要求重填三路径、运行 SETUP/init_workspace、重复下载安装 Python/uv/FFmpeg 或新建另一套成果目录。只有确无工作区且用户已指定路径才初始化；索引损坏或路径失效必须报错，禁止据此创建第二套。确需第二环境须有用户单独明确授权，并使用 `-NewWorkspace`/`--new-workspace`。免费第三方依赖仅对 `doctor` 确认缺失且当前任务需要的能力补装。全程不改系统 PATH、不覆盖用户资产或提交本机路径/凭据。
- **素材与数据**：以 `knowledge_root/materials` 为默认本地素材源，其他目录只在任务允许的范围内登记。保留原视频和许可元数据，按需使用 AI 核实镜头；索引文本匹配不是视觉识别。未经核实授权的素材不得使用，未经确认免费的 API 或素材服务不得使用。不得输出或保存 Cookie、API Key、账号密码、敏感第三方日志。
- **安全发布**：`studio package` 只生成发布包；`studio publish --execute` 必须严格匹配内容创建时记录的平台及账号，不再弹出 `PUBLISH` 确认。平台返回码不等于发布成功；链接须在对应平台核验，提交状态不明禁止重复盲发。未接入可靠投稿适配的公众号/知乎等只能交付发布包，不声称已发。
- **版本与可恢复性**：内容 ID 不覆盖、脚本与成片更新后旧 AI 审核失效；原任务的发布范围不可事后静默扩张。优先既有 FFmpeg/CLI/MCP，不为自动化重写成熟能力。所有成果以 `config/workspace.json` 中的 `output_root` 为唯一持久化根目录（脚本、成片、平台包及选题），旧版默认 `<install_root>/outputs`；禁止写到临时测试区或依赖安装区。记录真实成功、失败和不可验证项。
- **执行入口**：在具备本机权限的宿主使用绝对路径 `RUN-STUDIO-WINDOWS.ps1` / `run-studio.sh`。Codex 专属的 `start-codex.*`、`configure_mcp.py` 不是其他 Agent 的前提。离线演示、真实 FFmpeg 成片、MPT 集成和平台发布分别验收。
