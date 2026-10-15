---
name: ai-media-materials
description: 自动检索企业本地/NAS与已授权免费素材，核验来源、许可和实际画面，为短视频成片提供可追溯的素材 ID。
---
# 素材源与镜头匹配

- 根据 `config/workspace.json` 定位企业素材库；已配置目录与 NAS 使用 `materials scan/search`，通过 `materials preview` 提取真实画面；AI 能看图时核对镜头，文件名匹配不代表视觉识别。用 `materials annotate` 留下描述、来源和许可。
- 只选择 `owned` 或有可核许可证据的 `licensed` 素材。默认 `unverified` 不能成片，不得用 Agent 猜测代替许可。原始视频不复制、不修改。
- 若找不到镜头，优先调节分镜、检索已有素材或使用经过核实免费/合法的外部来源；`materials fetch-online` 先可查看计划，符合任务范围、费用与许可约束时直接 `--execute`，**不需再次人工输入 FETCH 口令**。网络失败或额度/权利不明则换用其它免费方案或说明阻塞。
- 将合规素材 ID 提供给 `studio render --material-ids <ID...> --rights-confirmed`。这里的 `--rights-confirmed` 是 Agent 依据证据确认素材许可，不是用户单独审批。未索引的临时文件需有实际来源及权利证据。
- 素材预览、格式与镜头选择都进入自动质量闭环，不应把正常创作判断交给用户。仅账号登录/扫码/验证码等身份操作需暂停；不得从非法来源抓取受保护内容。

详见 `docs/MATERIAL_SOURCES.md`。
