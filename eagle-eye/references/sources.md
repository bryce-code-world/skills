# 热点数据源

每次研究先按主题选择来源，不要求所有来源都可用。数据源只提供候选、专业变化或讨论信号；关键事实仍需回到一手原文核验。

## 选择来源

| 研究对象 | 候选发现 | 专业信号 | 必须核验 |
| --- | --- | --- | --- |
| AI 模型、产品和公司动态 | AI HOT、Techmeme、Web 搜索 | Hacker News、GitHub、社区平台 | 官方公告、文档、模型卡、状态页 |
| 论文与研究趋势 | AI HOT、arXiv API、Web 搜索 | GitHub 代码、研究者原文、技术讨论 | 论文原文、作者页面、正式代码仓库 |
| 开发工具与开源项目 | Hacker News、GitHub Search、可选 `last30days` | Releases、Issues、Discussions | 官方仓库、发布说明、文档 |
| 行业政策与商业变化 | Techmeme、可靠媒体、Web 搜索 | 公司和从业者反应 | 监管文件、公司公告、财报或正式声明 |
| 公众关注与争议 | 可选 `last30days`、Reddit、X、YouTube、小红书 | 评论、互动量、反方观点 | 不能用社区信号代替事实核验 |

至少组合一份一手来源、一份独立背景来源，以及一类目标读者信号。多个网站转载同一篇稿件只算一个来源。

## Agent Reach 可选采集层

- 项目：`https://github.com/Panniantong/Agent-Reach`
- 作用：检测并路由网页、全网搜索、GitHub、YouTube、B站、V2EX、RSS，以及经过用户配置的社区平台。
- 定位：采集基础设施，不负责事件聚类、可写性评分、独特角度和选题判断。

当前环境存在 `$agent-reach` 或 `agent-reach` CLI 时：

1. 运行 `agent-reach doctor --json`。
2. 只选择 `status=ok` 且与当前研究有关的渠道。
3. `status=warn` 的渠道只有完成当前任务所需的只读验证后才能使用。
4. `status=off`、`active_backend=null` 且未验证的渠道按不可用处理。
5. 按 Agent Reach Skill 的渠道路由调用上游工具；Agent Reach 本身只负责选型、配置和体检。
6. 在研究说明中记录渠道、实际后端和健康状态。

命令无法直接解析时，Windows 的官方 venv 安装可以检查 `%USERPROFILE%\.agent-reach-venv\Scripts\agent-reach.exe`。其他系统只使用当前环境明确提供的命令，不猜测安装位置。

Agent Reach 是可选能力，不是鹰眼的依赖。不要在鹰眼运行时执行 `install`、`configure`、登录、Cookie 导入或浏览器会话读取。某个渠道不可用时继续使用后续直接来源。

## AI HOT

- 作用：快速发现最近 7 天的中文 AI 候选事件。
- 地址：`https://aihot.virxact.com`
- OpenAPI：`https://aihot.virxact.com/openapi.yaml`
- 鉴权：公开匿名；API 请求需要浏览器样式 `User-Agent`。
- 默认候选：`GET /api/public/items?mode=selected&since=<ISO 时间>&take=100`
- 分类：`ai-models`、`ai-products`、`industry`、`paper`、`tip`。
- 关键词：使用服务端 `q` 参数，不先拉固定数量再本地搜索。
- 历史日报：`GET /api/public/daily/{YYYY-MM-DD}`；`items` 最长只覆盖最近 7 天。

AI HOT 的摘要由模型生成，只能帮助发现候选。引用和核验必须打开每条记录的 `url` 或 `sourceUrl`。

每次调用前检查 DNS 和 HTTP 状态。服务不可达、返回异常或没有原始链接时跳过，并改用官方站点、Techmeme、Hacker News、GitHub、arXiv 与普通 Web 搜索。本来源当前不构成强依赖。

## Hacker News

- 官方 API：`https://github.com/HackerNews/API`
- 作用：发现开发者正在关注的产品、开源项目、论文和争议。
- 常用入口：Top、Best、New stories，以及对应 Item 的评论树。

分数和评论量只表示 Hacker News 社区关注度。评论可以帮助发现问题和反方角度，不能证明产品能力、事件原因或行业普遍性。

## GitHub

- Search API：`https://docs.github.com/en/rest/search/search`
- 作用：查找近期仓库、提交、Release、Issue、Discussion 和实际采用问题。
- 优先顺序：官方仓库 Release 与文档，其次是 Issue 和 Discussion，再其次是 Stars、Forks 等热度指标。

搜索和速率限制可能需要 GitHub 登录或 Token。当前环境没有授权时使用公开仓库页面，不索取、保存或输出凭据。Stars 只表示关注，不等于技术质量或真实采用。

## arXiv

- 官方 API：`https://info.arxiv.org/help/api/index.html`
- 作用：发现近期论文并核对标题、作者、摘要、版本和发布日期。

论文摘要只用于初筛。推荐研究型选题前阅读论文正文，并检查作者代码、后续版本、评测条件和外部复现。预印本状态必须如实保留。

## Techmeme

- 地址：`https://www.techmeme.com/`
- 作用：发现科技新闻簇、主要报道和讨论入口。

Techmeme 是候选发现和报道聚类层，不是事件事实的最终来源。沿聚类链接回到公司公告、监管文件和独立报道。

## last30days

- 项目：`https://github.com/mvanhorn/last30days-skill`
- 作用：在已经安装且可用时，增强 Reddit、X、YouTube、Hacker News、GitHub、arXiv、Techmeme 和 Web 等多来源发现，并提供跨来源聚类与互动信号。

它不是鹰眼的依赖。不要在运行鹰眼时安装、更新或配置它，也不要自行读取浏览器 Cookie、账号会话或 API Key。只有当前环境已经提供、用户授权的数据源才能使用。

互动量反映社会关注，不等于事实重要性。把它的聚类结果视为候选，仍按鹰眼的一手来源门禁重新核验。

## 官方站点与普通 Web 搜索

普通 Web 搜索是始终可用的基础路线：

1. 用事件主体、动作、产品名和绝对日期搜索候选。
2. 优先限制到官方域名，查公告、文档、状态页、模型卡和 Release。
3. 再查至少一家独立来源补充背景和影响。
4. 搜索选题的中英文同义表达与反方命题，验证角度是否同质化。

新闻搜索结果页、搜索摘要和 AI 摘要都不是引用源。打开支持结论的具体页面后再记录链接。

## 来源健康与降级

在 `00-选题研究说明.md` 中记录：

```text
来源：
用途：候选发现 / 专业信号 / 事实核验
状态：可用 / 无结果 / 不可达 / 需要授权 / 未检查
覆盖时间：
降级动作：
```

可选来源失败时继续使用其他类别来源。缺少一手来源时保留为线索；缺少独立背景时进入观察；缺少目标读者信号时降低读者关联评分。不得用来源数量掩盖类型缺口。
