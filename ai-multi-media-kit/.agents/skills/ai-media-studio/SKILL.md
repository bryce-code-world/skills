---
name: ai-media-studio
description: 在已初始化工作区组织从目标理解、策划编稿、读音预检、审核返工、素材和视频合成到质量验收与交付的可追溯流程。
---
# 内容生产主编排

先读取本工作区 AGENTS.md、config/workspace.json 与 docs/CONTENT_SCHEMA.md。AI Agent 是策划者、编导、工具调度者和质量审核者；Skill 是业务流程与约束；TTS/FFmpeg/CLI/MCP 才执行具体操作。环境复用是基础设施能力，不是所有产品视频的默认主线。

1. 从用户任务固定核心价值、次级卖点、展示证据和发布边界，生成 brief；仅制作不获得发布权限。
2. 用 `studio new --topic <共用主题> --agent <实际宿主> --title "主题"` 新建独立运行目录，模型可核实才传 --model。接力用 --parent-id 记录来源哈希，不修改其他 Agent 的目录。studio list --topic 用于对比。
3. 按 ai-media-topics/scripts 编稿，填 editorial_intent。按 ai-media-review 审查主次对齐并记录 focus_alignment；这是语义判断，不是填字段就算通过。
4. 选择实际可用的 TTS 服务与音色，执行 speech-plan。遇到已知多音词风险自动按语境改稿、同步字幕并重跑。READY 后使用导出的逐镜头文本生成 WAV，再 voiceover 交给 FFmpeg 装配。此流程不声称词典能解决所有中文读音。
5. ai-media-materials 核对合法素材，ai-media-video 制作真实 MP4，工程检查之外实际试听和查看画面。pronunciation_check 需有真实时间点证据，ASR 不能取代试听；能力不足保留 BLOCK/部分完成，不虚构验收。
6. 审核通过再 package，发布仅限初始明确指定的平台和账号。无需用户逐阶段审批，最多三轮返工。身份操作、越权与收费边界遵守 AGENTS.md。

所有正式成果存放 output_root 下当前含 Agent 标识的内容 ID；执行命令用既有工作区绝对路径。先复用环境，不重复初始化。产品自身介绍任务可按需读 docs/examples/ai-multi-media-kit-introduction.md，其他主题不要加载该专用定位。
