---
name: ai-media-studio
description: 在已初始化的 AI Media Studio 工作区组织一次任务授权下的选题、脚本、AI 审核返工、合法素材、视频合成、质量验收、平台包和已授权发布。
---

# 媒体生产主编排

先读根目录 `AGENTS.md` 与 `config/workspace.json`，核对企业知识库、宿主本机执行权限及目标交付。使用工作区绝对路径调用 `RUN-STUDIO-WINDOWS.ps1` / `run-studio.sh`，无须系统级 PATH。

1. **只在起点解释一次任务范围**。用户要求制作即授权完整生产链；默认不能公开发布。若用户原始请求明确指定平台与账号，`studio new` 传 `--publish-target platform:account` 并按可用性传 `--task-ref`，之后不需要为脚本、成片或该范围内投稿重复审批。原始请求未指定的范围一律不得推断补写。
2. 调用 `ai-media-topics` 与 `ai-media-scripts` 生成 `script.json`，`ai-media-review` 生成当前哈希绑定的 `review.json`。仅 PASS 且无待核事实可继续，否则自主查证或修正，最多 3 轮，不请求用户读稿。
3. 调用 `ai-media-materials` 从授权素材源匹配镜头并核验许可、画面；没有素材优先改镜头和选择免费合法来源，不能为了过审谎称素材已授权。
4. 调用 `ai-media-video` 以成熟 TTS + `studio voiceover`（FFmpeg 装配）+ FFmpeg/MPT 制作真实成片，禁止临时手写重采样。`studio check/package` 会重算真实音轨质量，不相信 AI 自报 PASS。AI 另需实际试听与查看首/中/尾画面，审查吸引力、叙事、字幕、自然发音、节奏和非 PPT 化的视觉表达；未达标自动返工最多 3 轮。不请用户验片批准，但没有审看能力不得伪造通过。
5. 通过 `studio package` 生成发布包；只有真实初始任务授权的平台及账号才可 `studio publish --execute`。缺少平台登录时通知用户完成扫码/验证码，成功后续跑；缺少可靠投稿工具或作品链接时如实报告，不能假称已发布。上传未知状态不得重复盲发。

`studio check/status` 显示当前版本的脚本/成片质量门禁。AI 审核不得伪造 PASS；工具、素材、额度或平台不可用时说清阻塞，不交还不必要的人工质量审查。

子 Skill 根据阶段读取 `.agents/skills/ai-media-*/SKILL.md`；内容结构见 `docs/CONTENT_SCHEMA.md`。
