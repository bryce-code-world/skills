# 内容数据结构与审批约束

对一个内容 ID，运行 `studio new` 后，会生成 `script.template.json` 和 `review.template.json`，由 Codex 参考模板生成以下正式文件：

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

人工关口绑定最新哈希：

1. 脚本人工确认：需审核 PASS 且无待核事实。本人在终端输入 `APPROVE:<ID>:script`。
2. 成片人工确认：视频必须存在且脚本未变更。本人输入 `APPROVE:<ID>:video`。
3. 平台发布确认：视频平台需视频审批通过；公众号/知乎需脚本审批。须先生成发布包，本人输入 `APPROVE:<ID>:publish:<platform>`，绑定账号别名。
4. 发帖时本人另行输入 `PUBLISH:<ID>:<platform>`；脚本工具不保存账号凭据，也不代填这些文本。

每次修改源文件或审核规则，历史批准失效。已经执行的发布动作则不可自动撤回。
