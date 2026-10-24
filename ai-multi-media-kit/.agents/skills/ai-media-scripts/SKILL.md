---
name: ai-media-scripts
description: 结合真实用户目标与企业知识库编写短视频主线、口播、分镜和平台文案，区分核心价值与辅助卖点，并配合发音预检与自动返工。
---
# 脚本生产

- 新任务用 `studio new --topic <共同主题> --agent <实际宿主> --title "主题"`；可核实的模型才传 `--model`，自动生成同时含 Agent、模型标识与轮次的内容目录（未知模型标为 `model-unknown`）。别的 Agent 接力用同 topic、新内容 ID 和 `--parent-id`，不覆盖源稿。
- `brief.md` 先写观众、核心用户价值、辅助优势、要展示的真实过程/证据，以及哪些只是工程测试事项。工程测试通过不应自动变成产品宣传主题。产品专用资料按任务读取，不把本 Skill 的安装/复用说明误当成所有产品的核心卖点。
- 正式 `script.json` 包含 `content_id/title/narration/shots/duration_seconds`；需要平台包时再写目标 `platforms` 文案。新项目还须有 `editorial_intent`：`audience`、`primary_value`、`secondary_values`（列表）、`evidence_plan`（非空列表）。这里只检查结构，主线需实际审稿。
- 前 3～5 秒给出观众可感知的问题/结果，主体以一个实际任务的推进、操作或对比证明核心价值，结尾收束。不要默认六张技术卡片、功能列表或口号。真实素材不足时使用标注清楚的示意，不编造产品界面、经验或效果数字。
- 分镜应预先给字幕保留独立安全区：所有重要正文、产品卡片和底部说明不能占用字幕层；文字尺寸、行数和实际 bbox 由渲染时测量，不以 SRT 文字正确代替视觉排版。
- `shots[].voiceover` 是最终送给 TTS 的完整语义段，`narration` 汇总同一文案。字幕显示换行与音频分段独立，规则见根 `docs/QUICK_VIDEO.md` 的“口播、镜头与字幕”；字幕不能漏词或替换成拼音。分镜 seconds 总和与 duration_seconds 一致。
- 用 `studio speech-plan --id <ID> --tts-engine <实际服务> --voice <实际音色>` 检查已知易错词和文案一致性。发现“重复”等风险时自主按上下文改成“反复/再次”等自然表达，同步口播与字幕后 `--replace` 重跑。不能全局替换单个汉字，不能靠改审核结果消除风险。文本预检不是声音验证。
- 随后 `studio hash`，调用 `ai-media-review` 完成当前版本审核；最多三轮内容返工，不请求用户逐稿审批。事实无法核实、付费或越权事项保留阻塞。细节见 `docs/CONTENT_SCHEMA.md`。
