---
name: ai-media-studio
description: 在已初始化工作区执行需要企业知识库、脚本审核、平台包或授权发布的完整视频生产流程；单条快速制作与定点修改使用主 Skill 的快速路线。
---
# 内容生产主编排

先核对工作区 `config/workspace.json`；环境和协作约束见根 `AGENTS.md`，状态与质量字段以根 `docs/CONTENT_SCHEMA.md` 为准。单条制作与定点修改转到根 `docs/QUICK_VIDEO.md`，不要求先经过本流程。

1. 从用户任务固定核心价值、次级卖点、展示证据和发布边界，生成 brief；仅制作不获得发布权限。
2. 用 `studio new --topic <共用主题> --agent <实际宿主> --title "主题"` 新建独立运行目录，已知模型传 `--model`，未知则省略、不猜测。接力用 `--parent-id` 记录来源哈希，不修改其他 Agent 的目录；`studio list --topic` 用于对比。
3. 按任务读取 ai-media-topics/ai-media-scripts 编稿，填 editorial_intent。选择实际可用的 TTS 服务与音色，执行 speech-plan；按上下文处理已知读音风险，同步口播、字幕后重跑至 READY。
4. 按 ai-media-review 审核稳定脚本及主次对齐。使用 READY 导出的完整语义段生成 WAV，再由 voiceover 装配。改稿后更新计划和审核；原始音频的复用条件见根 docs/CONTENT_SCHEMA.md，不因画面调整重做全部 TTS。
5. 按需读取 ai-media-materials 核对合法素材，由 ai-media-video 制作真实 MP4。工程检查、画面检查和实际试听分别完成；pronunciation_check 需有真实时间点证据，ASR 不能取代试听，能力不足保留未验收状态。
6. 当前版本全部审核通过再 package；公开发布按初始指定平台与账号范围执行。无需逐阶段人工审批，最多三轮返工。具体质量与发布约束不在此重复，按根 docs/CONTENT_SCHEMA.md 执行。

所有正式成果存放 output_root 下当前含 Agent 标识的内容 ID；执行命令用既有工作区绝对路径。先复用环境，不重复初始化。仅本套件介绍任务按需读根 docs/examples/ai-multi-media-kit-introduction.md，其他主题不加载该定位。
