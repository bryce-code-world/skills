# ai-multi-media-kit — 跨 AI Agent 新媒体生产 Skill

遵循 [Agent Skills / SKILL.md](https://agentskills.io/specification) 目录格式，以**企业自有知识库 + 本地可复用脚本/CLI/MCP**完成中文短视频选题、脚本、AI 审核、素材匹配、成片及七平台发布准备。适用于**具备相应能力的** Codex、Claude Code 或其他兼容 Agent Skills 的客户端；不依赖特定模型或厂商。

支持：小红书、抖音、微信视频号、B站、快手、微信公众号、知乎。短视频优先，公众号和知乎主要为图文衍生流程。

## 安装：把 GitHub 地址交给当前 AI Agent

在已经能安装 Agent Skills 的 AI Agent 中直接发送：

```text
请使用你自身支持的 Skill 安装方式安装并初始化：
https://github.com/bryce-code-world/skills/tree/main/ai-multi-media-kit

请获取完整的 SKILL.md、scripts、docs、knowledge-templates 和子 Skills，
先确认本 Agent 是否能读取本机文件、执行本地命令、联网下载依赖。
如果可以，请读取 SKILL.md 和 docs/AGENT_COMPATIBILITY.md：
- 先检查本机是否已有这套 Skill 的共享工具工作区；
- 已存在则复用，不要重新下载 Python、FFmpeg 或改动知识库；
- 不存在则引导我选一次工具安装目录、独立企业知识库目录，并经授权调用安装脚本。
不要修改系统级 PATH、擅自安装付费 API、登录媒体账号或公开发布。
如果当前 Agent 无本地执行能力，请明确只能进行哪部分工作。
```

**不需要先下载 ZIP，也不需要自己预装 Python。** 安装 Skill 和初始化运行环境是两件事：由当前 Agent 的 Skill 安装能力取得源码；引导器负责准备套件内的 Python/uv、Git、FFmpeg（受平台与网络限制）。第三方 Skills、MoneyPrinterTurbo、发布工具仅在用户明确授权后按需配置。

> 注意：`SKILL.md` 是开放的**指令文件格式**，不保证每个品牌、客户端或具体版本都支持 GitHub 地址导入、本地磁盘、Shell、Python 或平台登录。没有本地终端权限的云端 Agent 可以做文字策划，但不能直接操控用户电脑中的素材或合成视频。见 [Agent 兼容与能力分级](docs/AGENT_COMPATIBILITY.md)。

## 首次配置与日常使用

首次真正运行时，需要指定**两个不互相嵌套的目录**：

| 目录 | 内容 |
| --- | --- |
| 工具工作区 | Python/uv、FFmpeg、工具/Skills、运行缓存、审批与视频产物 |
| 企业知识库 | 品牌、目标用户、审核标准、历史内容、原创视频素材 |

**不同 Agent 可以复用同一套已安装工具。** 安装成功后，本机会保存一份不含密钥的路径索引：

- Windows：`%LOCALAPPDATA%\ai-multi-media-kit\local-install.json`
- macOS/Linux：`${XDG_CONFIG_HOME:-~/.config}/ai-multi-media-kit/local-install.json`

这是**同一设备/操作系统用户**下共享的一份小型配置，不是云同步服务。路径信息可能占用系统盘少量空间，真正的工具及素材依然使用你选定的位置；不修改系统 PATH。新 Agent 读取共享索引、核对 `config/workspace.json` 后用绝对路径启动工具；索引不存在时可读取旧版 Skill 目录中的 `config/local-install.json`。路径失效时需确认原位置并重新登记，不自动覆盖或迁移用户内容。

配置完成后，日常只需对当前 Agent 说：

```text
使用 ai-multi-media-kit，结合我的企业知识库，规划 10 条适合抖音和小红书的短视频，
完成选题、脚本和 AI 审核。先给我确认，不要自动发布或启用收费服务。
```

## 内容生产流程

**选题 → 脚本 → AI 审核 → 真人批准 → 视频素材匹配 → FFmpeg/MoneyPrinterTurbo 成片 → 真人验片 → 七平台发布包 → 授权发布及状态核验。**

素材优先来自企业本地目录、NAS/共享目录、临时视频；素材不足时可以使用**已经授权并验证的**外部素材来源，例如 MPT 的 Pexels/Pixabay/Coverr。当前支持文本索引与人工/Agent 检查画面，**不应把关键词匹配说成视频语义识别**。未经核实使用许可的素材不能直接用于公开发布。

Agent 负责选题、脚本、内容检查和镜头判断；现成脚本、FFmpeg、MoneyPrinterTurbo、平台 CLI/MCP 负责确定性操作。AI **不能代替用户输入批准或投稿确认短语**。平台上传工具退出正常并不代表真实审核或公开发布成功。

## 宿主环境的能力边界

| Agent 实际可用工具 | 可用功能 |
| --- | --- |
| 只会加载 Skill/生成文本 | 选题、草稿、建议；无本地成片和真实平台发布 |
| 可读写本机文件且可执行命令 | 独立工作区初始化、素材索引、审核记录、合成视频、导出发布包 |
| 另有经授权的媒体账号、CLI/MCP 或 API | 按平台和账号单独确认后尝试投稿，并核验结果 |

`start-codex.cmd` / `start-codex.sh` 是 Codex CLI 的**可选快捷方式**；`scripts/configure_mcp.py` 当前只负责 Codex 项目级 MCP 配置。其他 Agent 不需要它们：使用当前宿主自己的启动、MCP 注册和授权方式即可，不影响通用脚本。

## 手动安装（备用）

只有 Agent 不能自动导入 Skill 时，才把本目录完整复制到宿主能识别的 Skill 目录，然后使用脚本配置**运行环境**，无需下载额外的“Skill 安装包”：

```powershell
# Windows PowerShell
powershell -NoProfile -ExecutionPolicy Bypass -File .\SETUP-WINDOWS.ps1
```

```bash
# macOS / Linux
bash ./SETUP-UNIX.sh
```

初次安装运行时可能需要网络、HTTPS、解压工具和用户目录权限；工具下载失败应修复原因后再尝试。当前版本不保证 Windows ARM64 的 FFmpeg 或 Linux musl 自动安装。企业知识库和既有成果应始终保留。

## 参考

[Agent 兼容及共享环境](docs/AGENT_COMPATIBILITY.md) · [首次初始化](docs/START_HERE.md) · [素材源](docs/MATERIAL_SOURCES.md) · [内容与审批](docs/CONTENT_SCHEMA.md) · [工具选型](docs/TOOLCHAIN.md) · [验收矩阵](docs/ACCEPTANCE_V3.md)

目前已实现本地运行脚本、审批和素材索引等能力；**不同 Agent 的原生安装、真实在线素材获取、MoneyPrinterTurbo 成片以及各平台账号发布仍需分别在目标环境验收**，不能把源码兼容性当成实际能力验收。
