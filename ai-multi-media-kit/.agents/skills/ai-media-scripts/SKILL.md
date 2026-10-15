---
name: ai-media-scripts
description: 根据企业知识库与用户任务自动生成中文短视频脚本、口播、分镜和七平台文案，并支持 AI 审核返工。
---
# 脚本生产

- 使用当前任务范围创建不可覆盖的内容 ID：`studio new --id <ID> --title "主题"`。只有任务原话明确指定公开发布的平台与账号时才添加 `--publish-target platform:account`；制作/导出不等于发布。
- 根据品牌、受众、事实与素材能力生成 `outputs/<id>/script.json`：包括 `content_id`、`title`、`narration`、`shots`、`duration_seconds`、七平台 `platforms` 适配、`article_markdown`。
- 开头突出真实用户问题，信息密度和分镜符合时长，镜头要可实际获取，来源不明的素材不能标为已授权。医疗、金融、法律、政策、热点等事实要核对可靠来源；不虚构效果或案例。
- 使用 `studio hash` 与 `ai-media-review`，根据审核问题自动修稿，最多三轮；禁止带着未核事实直接渲染。无需用户读稿或逐条选题审批。公众号/知乎适配为图文，不假装与短视频平台直传一样。
