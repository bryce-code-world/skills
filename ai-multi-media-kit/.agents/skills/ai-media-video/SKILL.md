---
name: ai-media-video
description: 使用通过 AI 审核的脚本和合法素材由 FFmpeg/MoneyPrinterTurbo 自动成片、验收、返工，并记录当前内容哈希。
---
# 视频制作 Skill

1. `studio check` 确认脚本 AI 审核通过（`script_ready=valid`），**不需要真人脚本批准**。通过 `materials resolve/preview` 验证已登记素材与画面，必要时裁剪镜头。
2. 有中文口播时，先比较宿主已验证的免费/已获授权 TTS 的**自然度、停顿、中文和英文词发音**，选择实际听感更好的；Windows SAPI/Huihui 只能作为技术回退，不能仅因免费且能发声便判定成片级质量。任一 TTS 均可生成逐镜头 WAV，但**禁止自己写重采样、线性插值或改变 PCM 播放速度**。统一使用 `studio voiceover --id <ID> --takes <镜头1.wav> <镜头2.wav> ...` 由 FFmpeg 重采样与装配，保存 `work/narration.wav` 和音频检测报告；槽位容不下就修改口播/时长，不得强制加速硬塞。随后 `studio render --id <ID> --engine ffmpeg --material-ids <ID1> ... --audio <output_root>/<ID>/work/narration.wav --rights-confirmed` 真实成片，字幕应基于实际配音时序校准。dry-run 不算成片。
3. MPT 需要先按经验证的免费依赖配置运行，生成的真实 MP4 经 `studio import-video` 重新验收。CLI 成功但没有找到输出文件不代表成片。
4. `studio render/import-video/check/package` 的音频技术检查会独立解码 MP4 并按分镜检查有效发声比例与异常长静音，**即便 AI 审核写 PASS 也不可绕过**。这只能识别严重静音/节奏错误，不能证明说的是人话或语音自然。Agent 还必须实际试听成片音轨，抽看每个章节开头、中间、结尾的真实画面（关注最后一幕是否空白/过场过长），核对配音清晰度、发音、情绪、字幕同步、音量、真实操作/案例与镜头变化，记录时间点和具体证据到 `video/review.json`。没有试听能力时不得声称“配音自然”“音画一致”已通过。
5. PPT/纯几何图形只能做必要辅助，不得默认代替真实操作演示；优先使用可授权的屏幕录制、实拍、结果对比和富有叙事目的的动态场景。无素材/无高质量 TTS 可用时，明确交付“技术演示”并保留体验质量问题，不写成可发布成片。
6. AI 审核未 PASS 就自主修复并再渲染（`--replace` 只能覆盖本内容 ID 的成片），最多三轮。**不请求真人验片批准**，不得为了通过验收虚构观看视频、音频或场景质量。

成片质量验收绑定最新版本；完成后由 `studio package` 生成待发布包。
