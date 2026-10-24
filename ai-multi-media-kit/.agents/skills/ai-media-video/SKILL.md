---
name: ai-media-video
description: 将已审核脚本、经过发音预检的 TTS 文本和合法素材合成为真实短视频，验证工程质量与实际视听体验并自动返工。
---
# 视频制作

用户只要求制作或修改单条视频时，使用 [快速制作与定点修改](../../../docs/QUICK_VIDEO.md)：内置 Remotion 模板，video-shotcraft 资源按需选用；实际检查画面与声音，不伪造审核或发布。以下步骤只用于**完整内容生产、审核和正式发布**。

1. 先 `studio check` 核实当前脚本审核。新项目用 `studio speech-plan --id <ID> --tts-engine <实际服务> --voice <实际音色>` 准备文本，再使用 READY 导出的完整语义段合成 WAV。先验收代表句和相邻句衔接，分段与字幕原则见根 `docs/QUICK_VIDEO.md`。
2. 选择已获许可、费用可确认且实际可用的中文 TTS；记录服务/音色。不同音色不能等同不同 Agent 的语言能力。SAPI/Huihui 可作技术回退，不自动代表正式内容质量。`speech-plan` READY 只是已知词风险预检，不保证不存在其他错读。
3. 优先使用 READY 的完整连续口播文本生成一份 WAV，交给 `studio voiceover --id <ID> --continuous --takes <完整旁白.wav>`，可跨多个画面镜头不断句；真正需要分段时才保留旧 `--takes ...`。由 FFmpeg 重采样和装配，不加速硬塞。只改画面或时长时复用未变的原始 take，更新计划与装配报告；完整语义段需要切换画面时在同一分镜内完成。版本绑定与复用条件见根 `docs/CONTENT_SCHEMA.md`。
4. 使用合法素材与 `studio render --id <ID> --audio <本项目/02-媒体素材/配音/完整旁白.wav> --materials ... --rights-confirmed`，或经验证的外部成片再 `import-video`。优先真实制作过程、场景或结果对比；动画辅助讲清事实，不用六页 PPT 卡片掩盖没有故事。
5. 按根 `docs/CONTENT_SCHEMA.md` 预留字幕区、测量实际文字并运行 `subtitle_layout.py`。声明坐标的预检不能代替最终 MP4 检查：各镜头首/中/尾和含字幕帧要核对遮挡、词语断行、动画中间态及手机可读性。
6. 技术门禁检查时长、有效声音与异常静音，不判断停顿是否自然。实际试听并核对字幕时序，新项目在 `99-专业工程/video/review.json` 记录问题时间段与当前版本绑定；格式见根 `docs/CONTENT_SCHEMA.md`。不另建重复的逐镜 PASS 表，也不把 ASR 当试听。
7. 没有音频输入能力时，仍可生成测试 MP4、运行工程检查并交付已有结果，但必须标明发音/自然度未验证，保留 BLOCK，不能伪造 PASS 后打包。最多三轮自主返工，不请求用户逐稿/逐片审批，不把后台安装或测试参数写成视频主体。

`studio package` 仅对质量检查通过的当前版本生成平台包，并附带 Agent/主题/轮次归属及建议导出文件名。默认不发布，版权、外部服务费用和原始任务授权边界不变。
