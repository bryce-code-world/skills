# 视频素材源：自动查找、许可核验和成片

**优先企业已授权的本地素材，再考虑已经核实免费且允许当前用途的网络素材。** 素材搜索、镜头匹配、选择与质量判断由 Agent 完成，不要求用户在每个素材阶段点击批准。

## 来源与边界

| 来源 | 方式 | 现状 |
| --- | --- | --- |
| 企业本地、硬盘、已挂载 NAS | `materials scan/search/preview` | 只索引，原片不移动 |
| 任务内已授权的临时视频 | `materials add-file` | 保留文件来源与许可证据 |
| Pexels / Pixabay / Coverr | 已安装 MPT 的 `fetch-online` | 可在核实免费额度和素材许可后自动执行；依赖 API/账号与版本，仍需实机验收 |
| 其他视频链接或 AI 生成服务 | 自有合法工具获取，再登记 `add-file` | 不内置绕过访问限制的任意下载器，不自动调用收费服务 |

**获取文件不等于获得版权。** 登记的素材默认 `unverified`，必须通过真实来源和许可核验为 `owned` 或 `licensed` 才允许以素材 ID 成片。Agent 不得为了通过校验擅自伪造许可或把仅供个人使用的素材当成商业授权。文本标签命中不等于已经视觉识别画面。

## 本地/NAS 素材

默认源为 `knowledge_root/materials`。对于任务内可访问的其他目录：

```powershell
.\RUN-STUDIO-WINDOWS.ps1 -Task materials sources
.\RUN-STUDIO-WINDOWS.ps1 -Task materials add-source --name nas --path "Z:\Video-Library"
.\RUN-STUDIO-WINDOWS.ps1 -Task materials scan
.\RUN-STUDIO-WINDOWS.ps1 -Task materials search --query "宠物 喂食"
.\RUN-STUDIO-WINDOWS.ps1 -Task materials preview --id <素材ID>
```

Agent 能看图片时应检查预览帧，判断镜头是否匹配分镜，再按实际证据标注。默认扫描最多 10,000 个视频，跳过符号链接，重扫保留已有人工/Agent 标签但校验文件变化；不对原片做写操作。

经核实的自有内容可这样登记：

```powershell
.\RUN-STUDIO-WINDOWS.ps1 -Task materials annotate --id <素材ID> --rights owned --license-note "企业原创"
.\RUN-STUDIO-WINDOWS.ps1 -Task materials add-file --path "D:\素材\片段.mp4" --rights licensed --license-note "已取得可传播授权的来源" --source-url "https://example.org/stock/123"
```

`--source-url` 只接受不含 Token/签名查询的 HTTPS 原始来源链接，**不会自动下载**。

## 根据分镜自动选材

当 `studio check` 显示 `script_ready=valid` 后：

```powershell
.\RUN-STUDIO-WINDOWS.ps1 -Task materials resolve --ids <素材ID1> <素材ID2>
.\RUN-STUDIO-WINDOWS.ps1 -Task studio render --id <内容ID> --material-ids <素材ID1> <素材ID2> --rights-confirmed
```

`--rights-confirmed` 是执行 Agent 已核查素材来源/授权的声明，不是用户单独审批。可先使用 `--dry-run` 检查命令，但实际交付必须生成可播放 MP4。素材文件在扫描后变化、移除或许可不明时，继续使用会被拒绝。

FFmpeg 模式默认顺序拼接整段视频，不按分镜自动裁剪。Agent 应在必要时用现有工具先裁剪，生成视频后对真实画面、音频、字幕和镜头一致性做质量审核并记录 `video/review.json`。没有配音不可把静音当成已完成口播。

## 合法免费网络素材

```powershell
# 计划预览，可选
.\RUN-STUDIO-WINDOWS.ps1 -Task materials fetch-online --id <内容ID> --provider pexels --terms "pet eating, bowl"
# 确认提供商确实免费且适用于本任务后，由 Agent 执行，无 FETCH 口令
.\RUN-STUDIO-WINDOWS.ps1 -Task materials fetch-online --id <内容ID> --provider pexels --terms "pet eating, bowl" --execute
```

工具只调用 MPT 的 `--stop-at materials` 素材阶段，不投稿。提供商若要求付费 API、未知计费或许可不足，Agent 应改用其他已核实免费的素材或调整创意，不能通过再次审批转嫁质量与成本判断。必须本人登录/扫码/验证码时才暂停；账号密钥不能写入脚本/审查产物。

MPT 返回成功并不保证已下载合规镜头。Agent 需要检查真实文件、画面、来源及传播许可，再用 `materials add-file` 登记，才可参与成片。索引/源配置可以随 `export_assets.py` 打包，但工作区之外的 NAS/硬盘原始视频不会随包迁移。
