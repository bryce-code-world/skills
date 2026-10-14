---
name: ai-media-materials
description: 管理 AI Media Studio 的企业本地/NAS/临时视频素材源、素材授权与检索，按脚本分镜选择真实镜头；缺素材时按授权通过 MoneyPrinterTurbo 查找 Pexels/Pixabay/Coverr 并导入素材索引。
---

# 素材源与镜头匹配 Skill

素材是企业资产，素材源与剪辑引擎相互独立。按需阅读 `docs/MATERIAL_SOURCES.md`。

1. 默认检索已配置的企业素材目录；其他挂载/NAS 目录经用户指定后用 `materials add-source` 登记。临时文件通过 `materials add-file` 登记，不复制或修改原始视频。
2. 使用 `materials scan` 建索引，以 `materials search --query` 找候选；需要实际理解画面时，使用 `materials preview --id` 生成帧，由 Codex 可用的图像理解能力或人工观察后用 `materials annotate` 保存标签/描述。文件名和标签命中只是初筛，不能宣称已完成视觉语义匹配。
3. 匹配 `script.json` 的每个 `shots[].visual`，优先原创/已授权素材；缺口写清并请求用户选择自有素材、授权的网上素材或 AI 生成素材。不能编造镜头内容，也不静默启用收费服务。
4. 网络素材优先使用已经验证的现成 CLI/MCP 或 MPT 的 `materials fetch-online`；默认只展示方案，联网执行还需用户本人确认。执行后检查来源、授权、文件与画面，再 `add-file --source-url` 导入本地库。不把未经许可的素材标为商用可用。
5. 经用户批准脚本后，把素材 ID 交给 `studio render --material-ids`。先 `--dry-run`，再由已验证的 FFmpeg/MPT 执行；始终传 `--rights-confirmed`。对临时文件仍兼容 `--materials`。
6. 无法访问共享盘、素材缺失、素材在索引后变化、权益不明、下载权限不足时停止当前选材并说明原因。不得自行生成假素材或绕过授权。成片后保留素材来源和授权元数据并请用户验片。

运行入口：Windows `RUN-STUDIO-WINDOWS.ps1 -Task materials ...`，Linux/macOS `bash ./run-studio.sh materials ...`。它们运行套件本身的 Python，不依赖全局 Python。
