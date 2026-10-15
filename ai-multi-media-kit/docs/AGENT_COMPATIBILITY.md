# AI Agent 兼容与运行边界

本 Skill 使用 [Agent Skills](https://agentskills.io/specification) 的 `SKILL.md` 目录格式；**不绑定模型、Agent 品牌、聊天订阅或特定插件框架**。一个宿主是否能使用完整功能，取决于该产品及版本开放了哪些工具能力，不由能否识别 `SKILL.md` 单独决定。无论用户使用 Codex、Claude、Grok、WorkBuddy、千问办公、豆包或其他产品，都应核实**当前具体客户端/版本**的 Skill 发现、文件系统和命令执行权限，不能仅凭产品名称宣称已适配。

## 三档能力

| 当前 Agent 能力 | 本 Skill 能完成什么 | 不应宣称 |
| --- | --- | --- |
| 只支持加载 `SKILL.md`、聊天/文档生成 | 讨论选题、创作脚本、解释流程；若用户提供材料可做文本审核 | 本地环境已安装、真实视频已合成或已投稿 |
| 另有本机文件读写 + 终端命令执行（含 Windows PowerShell 或 Linux/macOS Bash） | 调用内置引导器、自有 Python、FFmpeg 和素材索引工具；记录审核及准备发布包 | 第三方素材/API 或媒体账号可用，除非实际验证 |
| 另有经授权的网络/登录/媒体发布能力 | 在对应平台完成独立验证后尝试上传，并检查真实返回状态 | 所有平台通用、CLI 返回 0 就代表发布成功 |

仅能访问隔离云电脑/容器的 Agent 不能自行访问用户 Windows 的 `D:\` 盘、私人 NAS 或登录态。此时优先在该宿主**实际可访问的文件系统**内完成文字任务，或要求用户在拥有执行权限的本地 Agent 中完成后续操作。不要用聊天工具、插件名或模型名推断本地权限。

## 安装约定

把 GitHub Skill 目录链接交给当前 Agent，请它**使用自身支持的安装方式**（原生 Skill 安装器、导入或完整复制）取得 `SKILL.md` 连同 `scripts/`、`docs/`、`knowledge-templates/`、`.agents/skills/` 等资源。每种宿主的 Skill 安装目录与命令不同，**不要强制使用 Codex 或 Claude 的专有目录**。若只能读取文档但无法执行脚本，停止在文本方案。

主 `SKILL.md` 是跨 Agent 的唯一通用入口；初始化工作区内的 `.agents/skills/ai-media-*/SKILL.md` 是分阶段的业务子 Skill。宿主不发现嵌套子 Skill 时，主 Agent 按工作阶段直接读取对应文件，不要求改写系统 Skill 搜索路径或重复安装全部子 Skill。已安装并验证的现成第三方技能优先复用。

## 首次初始化与跨 Agent 共享路径

用户只需指定一次**工具目录**和**企业知识库目录**，均由用户掌控，且不互相嵌套。宿主执行对应 `SETUP-WINDOWS.ps1` 或 `SETUP-UNIX.sh`，自动准备套件内的 Python/uv/FFmpeg（平台不支持的工具须另行处理）。不会修改系统 PATH。联网安装依赖前应展示来源、权限与费用，并遵循用户授权。

首次成功完成后，共享定位索引仅保存路径信息：

- Windows：`%LOCALAPPDATA%\ai-multi-media-kit\local-install.json`
- macOS / Linux：`${XDG_CONFIG_HOME:-~/.config}/ai-multi-media-kit/local-install.json`

路径是 **每台设备、每位操作系统用户** 的本机配置，不是 Agent 云端同步服务；这份小型元数据可能位于系统盘，但 Python、FFmpeg、缓存和企业内容依然优先在用户选择的位置。不同 Agent 需要以**同一用户身份和相同本机文件访问权限**运行，才能共享它。旧版主 Skill 目录的 `config/local-install.json` 仅作为缺少共享记录时的兼容回退；不要将任何一种索引上传 Git 或生成工作区副本。

新会话使用前，读取共享索引并核对 `<install_root>/config/workspace.json`、`knowledge_root`；再以绝对路径调用工作区启动器。若路径失效，**停止并请用户提供现有工具目录**；不全盘扫描、不自动安装到新位置、不修改或迁移自有资料。可通过已有工作区的 Python 执行 `scripts/workspace_locator.py register --install-root <原工具目录>` 重登记；`show` 为只读验证。没有 Python 的 Agent 也可用自己的本地文件读取能力直接读取这两份 JSON。

## 哪些能力有专属适配

- `start-codex.cmd`、`start-codex.sh` 仅为 **Codex CLI 的可选便捷入口**，不是主运行入口，也不要求其他 Agent 安装 Codex。
- `scripts/configure_mcp.py` 当前只生成 **Codex 项目级** `.codex/config.toml`，其他 Agent 必须按自己支持的 MCP 配置格式注册、授权并验证连接，不能直接复用该 TOML。
- `RUN-STUDIO-WINDOWS.ps1`、`run-studio.sh`、`scripts/studio.py`、`scripts/materials.py` 等是**操作系统工具**，不属于某家模型或 Agent。按本机能力执行。
- 无论宿主是谁，审批决定都必须来自真人。用户在对话中明确批准**当前内容 ID、阶段及必要的平台账号**后，Agent 才能原样引用该用户消息，通过 `studio approve --chat-message` 写入带哈希的审批记录；CLI 只核验字面匹配，无法独立证明消息确实出自用户，宿主必须先确认原始用户轮次。不得伪造、代写或推断授权。旧终端 `APPROVE` 仍兼容，实际投稿 `PUBLISH` 二次交互确认不变。未验证授权的素材、第三方收费 API 和平台投稿均禁止静默执行。

## 验收口径

区分 `SKILL.md` 已被发现、当前 Agent 已能读取知识库、内置本地工具已验证、第三方 CLI/MCP 已验证、目标媒体账号已真正验收五种状态。当前仅对本地脚本提供回归测试；不同厂商的 Agent 需在其真实运行版本验证 Skill 发现、工具调用和沙箱权限，不把某个 Agent 的成功推广到所有客户端。
