---
name: ai-media-video
description: 使用通过 AI 审核的脚本和合法素材由 FFmpeg/MoneyPrinterTurbo 自动成片、验收、返工，并记录当前内容哈希。
---
# 视频制作 Skill

1. `studio check` 确认脚本 AI 审核通过（`script_ready=valid`），**不需要真人脚本批准**。通过 `materials resolve/preview` 验证已登记素材与画面，必要时裁剪镜头。
2. 优先 `studio render --id <ID> --engine ffmpeg --material-ids <ID1> <ID2> --rights-confirmed`，需要时加 `--audio` 与 `--subtitles`。也可先 dry-run 诊断，但不能把 dry-run 当成最终输出。FFmpeg 不会自动写口播或生成 TTS；用户要求有声讲解时，必须选用已经核实免费且可用的音频方案。
3. MPT 需要先按经验证的免费依赖配置运行，生成的真实 MP4 经 `studio import-video` 重新验收。CLI 成功但没有找到输出文件不代表成片。
4. 使用 ffprobe 校验音视频轨、方向、时长等硬条件。基于真实成片或关键帧核验分镜一致性、字幕、听感、节奏、版权和明显伪影，写入 `video/review.json`，包含成片哈希、脚本哈希、审核标准哈希和全项检查。
5. AI 审核未 PASS 就自主修复并再渲染（`--replace` 只能覆盖本内容 ID 的成片），最多三轮。**不请求真人验片批准**，不得为了通过验收虚构观看视频、音频或场景质量。

成片质量验收绑定最新版本；完成后由 `studio package` 生成待发布包。
