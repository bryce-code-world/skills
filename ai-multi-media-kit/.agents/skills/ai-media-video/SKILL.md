---
name: ai-media-video
description: 把人工批准的短视频脚本结合有授权的本地素材，通过 FFmpeg CLI 或 MoneyPrinterTurbo 生成 9:16 视频、字幕和配音。
---
# 视频制作 Skill

- 先用 `studio check` 验证脚本已审核且已人工批准；检查素材本地路径及来源授权。未经批准拒绝任何视频生成。
- 优先选择可复现的 FFmpeg CLI，适用于用户已有实际镜头和配音音频。命令：`python scripts/studio.py --root . render --id <id> --engine ffmpeg --materials <video1.mp4> <video2.mp4> --audio <voice.mp3> --subtitles <captions.srt> --rights-confirmed`。
- 未提供音频时，FFmpeg 输出静音视频；不能声称自动生成配音。可使用 MPT `--engine mpt`，优先用本地素材和 Codex 的现成口播稿，Edge TTS 无单独 API Key，但需要对上游实际环境进行测试。
- MPT 输出可能保存在第三方存储目录。找到实际成片后用 `studio import-video --id <id> --file <path>` 导入工作区。不能把 MPT 命令退出码直接当作已生成作品。
- FFmpeg 字幕脚本需为 UTF-8 SRT；有权使用的音乐/音频才可使用。自动镜头切割不等于语义匹配，建议人工验片。
- 成片完成后请用户自己运行 `approve --stage video`，再准备七个平台内容。
