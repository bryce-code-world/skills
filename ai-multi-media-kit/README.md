# ai-multi-media-kit — 跨 AI Agent 自动内容生产 Skill

这是符合 [Agent Skills / SKILL.md](https://agentskills.io/specification) 的跨宿主 Skill。使用企业知识库和已验证免费的本地工具，将中文短视频的**选题、脚本、AI 审核返工、素材检索、视频合成和内容交付**串成自动流程；若用户在**初始任务**明确指定发布平台和账号，则在受支持且已登录的平台上自动投稿。

支持小红书、抖音、微信视频号、B站、快手的短视频准备，以及微信公众号、知乎的图文衍生稿；真实投稿能力须按具体工具、平台和账号单独验证，不能把发布包等同于已发布。

## 交给 AI Agent 安装

将下面的 Skill 地址交给当前支持 Agent Skills、且拥有本机文件和终端权限的 Agent：

https://github.com/bryce-code-world/skills/tree/main/ai-multi-media-kit

发送示例：

> 请使用你自身的 Skill 安装功能安装上面的完整 Skill（包括 scripts、docs、knowledge-templates 和子 Skills），读取 `SKILL.md`、`AGENTS.md`、`docs/START_HERE.md`。我指定工具目录和独立的企业知识库目录；先检查同一系统用户的共享工作区，存在就复用，否则按指定路径初始化。使用已验证免费的工具完成一条 45～60 秒中文 9:16 竖屏视频，自动选题、编稿、审核、选材、返工和生成 MP4。除我必须完成的账号登录、扫码、验证码外，不要在脚本、成片、素材和工具安装阶段要求逐项审批。**本次只制作不公开发布。** 交付真实视频及审核记录，不得调用收费服务或覆盖既有用户数据。

**不需要用户先下载 ZIP 或预装 Python。** Skill 源码安装和运行环境安装是两件事。宿主不支持本机文件/命令时只能做文案等文本任务，不得冒充已成片。云端隔离 Agent 也不能自动访问用户电脑的 D: 盘。

## 两个用户指定目录与共享定位

首次运行需要两个**互不嵌套**的目录：工具工作区（自有 Python、uv、FFmpeg、工具与视频产物）和企业知识库（品牌、受众、审核标准、授权素材）。按实际平台使用 `SETUP-WINDOWS.ps1` 或 `SETUP-UNIX.sh` 初始化。

Windows 在 `%LOCALAPPDATA%\ai-multi-media-kit\local-install.json`，macOS/Linux 在 `${XDG_CONFIG_HOME:-~/.config}/ai-multi-media-kit/local-install.json` 记录路径索引。每个 Agent 读取索引并核对 `config/workspace.json`，用**绝对路径**运行工具。共享路径不等于云同步；不修改系统级 PATH，不覆盖或迁移用户资料。不能定位时报告真实原因，不凭猜测重装。

已有环境，Agent 可以执行：

```powershell
& "<工具目录>\RUN-STUDIO-WINDOWS.ps1" -Task doctor --scope core --strict
& "<工具目录>\RUN-STUDIO-WINDOWS.ps1" -Task test
```

首次安装缺失的免费工具按 `installer --component <组件>` 先核对来源，再使用 `--install`，不要求用户手动输入安装口令；第三方服务收费未知时禁止擅自启用，选择免费替代方案。

## 更新已经安装的运行环境

若另一 Agent 已在本机安装旧版，不能仅重新执行初始化脚本（它会保护原文件，不覆盖）。获取新版本 Skill 源码后，由本地 Agent 使用**新源码中的** `scripts/upgrade_core.py --root <已有工具目录> --apply` 更新；该操作仅替换本 Skill 自有文件，先备份旧文件，不移动企业知识库与 outputs，不要求用户输入升级口令。必须检查目标 `config/workspace.json` 路径与任务范围，不在已有目录中直接运行其旧版升级脚本冒充已升级。

## 自主生产与质量门禁

**用户一次下达任务 → AI 选题/编稿 → AI 审核与自动返工 → 合法素材 → 真实 MP4 → AI 成片审核与返工 → 打包交付。**

内容 ID 下的 `script.json`、`review.json`、`video/master.mp4`、`video/render.json`、`video/review.json` 相互绑定哈希。每次修改必须重新审核；未核事实、非 PASS、素材未经授权、不存在真实成片时，后续步骤被拒绝。AI 默认最多三轮返工，失败要暴露原因，不得伪造 PASS。详见 [内容结构](docs/CONTENT_SCHEMA.md)。

**公开发布采用初始任务范围，不设二次批准。** 例如用户明确要求“发布到抖音 main 账号”，Agent 在 `studio new` 时记录 `--publish-target douyin:main`。之后 `studio publish --execute` 只允许该平台及账号，先确保审核、视频、发布包均为当前版本。仅要求制作或导出的任务永远不会自动获取发布权限；若后来扩大范围，应建立新的明确授权任务而不是私自改记录。平台首次登录等身份环节可能需要用户操作。

发布 CLI 返回成功不意味着实际作品公开成功；拿到可核验的对应平台作品链接后才能标为已发布。状态未知禁止盲重试。公众号和知乎目前只稳定支持生成图文包，真实自动发布依赖另行验证的宿主与工具，不会伪造发布结果。

## 工具与能力边界

优先本地已许可视频素材和 FFmpeg；按需使用 MoneyPrinterTurbo 与 `social-auto-upload` 等经验证工具。文本关键词命中不等于 AI 看过画面；FFmpeg 默认只拼接已有素材，没有配音就可能是静音，不能用无声视频冒充口播成片。素材来源和传播许可必须可追溯，未经核实的网络素材不能随意使用。

安装脚本、审批迁移、平台兼容和已测范围参见 [首次使用](docs/START_HERE.md) · [Agent 兼容](docs/AGENT_COMPATIBILITY.md) · [内容与质量](docs/CONTENT_SCHEMA.md) · [素材源](docs/MATERIAL_SOURCES.md) · [工具链](docs/TOOLCHAIN.md) · [验收矩阵](docs/ACCEPTANCE_V3.md)。