# AI Media Studio — 工作区 Agent 规则（V3）

这个工作区是中文新媒体内容生产，不是通用开发仓库。在本 Skill 源码目录中优先使用 `SKILL.md`；初始化后的工作区使用 `.agents/skills/ai-media-studio/SKILL.md`，按需加载其余 `ai-media-*` 子 Skill 和已安装第三方 Skills。

- **数据归属**：企业知识库由 `config/workspace.json` 的 `knowledge_root` 指定。不要自动覆盖、迁移、上传企业数据；除授权范围内必要文本外，不将企业内部文件发给第三方平台。不得将 Cookie、API Key、密码、`.env` 复制到提示词或产物。
- **初始化**：不存在配置时引导使用 `SETUP-WINDOWS.cmd` / `SETUP-WINDOWS.ps1` 或 `bash SETUP-UNIX.sh`（自动安装套件内 Python，不要求系统安装）。依赖安装先用 `RUN-STUDIO-WINDOWS.ps1 -Task installer` / `bash run-studio.sh installer` 展示计划；用户批准后安装，逐个锁定 Git SHA，不假定已安装或已功能验证。
- **真人审批**：AI 只能出审核建议，不能代表人完成 `studio approve` 的交互确认。成片和公开发布各自需要单独批准。
- **安全发布**：默认只生成发布包/dry-run。CLI 退出码不证明平台发布成功，未得到用户确认的链接时保持状态未知；不绕过平台访问限制。
- **工具排序**：已审核脚本/FFmpeg CLI > 受控现成工具 > 针对性 MCP > 新代码；尽可能避免重写现成能力。
- **素材独立与许可**：默认以 `knowledge_root/materials` 为本地素材源；其他共享目录、临时文件须显式登记。扫描只读原视频，索引存在工作区内。索引文本匹配不等于视觉识别，预览帧需 AI/人工核实。联网搜索/生成须事先授权、核对使用许可；未经验证授权的素材不得自动加入成片。
- **版本与产物**：内容 ID 不覆盖、脚本/审核/视频/发布包 SHA 防过期。发生变更重新审核/确认。所有重要输出保存到 `outputs/`，可导出但须审查敏感信息。
- **收费边界**：Codex 订阅额度与任何外部 API 独立。未经确认不要切换到收费云模型、素材、配音服务或付费投稿。
- **区分已测范围**：本地离线演示、真正 FFmpeg 视频、MPT 集成、真实平台投稿是不同的验收等级。不要混为一谈。

- **执行入口**：所有本地 Python 脚本统一经 `RUN-STUDIO-WINDOWS.ps1` / `run-studio.sh` 运行；不要要求非技术使用者先手动安装 Python、uv、Git 或修改系统 PATH。安装外部第三方依赖必须展示源仓库与许可并获得授权。
