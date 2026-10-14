---
name: ai-media-scripts
description: 根据企业知识库和已确认选题生成可审核的中文短视频口播稿、分镜、镜头素材需求以及七个平台差异化标题和标签。
---
# 脚本生产 Skill

优先结合 `copywriting`、`social`、`video` 等已经安装的优秀 Skill 方法，输出符合 `docs/CONTENT_SCHEMA.md` 的 `script.json`。

- 使用 `python scripts/studio.py --root . new --id <ID> --title "主题"` 建立不可覆盖的任务目录。
- `script.json` 必须具备 `content_id`、`title`、`narration`、`shots`、`duration_seconds`、`platforms`（7 平台，每个平台 title/tags/description）、`article_markdown`。
- 每个镜头有真实可拍/可检索的 `visual`，不要把没有来源的版权素材描述成已获授权。
- 提供开头 3 秒钩子、中段信息密度、结尾互动/行动建议；主题涉及健康、财经、法律、政策时核对实时资料并注明证据。
- 对公众号/知乎，先给出文章衍生稿；不要假装它们支持同样的短视频直传工具。
- 生成完先运行 `studio hash`，调用 `ai-media-review`，不要直接视频渲染或公开发布。
