---
name: ai-media-video
description: 将已审核脚本、经过发音预检的 TTS 文本和合法素材合成为真实短视频，验证工程质量与实际视听体验并自动返工。
---
# 视频制作

用户只要求制作或修改单条视频时，使用 [快速制作与定点修改](../../../docs/QUICK_VIDEO.md)：内置 Remotion 模板，video-shotcraft 资源按需选用；实际检查画面与声音，不伪造审核或发布。以下步骤只用于**完整内容生产、审核和正式发布**。

1. 先 `studio check` 核实当前脚本审核，再准备配音。新项目必须先有 `studio speech-plan --id <ID> --tts-engine <实际服务> --voice <实际音色>` 的 READY 记录。它将普通口播逐镜头导出为 `work/tts-inputs/<脚本哈希>/shot-NNN.txt`，只用这些文本合成 WAV。已知多音词风险由 Agent 按语境改稿并同步字幕，不自动把中文替换为拼音，也不假设所有 TTS 支持 SSML/phoneme。
2. 选择已获许可、费用可确认且实际可用的中文 TTS；记录服务/音色。不同音色不能等同不同 Agent 的语言能力。SAPI/Huihui 可作技术回退，不自动代表正式内容质量。`speech-plan` READY 只是已知词风险预检，不保证不存在其他错读。
3. 按镜头顺序将真实 WAV 交给 `studio voiceover --id <ID> --takes ...`。FFmpeg 负责正确重采样与时间轴装配，禁止手写 PCM 插值或加速语音硬塞镜头。输出 `work/narration.wav`、输入音频哈希和绑定当前脚本/发音计划的 `voiceover-check.json`。脚本或音色改变后，重新规划、生成配音，不复用旧音轨。
4. 使用合法素材与 `studio render --id <ID> --audio <本项目/work/narration.wav> --materials ... --rights-confirmed`，或经验证的外部成片再 `import-video`。优先真实制作过程、场景或结果对比；动画辅助讲清事实，不用六页 PPT 卡片掩盖没有故事。
5. **字幕不遮挡画面**：程序化视频要保留字幕专属安全区（关键正文、卡片、图表底边不超过画高 72%，字幕占用画高 76%～92%，两侧各留至少 7%，最多两行）。用文字 bbox/背景矩形的真实坐标制作每镜头 `content_boxes/subtitle_boxes` 清单，运行 `scripts/subtitle_layout.py --layout <JSON路径>` 预检。预检只校验渲染器申报的坐标，不会识别任意 MP4 里的实际内容；仍必须从**最终 MP4 每个有字幕的镜头**抽帧，确认字幕没有盖住正文、卡片、底部注释和手机外框。不能仅凭字幕可读、SRT 同步就写“无遮挡 PASS”。
6. 技术门禁会从最终 MP4 解码音轨，检测时长、有效声音与异常静音；这不是读音/语义检查。Agent 必须实际试听最终音频并查看镜头、字幕时序和末尾画面，特别核对多音词、品牌英文名、数字及停顿。新项目在 `video/review.json` 写入 `pronunciation_check`，方法为 `actual_audio_review`，包含真实时间段、听到的结果和当前 `speech_plan_sha256`。ASR 和波形仅可作辅助，不能伪装成试听；格式见 `docs/CONTENT_SCHEMA.md`。
7. 没有音频输入能力时，仍可生成测试 MP4、运行工程检查并交付已有结果，但必须标明发音/自然度未验证，保留 BLOCK，不能伪造 PASS 后打包。最多三轮自主返工，不请求用户逐稿/逐片审批，不把后台安装或测试参数写成视频主体。

`studio package` 仅对质量检查通过的当前版本生成平台包，并附带 Agent/主题/轮次归属及建议导出文件名。默认不发布，版权、外部服务费用和原始任务授权边界不变。
