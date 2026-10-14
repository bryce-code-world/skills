---
name: ai-media-topics
description: 为国内小红书、抖音、视频号、快手、B站等账号结合企业知识库批量策划选题，检测重复选题与目标用户价值。
---
# 批量选题 Skill

1. 从 `config/workspace.json` 定位知识库，读取 `brand.md`、`audience.md`、`methodologies/`、`successful-examples/`；以及 `outputs/` 既有选题。
2. 如已安装 `content-strategy`、`social`、`product-marketing`，优先使用其中已审查方法；不要将海外渠道方法生搬硬套到国内平台。
3. 每条选题输出：`id`、用户问题/场景、核心角度、视频钩子、预计时长、可用证据、可用素材、平台适配、与历史选题的差异、风险等级。
4. 按用户价值/创作成本/可核验事实/素材匹配度排序；缺乏可信来源的热点或专业判断，标记“待核实”，不得编造数据和案例。
5. 将批量结果以 UTF-8 Markdown + JSON 保存到 `outputs/_plans/<YYYYMMDD>-topics.*`，存在时使用新版本名，不覆盖。
6. 人工确认选题后，再交给 `ai-media-scripts`，不强制每条都进入视频生产。
