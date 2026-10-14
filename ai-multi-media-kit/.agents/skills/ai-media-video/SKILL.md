---
name: ai-media-video
description: 将已审核的短视频脚本、经过来源与授权核对的本地/企业/NAS/网上补充素材，通过 FFmpeg 或 MoneyPrinterTurbo 组合成竖屏成片，并保留素材使用记录。
---

# 视频制作 Skill

- 先用 `studio check` 核验脚本 AI 审核及真人批准。素材由 `ai-media-materials` 提供，详见 `docs/MATERIAL_SOURCES.md`；不要将 MoneyPrinterTurbo 当作唯一素材源。
- 按分镜查找本地素材：`materials scan` -> `materials search --query <关键词>` -> 必要时 `materials preview --id <素材ID>` 并由 Codex/人工核对画面 -> `materials annotate` 记录描述/授权。
- 优先以 `studio render --id <内容ID> --engine ffmpeg --material-ids <ID1> <ID2> --rights-confirmed --dry-run` 检查计划，确认后移除 `--dry-run` 执行。索引已变化、授权未核实或素材丢失时会拒绝执行；原有 `--materials <file1> <file2>` 仍可处理临时视频。
- 本地 FFmpeg 适合剪辑已有真实片段：`--audio <voice.mp3>` 和 `--subtitles <captions.srt>` 可选。未提供配音音频时为静音，不可声称“自动 AI 配音”。当前默认拼接整个片段，精确镜头裁剪需先用确定性工具准备片段。
- 如果需要 MPT 配音和成片：使用 `studio render --engine mpt`，默认依旧从已确认的**本地**素材导入；MPT 生成的结果需用 `studio import-video` 纳入受控工作区。不能把退出码当成作品验收。
- 如果缺少素材，按用户同意使用 `materials fetch-online`，仅执行到 MPT 的 `materials` 阶段，然后核对实际视频/授权并导入本地索引。未经允许不调用付费 API、不调用可灵/即梦等外部生成服务，不自动投稿。
- 最后按 `studio approve --stage video` 由用户自己人工验片并确认。代码不能代填确认口令。

Windows 命令统一使用 `RUN-STUDIO-WINDOWS.ps1 -Task materials/studio ...`，Linux/macOS 使用 `bash ./run-studio.sh materials/studio ...`，无需预装系统 Python。
