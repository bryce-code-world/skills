---
name: ai-multi-media-kit
description: 根据用户内容目标与企业知识库，自动完成短视频选题、脚本、审核返工、素材匹配、配音字幕、视频合成、质量检查和交付；支持任务归属追踪、易错读音预检及共享本地环境。仅在初始用户任务明确授权的平台和账号范围内发布。
---

# AI 短视频自动化生产 Skill

**核心是视频生产工作流，不是安装工具或展示多 Agent 复用。** 当前 AI Agent 负责理解目标、策划/编稿、分镜、工具选择和质量判断；本 Skill 提供方法与可追溯流程；TTS、FFmpeg、CLI/MCP 等执行具体操作。工具执行成功不代表内容质量合格。先读 [AGENTS.md](AGENTS.md)，按宿主实际文件、终端和视听能力执行。

## 内容生产

1. 从真实用户任务区分“观众要了解的核心价值”和“本次工程测试项”。在 `brief.md` 中明确目标受众、主线、次级优势与证据展示；测试安装、路径复用不自动成为视频的宣传主线。通用 Skill 不替所有产品固定卖点。只有本次明确介绍本套件时，才参考 [套件介绍样例定位](docs/examples/ai-multi-media-kit-introduction.md)。
2. **新项目必须有归属**：`studio new --topic <共同主题> --agent <当前实际宿主> --title "主题"` 自动生成 `<topic>-<agent>-<run_id>` 目录。模型能核实才传 `--model`，不能猜。用 `studio list --topic <主题>` 对比成果。协作接力用 `--parent-id <来源ID>` 新建独立轮次并记录源哈希，不覆盖另一 Agent 的项目；不并发写同一 ID。旧 `--id` 仅用于兼容，不作为新任务默认入口。
3. 结合知识库调用 `ai-media-topics/scripts`，形成正式 `script.json` 和 `editorial_intent`。先由 `studio speech-plan --id <ID> --tts-engine <实际服务> --voice <实际音色>` 检查口播、字幕一致性及已知易错词。出现风险则由 Agent 在保持原义的前提下改写正式口播/字幕后重跑；不得将拼音或不受支持的 SSML 塞进最终字幕/TTS，也不逐字全局替换多音字。
4. 调用 `ai-media-review`，检查 `focus_alignment`：主线是否对应核心价值、次级卖点是否喧宾夺主。`review.json` 必须与当前脚本、审核标准绑定。AI 未通过就自行修正，最多三轮，不请求用户逐阶段读稿审批。语义对齐需要真实审稿，CLI 仅验证结构与记录。
5. `speech-plan` READY 后只使用其导出的逐镜头文本生成 TTS WAV；`studio voiceover --takes ...` 交给 FFmpeg 正确重采样、配时并记录音色与输入哈希。预检只覆盖已知词典，**不是所有汉字的发音验证**。优先真实操作/使用场景/结果对比和合法素材，不默认把流程图/PPT 当成吸引人的视频。
6. `studio render` 或 `import-video` 生成真实 MP4，自动检查时长、音轨有效声音与长静音。Agent 另需实际查看镜头/字幕并试听配音，在 `video/review.json` 写入有时间点的 `pronunciation_check`。ASR/波形/无静音不能充当试听证明；无音频输入能力时保留未验证状态、交付技术测试结果，不编造 PASS。无需真人阶段批准。
7. 全部质量检查通过才 `studio package`。`content.json`、渲染记录、配音记录和发布包保留主题、Agent、模型（未知为 null）、轮次及来源信息。用户仅要求制作/测试时不设置 `publish_targets`，不登录或投稿；公开发布必须来自初始用户任务明确的平台/账号授权，详情见 [内容契约](docs/CONTENT_SCHEMA.md)。

## 环境是执行条件，不是默认创作主题

- 同设备/系统用户，先只读检查共享安装索引和 `workspace.json` 的三个路径；有效则直接复用，不再次初始化或安装 Python/FFmpeg。共享索引缺失时凭已有工具路径 `workspace_locator.py inspect/register` 恢复；损坏或路径冲突时停止，不擅自新建第二环境。
- 只有确无既有环境才按用户指定工具、知识库、成果目录首次安装。已有源码更新应使用**新源码**的 `upgrade_core.py --root <工具目录> --apply` 备份更新自有核心，不覆盖用户修改、资料、配置和旧视频。操作细则见 [首次使用](docs/START_HERE.md)。
- Windows 以绝对路径调用 `<install_root>/RUN-STUDIO-WINDOWS.ps1 -Task studio|materials|doctor|installer ...`；Unix 使用 `bash <install_root>/run-studio.sh ...`。不修改系统 PATH，不重复安装。仅补齐任务必需、来源和费用已核实的缺失依赖。
- 仅登录/验证码等用户身份步骤需要本人处理；超出授权、收费、隐私外传和无许可素材不能因“自动化”而放行。具体宿主权限、MCP 注册及音频输入支持需分别验证。

成果根目录只取 `workspace.json.output_root`。每个新项目使用自己的归属 ID；不得在 Skill 源码、临时目录或另一个 Agent 的项目中放正式作品。批量选题使用 `_plans/<date>-<agent>-<run>-topics.*` 避免互相覆盖。业务子 Skills 位于 `.agents/skills/ai-media-*/SKILL.md`，按阶段读取。参见 [内容与发音协议](docs/CONTENT_SCHEMA.md)、[工具链](docs/TOOLCHAIN.md)、[验收](docs/ACCEPTANCE_V3.md)。
