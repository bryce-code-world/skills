---
name: ai-media-studio
description: 面向兼容 Agent Skills 的 AI Agent，在已初始化 AI Media Studio 工作区中协同企业知识库、选题、脚本审核、素材、FFmpeg/MoneyPrinterTurbo 成片和中国七平台待发布包；需要管理内容生产和审核闸门时使用。
---

# AI Media Studio — 工作区主编排

本工作区不依赖某家 AI Agent。先阅读根目录 `AGENTS.md` 与 `config/workspace.json`，确认根路径和 `knowledge_root`、宿主是否具备本地文件与终端权限。当前宿主若只会生成文本，停止在可核实的选题/脚本建议，不能声称本地视频或平台上传已完成。Agent 兼容说明见 `docs/AGENT_COMPATIBILITY.md`。

- 运行自有脚本使用工作区绝对路径：Windows `RUN-STUDIO-WINDOWS.ps1 -Task ...`；macOS/Linux `bash run-studio.sh ...`。不要要求全局 Python、uv、Git 或修改系统 PATH。
- 从当前企业知识库读取品牌、受众、方法、审核标准与历史数据。内部子 Skill 位于 `.agents/skills/ai-media-*/SKILL.md`；当前 Agent 不发现这些子 Skill 时按任务阶段直接读取对应文件。
- 选题与脚本由**当前具备相应能力的 AI Agent**完成：`ai-media-topics` → `ai-media-scripts` → `studio new` → `script.json`；不得生成无法核对的营销效果或原创事实。
- 通过 `studio hash` 和 `ai-media-review` 生成 `review.json`，然后 `studio check`。只有审核 PASS 且没有待核事实时才请用户审批。真人可直接在当前对话明确批准指定内容 ID 的脚本，由 Agent 原样传入 `studio approve --stage script --chat-message <用户原话> --who <用户别名>` 记录；未经真人明确表态不能生成审批，亦不能替用户输入终端确认短语。
- 使用 `ai-media-materials` 检索自有本地/NAS/临时素材并核验画面、授权；未满足需求时按用户同意用已验证的外部素材 CLI，不擅自调用付费模型、TTS 或受保护视频资源。
- 使用 `ai-media-video` 和 `studio render --material-ids` / `--materials` 成片。完整视频生成后请用户本人验片并在对话中明确批准成片，Agent 才可按真实用户原话登记 `studio approve --stage video --chat-message ...`；未批准不得进入可发布状态。
- 使用 `studio package` 生成七平台发布包；`ai-media-publish` 只在用户针对平台、账号与版本单独批准后尝试投稿。未核实真实公开作品链接前不得标为成功，遇到未知上传状态不得盲重试。
- 审核、脚本、视频、平台包哈希必须对应当前版本。无法执行本地操作、登录或验证时报告准确阻塞并保留数据，不伪装成已完成业务。

工具选型和媒体结构详见 `docs/CONTENT_SCHEMA.md`、`docs/TOOLCHAIN.md`、`docs/MATERIAL_SOURCES.md`。Codex 的 `start-codex.*` 和 `.codex/config.toml` 注册仅是可选专用路径，其他 Agent 不需要。
