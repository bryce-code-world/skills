# 跨 Agent 兼容、授权边界与实测等级

本 Skill 使用开放的 [Agent Skills](https://agentskills.io/specification) 目录格式，适用于能读取 `SKILL.md` 的 Agent，但**不保证**每种客户端都拥有本地文件、Shell、账号或浏览器能力。对于 Codex、Claude Code、WorkBuddy、Grok、千问办公、豆包等宿主都要按**当前具体版本**实测，不能凭品牌名宣称支持。

| 宿主实际可用能力 | 可以做什么 | 不能冒充 |
| --- | --- | --- |
| 仅 Skill/聊天 | 选题、脚本、基于已提供证据的文本审查 | 本地环境已经安装、视频或平台发布已完成 |
| 还可读写本机和执行命令 | 初始化或复用共享工作区、使用自有 Python/FFmpeg/素材 CLI，完成真实 MP4 和发布包 | 自动拥有第三方素材许可、TTS/模型额度或平台账号 |
| 另有已验证的外部网络与平台登录权限 | 按用户初始任务限定的平台/账号执行受支持的发布工具并核查链接 | 任意平台账号都能发布、CLI 退出码 0 就是发布成功 |

隔离的云电脑不自动等于用户本机 Windows 的 `D:\`，也不继承私人 NAS 或账号登录态。缺少能力时交付可核实的部分，不虚构功能。

## Skill 安装与工作区复用

使用**当前宿主自己**的 Skill 安装/导入或完整目录复制，不强制 Codex 或 Claude 专属安装目录。主 `SKILL.md` 为统一入口；初始化工作区内 `.agents/skills/ai-media-*/SKILL.md` 是业务子 Skill，宿主不能自动发现时按阶段直接读取，无需修改系统 Skill 路径。

工具目录和企业知识库目录由用户选定且不得互相嵌套。运行对应的 `SETUP-WINDOWS.ps1` / `SETUP-UNIX.sh`，不改系统 PATH。首次成功后在同一系统用户的本机共享索引中记路径：

- Windows：`%LOCALAPPDATA%\ai-multi-media-kit\local-install.json`
- macOS / Linux：`${XDG_CONFIG_HOME:-~/.config}/ai-multi-media-kit/local-install.json`

每次需与 `<install_root>/config/workspace.json`、企业知识库校验。旧版主 Skill 的 `config/local-install.json` 仅供共享索引缺失时回退；索引损坏或路径不符时停止询问原路径，不静默迁移或重复安装用户资产。独立 Agent 在同设备、同系统用户及可访问本地文件时才可复用，索引不是云同步。

## 自动执行的授权

用户明确提出**制作视频**的任务，允许 Agent 在该任务内自主选题、脚本、AI 审核、合法免费选材、成片及迭代，不因每一阶段的质量或工具计划重复索取批准。

只有原始任务明确指定**公开发布的平台及账号**，Agent 才可在创建内容时记录 `studio new --publish-target platform:account`。这不是任意未来发布权限；内容 ID、平台、账号严格绑定。Agent 不能将“账号已登录”“请准备发布包”或模糊回答解释为公开发布授权，不能编造用户请求或扩大范围。CLI 不能独立辨认原话作者，宿主必须保证指令确实来自用户。

在该范围内，`studio publish --execute` 不要求第二次终端/对话审批。只在用户必须操作的平台登录、扫码、验证码时暂停。拒绝未经核实许可的素材、收费或不确定计费 API、未知外部安装；自主切换免费方案或报告阻塞，不将质量审查交给用户。状态未知不能重试盲发。

## 哪些功能仍为宿主专用

- `start-codex.*` 仅是 Codex CLI 可选入口，不影响其它宿主。
- `scripts/configure_mcp.py` 只适配 Codex 项目级 `.codex/config.toml`，其它宿主应使用自己的 MCP 注册和权限方式。
- `RUN-STUDIO-WINDOWS.ps1`、`run-studio.sh`、`scripts/studio.py`、`scripts/materials.py` 是系统级本地工具，可供兼容 Agent 调用。
- `doctor` 只做本地结构及依赖检查，不代表 AI 审核质量、账号已登录、MPT 成片或真实发布经过验收。真实作品必须具备可核对的 MP4/发布状态证据。
