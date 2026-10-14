# ai-multi-media-kit — AI 新媒体生产 Skill

基于 **Codex + Skills + CLI/MCP + 自有企业知识库**，完成选题、脚本、审核、素材匹配、短视频成片和多平台发布准备。面向小红书、抖音、微信视频号、B站、快手、微信公众号和知乎；**短视频优先**。

这是给 AI Agent 使用的 Skill，不是需要下载安装的桌面软件。**推荐直接把 GitHub 地址发给 Codex，让它安装并引导配置。**

## 推荐安装：直接把地址发给 Codex

在已可用的 Codex CLI、Codex IDE 或其他支持 GitHub Skills 的 Agent 中，发送以下消息：

```text
请安装并初始化这个 Skill：
https://github.com/bryce-code-world/skills/tree/main/ai-multi-media-kit

使用 Agent 的标准 Skill 安装方式安装完整目录（包含 SKILL.md、scripts、docs 和子 Skills），检查 Skill 是否被识别。
随后阅读 SKILL.md 和 docs/START_HERE.md，检查本机环境，引导我指定：
1. 工具及运行环境安装目录（Python、uv、Git、FFmpeg、缓存等尽量放在此目录）。
2. 独立的企业知识库目录（品牌、内容规则、自有视频素材）。

由你调用 Skill 自带的初始化脚本，先展示需要安装的外部依赖、来源和可能产生的费用；得到我的授权后，再安装缺失的依赖并运行自检。
不要让我手动下载 ZIP 或预装 Python，不要修改系统级 PATH，也不要擅自登录媒体账号、启用付费 API 或公开发布。
```

**两件事要区分：** 安装 Skill 是把它放到 Codex 可发现的 Skill 目录；首次初始化才会配置独立工作区和工具依赖。Skill 安装完成不代表 MoneyPrinterTurbo、MCP 或视频发布工具也已经安装、连通。

首次使用要求当前 Agent 可以读取 GitHub 仓库、访问本地终端并获准写入相关目录。若 Agent 不支持 GitHub Skill 安装或网络不可用，应明确报告阻塞，再采用下文的手动备用方式。安装后若暂时无法识别 Skill，可重新打开 Codex 会话并检查安装位置。

**安装路径会被记住：** 初始化成功后，安装器自动在主 Skill 目录的 `config/local-install.json` 保存工具目录及知识库目录（本机私有，已 Git 忽略）。日后从其他项目、新的 Codex 会话调用时，AI 从 Skill 所在目录读取并核对这条记录，然后调用工作区内的绝对路径启动器。无需重复填写目录，也无需修改系统 PATH。Skill 被删除重装或安装目录迁移后，记录可能丢失/失效；这时应重新登记已有工作区，而不是自动重装或覆盖数据。

## 初始化成功后怎么用

在 Codex 中直接对话即可，不需要每天运行命令：

```text
使用 $ai-multi-media-kit，读取我的企业知识库，策划 10 条适合抖音和小红书的短视频选题，
按审核标准生成脚本。先让我确认，不要自动发布或调用收费 API。
```

也可以让 AI 按需调用主 Skill 中的 `ai-media-topics`、`ai-media-scripts`、`ai-media-review`、`ai-media-materials`、`ai-media-video`、`ai-media-publish` 子 Skill。**Codex 负责创作和判断；本地脚本、FFmpeg、MoneyPrinterTurbo 与平台 CLI/MCP 负责执行。**

第一次初始化时，AI 会引导选择两个互不嵌套的目录：

| 目录 | 保存什么 |
|---|---|
| 工具工作区 | 自有运行脚本、Python/uv、Git、FFmpeg、第三方 Skills/CLI/MCP、缓存和产出 |
| 企业知识库 | 品牌定位、目标用户、创作方法、审核标准、优秀案例及自有素材 |

已有资料不会因重复初始化被自动覆盖。工具尽量集中安装，不要求预装系统 Python、uv 或 Git；操作系统自身的少量缓存无法保证完全不使用系统盘。

## 已有能力与边界

- **内容工作流：** 批量选题、脚本、AI 审核、人工批准、成片、七个平台发布包。
- **素材来源：** 企业本地目录、NAS/共享目录、单次视频、合法下载的网络素材；支持索引、搜索、人工标注、授权记录。缺素材时可以在授权后调用 MoneyPrinterTurbo 的 Pexels / Pixabay / Coverr 来源。
- **视频工具：** 优先使用 FFmpeg 处理已准备好的本地素材；需要额外的配音和自动成片流程时可按需调用 MoneyPrinterTurbo。素材检索不等于自动精确视觉理解。
- **平台发布：** 五个短视频平台优先采用 `social-auto-upload`；微信公众号、知乎走各自的图文/文章发布能力。默认仅生成待发布内容，不会擅自投稿。
- **数据自主：** 企业知识库独立保存，可导出内容与素材来源索引。外接盘/NAS 原片不会被自动复制进导出包。

**人工审批不可跳过。** 脚本批准、成片验收和真正发帖是不同关口。账号登录、Cookie、MCP 授权、第三方素材许可及 API 费用也需要分别核实；**ChatGPT 订阅额度不等于第三方模型/素材 API 额度**。

## 手动备用安装（正常用户可跳过）

仅在 Agent 无法完成原生 Skill 安装，或需要手动部署时，才下载/复制本项目的完整目录并运行内置引导器；这些脚本**不是安装 Skill 的必要前置步骤**。引导器仍可能需要联网下载工具，因此不承诺断网机器能直接运行。

Windows 10/11：在本目录运行 `SETUP-WINDOWS.cmd`，或使用 PowerShell：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\SETUP-WINDOWS.ps1
```

macOS / Linux（受支持架构）：

```bash
bash ./SETUP-UNIX.sh
```

引导器询问工具目录和知识库目录，将 Python、uv 及可用的基础工具尽量装到指定目录。第三方 Skills、MoneyPrinterTurbo、发布 CLI/MCP 则按需检查、展示安装计划，用户授权后才安装。系统需具备相应的 PowerShell/Bash、HTTPS 下载及解压/校验能力；无法连接分发源时会报错。详细平台支持和具体限制见 [首次使用说明](docs/START_HERE.md)。

## 维护与验收

- AI 定位环境：先从主 Skill 目录读取 Git 忽略的 `config/local-install.json`，核对工作区的 `config/workspace.json`；不能依赖当前终端所在目录。
- AI 检查环境：使用定位到的工作区绝对路径调用 `doctor`。
- AI 安装缺失能力：先运行 `installer` 的预览模式，确认来源/权限后执行。
- 账号与发布测试：必须逐个平台验证，CLI 安装成功不代表可以稳定投稿。
- 知识库、内容成果与来源索引独立于第三方工具；升级 Skill 不应覆盖它们。

工程参考：[素材源管理](docs/MATERIAL_SOURCES.md) · [工具选型](docs/TOOLCHAIN.md) · [内容结构与审批](docs/CONTENT_SCHEMA.md) · [验收矩阵](docs/ACCEPTANCE_V3.md)。

**当前验收边界：** 已验证部分本地脚本、审批与素材索引流程；首次 GitHub Skill 安装、第三方工具联网安装、真实素材下载和七平台账号投稿需在目标用户环境逐项验收，不应称为已全部打通。
