# 视频素材源：登记、检索、补充与剪辑

素材源与剪辑引擎独立。**默认优先企业自有素材，之后临时提供的已授权素材，最后才考虑网络素材。** 搜索不到合适画面时要明确缺口，不要通过重命名或自动打标签伪装成“AI 已识别”。

## 现有能力和边界

| 来源 | 操作 | 状态 |
| --- | --- | --- |
| 本地、外接硬盘、NAS/共享目录（已挂载可读） | 多目录登记、扫描视频、关键词检索、预览关键帧 | 已实现；只建索引，不搬运原片 |
| 单次提供的本地视频 | `materials add-file`，记录来源、授权、标签 | 已实现 |
| 用户给出的 HTTPS 视频链接 | 使用**经授权的外部下载工具/CLI/MCP**取得文件，再 `add-file --source-url` | 登记来源已实现；不内置任意 URL 下载器 |
| Pexels / Pixabay / Coverr | 通过已安装 MoneyPrinterTurbo 的 `--stop-at materials` 获取候选素材 | 按用户确认后执行；依赖提供商 API/权限，尚未实机连通 |
| AI 生成片段（如用户自己的可灵/即梦服务） | 经用户明确授权使用已有外部工具生成，导入本地后 `add-file` | 通用导入已支持；没有默认购买 API 或自动生成能力 |

重要：**“找到素材文件”不等于具备公开传播许可。** 默认 `unverified`；只有用户确认其为 `owned` 或 `licensed` 并保存许可说明后，才能使用登记的素材 ID 成片。网页可下载也不代表允许商用；在多个平台分发需核对各自许可范围。不会擅自录屏/爬取他人平台内容。

## 1. 配置素材源

首次初始化在独立工作区的 `config/material-sources.json` 注册默认的 `<企业知识库>/materials`，不覆盖已有配置。源目录可以是任何存在且可访问的路径，包含 UNC 或挂载好的 NAS 目录；安装器不负责建立网络共享/登录。

Windows 在**已初始化的工作区**打开 PowerShell：

```powershell
.\RUN-STUDIO-WINDOWS.ps1 -Task materials sources
.\RUN-STUDIO-WINDOWS.ps1 -Task materials add-source --name nas --path "Z:\\Video-Library"
.\RUN-STUDIO-WINDOWS.ps1 -Task materials scan
.\RUN-STUDIO-WINDOWS.ps1 -Task materials search --query "宠物 喂食" --limit 10
```

Linux/macOS：

```bash
bash ./run-studio.sh materials add-source --name nas --path "/mnt/nas/media"
bash ./run-studio.sh materials scan
bash ./run-studio.sh materials search --query "宠物"
```

`sources`、`add-source`、`scan` 只修改自有配置和本地索引；原视频完全不动。每次扫描最多 10,000 个视频文件，跳过符号链接，支持 MP4/MOV/MKV/WEBM/M4V/AVI。重新扫描保留人工标注；素材损坏/变化则要求重新建索引。

## 2. 给视频补充可检索信息

先检索文件名。需要镜头理解时用 `preview` 调用本地 FFmpeg 提取预览帧，再由当前 AI Agent（如支持图片读取）或人工检查画面，明确场景、主体、可用镜头片段后标注。**纯 CLI 不会自动做视觉模型理解，文本检索也不是向量语义检索。**

```powershell
.\RUN-STUDIO-WINDOWS.ps1 -Task materials preview --id <素材ID>
.\RUN-STUDIO-WINDOWS.ps1 -Task materials annotate --id <素材ID> --tags "宠物,喂食,实拍" --description "猫咪进食的特写镜头" --rights owned --license-note "企业自行拍摄"
```

单次文件、第三方已下载文件、AI 生成素材同样登记：

```powershell
.\RUN-STUDIO-WINDOWS.ps1 -Task materials add-file --path "D:\\素材\\片段.mp4" --rights licensed --license-note "授权编号或协议存放位置" --source-url "https://example.org/stock/123" --tags "办公,城市"
```

`--source-url` 只保留不带 Token/查询参数的 HTTPS 来源链接，**不会自动下载**；私有云签名地址、Cookie 和 Key 不得保存进素材索引。

## 3. 按脚本匹配、人工复核并成片

当前 AI Agent 读取脚本的 `shots[].visual`，在索引中按名称/标签/描述筛选候选素材；必要时逐个 `preview` 看画面，再按脚本顺序选择 ID。镜头匹配是当前 AI Agent/人工的判断，不是文件名匹配天然正确。

**脚本经 AI 审核并由用户批准后**：

```powershell
.\RUN-STUDIO-WINDOWS.ps1 -Task materials resolve --ids <素材ID1> <素材ID2>
.\RUN-STUDIO-WINDOWS.ps1 -Task studio render --id <内容ID> --engine ffmpeg --material-ids <素材ID1> <素材ID2> --rights-confirmed --dry-run
.\RUN-STUDIO-WINDOWS.ps1 -Task studio render --id <内容ID> --engine ffmpeg --material-ids <素材ID1> <素材ID2> --rights-confirmed
```

成片后写入 `outputs/<内容ID>/video/materials-used.json`，记录选材来源及授权声明，原始视频仍在自有素材目录。素材文件在扫描后被修改或移除时拒绝复用旧索引。对于未入库的临时文件，兼容原来的 `--materials <本地路径>`；仍需 `--rights-confirmed`。

**当前 FFmpeg 模式按传入顺序拼接整段视频，不会自动按脚本时长精确裁剪。** 需要先用 FFmpeg/MCP 的已验证工具裁好镜头，再传入；MoneyPrinterTurbo 的成片流程也必须人工验片。

## 4. 联网素材不足时再补充

已安装且配置好的 MPT 可以在**脚本审批后**仅获取素材，不执行成片/投稿：

```powershell
# 只预览计划，不调用网络
.\RUN-STUDIO-WINDOWS.ps1 -Task materials fetch-online --id <内容ID> --provider pexels --terms "pet eating, feeding bowl"
# 单独要求 --execute，并由用户本人输入 FETCH:<内容ID>:pexels
.\RUN-STUDIO-WINDOWS.ps1 -Task materials fetch-online --id <内容ID> --provider pexels --terms "pet eating, feeding bowl" --execute
```

可改选 `pixabay` / `coverr`。内部调用 MPT `--video-script` + `--video-terms` + `--stop-at materials`，避免由 MPT 再调用 LLM 生成脚本和搜索词。部分素材商仍要求 API Key 或有额度/许可限制，**当前 AI Agent 的订阅不会自动抵扣这些第三方 API 调用**。MPT 返回成功仅说明素材阶段完成；下载后的文件必须检查画面、来源及许可并用 `add-file` 登记为本地素材，才能进入受控成片。

素材源配置与索引会进入 `export_assets.py` 生成的 `materials/sources.json`、`materials/index.json`，但 **NAS、外接盘、知识库以外的原视频不会被打包**，迁移电脑时需自行转移和重新映射路径。导出前审核含本机路径的索引是否适合对外共享。

不得自动安装陌生素材下载器、绕过网站风控、下载有水印/无授权的受保护视频，或假装免费图片/视频库素材适用于所有商业用途。
