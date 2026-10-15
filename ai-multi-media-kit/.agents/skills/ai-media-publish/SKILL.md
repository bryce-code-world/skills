---
name: ai-media-publish
description: 给小红书、抖音、视频号、快手、B站、公众号、知乎准备差异化内容，严格执行人工审核和 dry-run，受控使用既有 CLI 或对应 Skill 发布。
---
# 平台发布 Skill

- 七个平台：`xiaohongshu`、`douyin`、`tencent`、`bilibili`、`kuaishou`、`wechat_oa`、`zhihu`。
- 视频平台需要人工批准成片；公众号/知乎需要人工批准脚本，并准备图文衍生稿；执行 `studio package --id <id>` 只会生成待发布包，绝不投稿。
- 每个平台的标题、简介、标签应单独审核，尤其检查平台格式、话题、版权与敏感表述；素材仅供已授权账号使用。
- 视频投稿首选 social-auto-upload `sau`；先在测试号验证当前 CLI。发布包可由用户在对话中明确批准**内容 ID + 平台 + 账号**，Agent 使用 `studio approve --stage publish --platform <p> --account <alias> --who <本人> --chat-message <用户原话>` 登记；否则仍使用终端人工批准。`studio publish` 先 dry-run。**实际投稿时的 `PUBLISH` 二次交互确认仍然独立保留**，不能把对话中批准发布包当作立即发帖授权。
- 公众号使用 baoyu-post-to-wechat；知乎使用 ZhihuPublisher。由于它们的接口和授权流程不同，V2 只自动生成文章包，真正发送时由对应已安装 Skill 引导人工发布，不调用没有测试过的接口。
- 未拿到可靠公开作品链接之前记录 `submitted_unknown`，不要声称发布成功，不要因超时而盲目重试。
- 不默认自动抓取/回复评论；仅在合法 API/MCP 权限可验证后逐平台开启。
