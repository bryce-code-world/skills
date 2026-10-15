# 内容结构与 AI 自主质量门禁

**一次用户任务授权完整的内容制作，不需要脚本、成片或素材逐项人工批准。** 只有初始用户任务明确指定公开发布的平台和账号时，才记录相应发布范围。

## 任务创建与发布范围

默认只制作：

```powershell
.\RUN-STUDIO-WINDOWS.ps1 -Task studio new --id my-video-001 --title "短视频主题"
```

初始任务明确授权公开发布抖音的 `main` 账号时：

```powershell
.\RUN-STUDIO-WINDOWS.ps1 -Task studio new --id my-video-002 --title "短视频主题" --publish-target douyin:main --task-ref "当前用户消息的真实引用"
```

`outputs/<ID>/content.json` 中保存 `publish_targets` 和可选的 `task_ref`（不保存账号口令）；`--publish-target` 可在创建时重复传入不同平台和账号，同一平台不得重复。Agent **只能根据原始用户任务设置**，不是由 CLI 读取聊天记录或判断真人身份。工具无法独立证明用户是否下达过发布指令，因此 Agent 不得自己编造来源。后续修改脚本不会增加发布权限，默认制作任务无法执行公开投稿。

## AI 编稿与脚本审核

`studio new` 生成 `script.template.json` 和 `review.template.json`，由 Agent 结合企业知识库生成正式 `script.json`：

```json
{
  "content_id": "my-video-001",
  "title": "短视频题目",
  "duration_seconds": 45,
  "narration": "经过事实核对的真实中文口播稿",
  "shots": [
    {"seconds": 5, "visual": "能找到且许可明确的镜头", "voiceover": "该镜头口播"}
  ],
  "platforms": {
    "xiaohongshu": {"title": "小红书标题", "description": "正文", "tags": ["标签"]},
    "douyin": {"title": "抖音标题", "description": "正文", "tags": []},
    "tencent": {"title": "视频号标题", "description": "正文", "tags": []},
    "bilibili": {"title": "B站标题", "description": "正文", "tags": []},
    "kuaishou": {"title": "快手标题", "description": "正文", "tags": []},
    "wechat_oa": {"title": "公众号标题", "description": "图文摘要", "tags": []},
    "zhihu": {"title": "知乎标题", "description": "图文摘要", "tags": []}
  },
  "article_markdown": "# 衍生文章\n..."
}
```

执行 `studio hash --id <ID>` 得到真实的 `script_sha256` 和 `review_standard_sha256`，Agent 依据知识库与实际证据审核并写入 `review.json`：

```json
{
  "result": "PASS",
  "score": 91,
  "script_sha256": "studio hash 给出的脚本哈希",
  "review_standard_sha256": "studio hash 给出的审核标准哈希",
  "checks": [
    {"rule": "事实准确", "result": "PASS", "reason": "能够追溯的证据"}
  ],
  "facts_to_verify": [],
  "issues": []
}
```

只有 **PASS + 每条 checks PASS + 无待核事实 + 无问题 + 哈希有效**，才会通过 `studio check` 的 `script_ready`；否则 Agent 自主查证、修改和重新审核（默认最多三轮）。文件本身是 AI 审核声明，CLI 不能代替 AI 发现语义错误，更不能默许伪造 PASS。

## 素材、成片和视频 AI 审核

优先使用可验证授权的本地/NAS/原创素材，`materials scan/search/preview` 用于检索和提帧。已有合法素材的 `--material-ids` 会验证索引、时间戳和权利；临时 `--materials` 必须有来源/许可依据。`--rights-confirmed` 只是执行 Agent 已核查的断言，不是用户审批。

`studio render`（FFmpeg）或 `studio import-video`（MPT 等外部工具）生成 `video/master.mp4` 和 `video/render.json`。渲染/导入记录 `script_sha256`、`video_sha256` 及可得的音视频信息；导入视频必须通过 ffprobe 的真实音视频检测。AI 审核实际画面、节奏、字幕和配音后创建 `video/review.json`：

```json
{
  "result": "PASS",
  "video_sha256": "当前 video/master.mp4 的 SHA256",
  "script_sha256": "当前 script.json 的 SHA256",
  "review_standard_sha256": "当前知识库 review-rules.md 的 SHA256",
  "checks": [
    {"rule": "镜头、字幕、声音与节奏", "result": "PASS", "reason": "已检查实际成片/关键帧"}
  ],
  "facts_to_verify": [],
  "issues": []
}
```

`studio check/status` 报告 `video_ready`。视频审核必须全项通过且与当前脚本、成片及审核标准版本吻合，`studio package` 才允许生成视频平台的发布包；任一修改将使相关审核过期。Agent 应自动返工且如实记录，不能用“FFmpeg 退出 0”替代视听验收。

## 发布与状态

`studio package --id <ID>` 生成各平台 `package.json` 和可用图文，不会投稿。发布包记录当前脚本、成片及视频审核哈希。

仅当内容创建时的 `publish_targets` 含 `platform:account`、发布包与当前资产一致、实际平台工具和登录态可用，Agent 可执行：

```powershell
.\RUN-STUDIO-WINDOWS.ps1 -Task studio publish --id my-video-002 --platform douyin --account main --execute
```

不再调用 `studio approve`，也不要求 `APPROVE`、`PUBLISH`、`VERIFY` 或逐平台确认；用户可能需要完成登录/扫码/验证码。CLI 成功仅进入 `submitted_unknown`，**不能直接宣称发布成功**。核实官方作品链接后记录：

```powershell
.\RUN-STUDIO-WINDOWS.ps1 -Task studio confirm-published --id my-video-002 --platform douyin --url "https://www.douyin.com/video/真实作品ID"
```

只有对应已授权平台账号的 `submitted_unknown` 状态和该平台的 HTTPS 作品链接才能进入 `published`；请求超时、状态未知或已发布时不得盲发第二次。当前公众号、知乎只有发布包能力，没有经验证的本套件通用自动投稿实现。

已存在的旧人工审批记录可以保留作历史追溯，但不再构成新版本的执行条件；旧内容若缺少当前视频 AI 审核，需要补做审核才可打包。已删除的 `studio approve` 不再是命令入口。
