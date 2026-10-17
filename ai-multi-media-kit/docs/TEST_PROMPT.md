# 自动安装/更新与视频生产测试提示词

使用时把 `__OUTPUT_ROOT__` 替换为用户明确指定的成果根目录。主题可以共用，但每个 Agent 必须使用自己的身份和新轮次。测试任务与最终视频要讲的内容不是一回事。

```text
请实际安装或安全更新 ai-multi-media-kit 的最新版本，然后完成一条介绍视频的制作测试，不要只给方案。

源码：
https://github.com/bryce-code-world/skills/tree/main/ai-multi-media-kit

本次唯一成果根目录：
__OUTPUT_ROOT__

一、安装/更新与复用
使用当前 Agent 自身支持的安装方式获取完整 Skill。核对 GitHub main 当前提交及 references/release.json，要求 V0.10.0 或更新版本；已安装时比较版本和必要文件，不以目录存在冒充已更新。保留本机配置和用户改动，不覆盖未知修改。
实际读取 SKILL.md、AGENTS.md、docs/START_HERE.md、docs/CONTENT_SCHEMA.md，以及 docs/examples/ai-multi-media-kit-introduction.md。
先只读检查共享索引与既有 workspace.json。工具目录参考 D:\ai-multi-media-skill；知识库位置以已登记且可访问的配置为准。核对 output_root 与上面的唯一成果根目录一致；不一致时报告冲突，不写入别处或擅自搬迁旧作品。
已有环境直接复用，不重新安装 Python/FFmpeg、不运行整套初始化、不修改系统 PATH。共享运行核心落后时，使用新 Skill 源码里的 upgrade_core.py 先预览，确认只涉及本套件自有文件且无其他 Agent 同时更新核心，再 --apply 备份升级。此任务授权这次安全更新，不需要我额外确认。

二、建立有明确归属的新项目
共同 topic_id 使用 amk-workflow-intro。识别你实际所在的宿主，使用 codex、trae、workbuddy、claude-code 等真实小写标识；模型能核实就必须通过 `--model` 传入真实名称，未知时省略，目录明确显示 `model-unknown`，不得猜测。
用 studio new --topic amk-workflow-intro --agent <你的实际宿主> --model <你核实的实际模型名> --title "从一个选题到一条视频：AI 自动生产工作流" 创建项目（未知模型则省略整组 --model 参数）。新内容目录含 topic、Agent、model_slug、run_id；完整 model_id 在 content.json，工具自动生成 run_id，不走只有 --id 的旧兼容入口。
全部脚本、素材记录、配音、字幕、视频及 TEST-REPORT.md 保存到工具返回的本次独立目录。不要覆盖或修改其他 Agent 的项目。读取历史项目可以用于比较，不把旧成片改名冒充新作。

三、介绍视频的主线
制作45～60秒、9:16、中文配音和中文字幕的真实 MP4，优先1080×1920、至少720×1280。
核心是：这套 Skill 怎样把一个内容需求推进为视频，以及背后的知识库调用、AI策划编稿、审核返工、合法选材、配音/字幕/剪辑、质量检查和可追溯交付机制。
面向个人创作者和小团队。开头讲“写完文案后，素材、配音、字幕和剪辑仍要自己串起来”的问题；主体围绕一个实际制作任务展示过程，不只朗读功能列表。
至少约70%的时长讲视频生产及质量闭环。跨 Agent、共享环境、不重复安装仅作末尾一句辅助优势，不以“换 Agent 必须重装”开场，不把安装日志、路径校验和测试通过数当视频主体。
在 brief 和 editorial_intent 中明确主次。使用真实过程、结果片段或标注清楚的原创示意；避免整条片子只是六页科技流程图。不能把模拟界面叫真实录屏，也不能虚构效率数字、全平台发布或商业成果。

四、发音和实际制作
先选择实际可用、费用和使用权限明确的 TTS 服务/音色；不调用收费 API，不外传企业私有原文或凭据。
写好脚本后执行 studio speech-plan --id <本次ID> --tts-engine <实际服务> --voice <实际音色>。对“重复”等已知风险，按语境改成“反复/再次”等自然表达，同步 narration、分镜 voiceover 和字幕，再 --replace 复检。不能把拼音写进字幕、全局替换单字或擅自向不支持的服务传 SSML。
只用 READY 计划导出的逐镜头文本生成 WAV，再通过 studio voiceover 和 FFmpeg 实际成片，禁止手写 PCM 重采样或强行加速。按真实配音时序生成字幕。
**烧录字幕不准压住主画面内容**：重要正文/图形底边不得超过 72% 画高，字幕独占 76%～92% 画高，两侧留至少 7% 边距，最多两行；基于实际文字 bbox 规划每镜头的 `content_boxes/subtitle_boxes`，运行新 Skill 的 `scripts/subtitle_layout.py --layout <坐标.json>` 进行碰撞预检。此工具检查的是声明坐标，不能代替最终视频查看。
AI 审稿必须检查 focus_alignment；成片实际试听并检查 pronunciation_check、字幕同步、画面和节奏。**必须从最终 MP4 每个含字幕的镜头至少抽取一个字幕正在显示的帧**，确认字幕没有覆盖底部说明/卡片/画面重点，不能只检查字幕内容正确就判 PASS；记录时间点和示例帧。ASR/波形只能辅助，不能代替发音与自然度试听。没有音频输入能力时继续完成能验证的工作，交付真实 MP4 和未验收项，保留 BLOCK/部分完成，不伪造 PASS、不把测试片宣称可发布成片。

五、交付和边界
最多三轮自主返工。除必要身份操作或超出任务授权的行为，不要逐阶段要求我审批。没有素材/工具时优先找已授权免费替代方案，不重新开发整套系统。
本次只制作测试视频：不设置 publish-target，不登录或公开投稿，不改 GitHub 源码，不覆盖旧作品，不同时写同一内容 ID。
最终给出视频绝对路径、内容ID、topic/agent/model/run、使用的Skill版本和提交、原始/改写口播与读音风险记录、真实TTS服务及音色、工程与体验验收证据、失败与未验证项。测试报告放本项目目录下，明确区分“工程通过”“内容主线符合要求”“实际发音/自然度已验证”。
请直接开始真实执行。
```
