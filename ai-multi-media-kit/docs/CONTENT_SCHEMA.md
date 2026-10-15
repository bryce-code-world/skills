# 内容数据结构与审批约束

对一个内容 ID，运行 `studio new` 后，会生成 `script.template.json` 和 `review.template.json`，由 当前 AI Agent 参考模板生成以下正式文件：

`outputs/<ID>/script.json`：

```json
{
  "content_id": "my-video-001",
  "title": "短视频题目",
  "duration_seconds": 45,
  "narration": "真实中文口播稿……",
  "shots": [
    {"seconds": 5, "visual": "真实素材或可执行的拍摄镜头描述", "voiceover": "本镜头口播"}
  ],
  "platforms": {
    "xiaohongshu": {"title": "小红书标题", "description": "正文", "tags": ["标签"]},
    "douyin": {"title": "抖音标题", "description": "正文", "tags": ["标签"]},
    "tencent": {"title": "视频号标题", "description": "正文", "tags": ["标签"]},
    "bilibili": {"title": "B站标题", "description": "正文", "tags": ["标签"]},
    "kuaishou": {"title": "快手标题", "description": "正文", "tags": ["标签"]},
    "wechat_oa": {"title": "公众号标题", "description": "图文摘要", "tags": []},
    "zhihu": {"title": "知乎标题", "description": "图文摘要", "tags": []}
  },
  "article_markdown": "# 视频衍生文章标题\n正文……"
}
```

生成 `script.json` 后执行 `python scripts/studio.py --root . hash --id my-video-001`，将打印结果填入 `review.json`：

```json
{
  "result": "PASS",
  "score": 91,
  "script_sha256": "复制 studio hash 给出的当前值",
  "review_standard_sha256": "复制 studio hash 给出的当前值",
  "checks": [{"rule": "事实准确", "result": "PASS", "reason": "已核对证据..."}],
  "facts_to_verify": [],
  "issues": []
}
```

如果存在待核实事实或未通过检查，result 必须为 `REVISE`/`BLOCK`，不允许 PASS。

素材选型信息不直接混入 `script.json` 的审核哈希：由 `materials scan/search/preview` 从多来源选视频、`materials annotate` 记录来源和授权，使用 `studio render --material-ids <ID...>` 时校验索引的新鲜度及许可。成片后 `video/materials-used.json` 记录素材 ID、原始路径、授权状态及成片哈希（只复制元数据，不复制企业原片）。使用原有 `--materials` 仍可临时传入本地文件，并由使用者显式确认其权利。详见 [MATERIAL_SOURCES.md](MATERIAL_SOURCES.md)。

人工关口绑定最新哈希，支持**对话确认或终端确认**：

1. 脚本：AI 审核 PASS、无待核事实且本人看过当前脚本后，可以在当前对话说「我已审核并批准 my-video-001 的脚本，可以进入视频制作。」或「我批准 my-video-001 的脚本。」。
2. 成片：实际视频存在、脚本未变化，本人验片后可以说「我已验收并批准 my-video-001 的成片。」或「我批准 my-video-001 的成片。」。
3. 发布包：对应脚本/成片已获批准，平台包生成后，本人可说「我批准 my-video-001 发布到 douyin，账号 main。」；内容 ID、平台和账号必须完全一致。
4. **真正上传仍是另一道关口：** `studio publish --execute` 当前依然需要终端输入 `PUBLISH:<ID>:<platform>`，不因批准发布包而自动投稿；`confirm-published` 的人工核验同样保留。

Agent 在确认存在**真实用户**的上述原话后，可以执行下面的命令记录批准，用户本人无需操作终端：

```powershell
# Windows：在已初始化工作区，Agent 引用实际用户发出的批准原话
.\RUN-STUDIO-WINDOWS.ps1 -Task studio approve --id my-video-001 --stage script --who "本人" --chat-message "我已审核并批准 my-video-001 的脚本，可以进入视频制作。"
# 如果宿主提供真实用户消息 ID，可附加 --chat-ref "workbuddy:conversation:message"
```

CLI 的 `--chat-message` 只校验文本明确性、内容 ID、阶段及账号（如发布），**无法独立验证是谁发出的消息**。调用的 Agent 必须直接引用当前会话真人用户的原话，不能编造、总结代替、引用 AI 自己的输出，不能把疑问、笼统的「可以」或本次功能开发授权当成脚本批准。可选的 `--chat-ref` 是便于追溯的消息位置，不是身份签名。记录会保留 `approval_method=conversation`、用户批准原话、来源引用（若有）及现有脚本/审核/成片/发布包哈希，修改后旧批准仍失效。对话引用只使用简单批准语句，勿夹带隐私或凭据。

旧流程完全保留：用户也可以自己执行 `studio approve` 并在终端输入 `APPROVE:<ID>:script`、`APPROVE:<ID>:video` 或 `APPROVE:<ID>:publish:<platform>`。不允许 AI 代填终端口令。

已执行的发布动作不可自动撤回。
