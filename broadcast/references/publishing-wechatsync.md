# Wechatsync 发布实现

本文件只描述 Wechatsync 供应者的 MCP、Skill、CLI 和浏览器扩展入口。先读取 [publishing.md](publishing.md) 完成授权、能力检查、状态归一和降级判断；内容设计、事实判断、风格、Markdown 和平台转译仍由 `broadcast` 负责。

当前能力以 [Wechatsync 官方仓库](https://github.com/wechatsync/Wechatsync) 为准。平台、命令和接口会变化，实际投递前必须重新核对官方文档和当前环境。

## 目录

- [供应者边界](#供应者边界)
- [选择官方入口](#选择官方入口)
- [自动安装 MCP](#自动安装-mcp)
- [发布前预检](#发布前预检)
- [使用 CLI](#使用-cli)
- [使用 MCP](#使用-mcp)
- [安全要求](#安全要求)
- [逐平台投递](#逐平台投递)
- [草稿落地验收](#草稿落地验收)
- [状态词](#状态词)
- [降级](#降级)

## 供应者边界

Wechatsync 当前只作为可选发布实现，不是 `broadcast` 的内容依赖。目标入口必须满足 [publishing.md](publishing.md) 的通用契约，并且当前环境真实具备对应工具、依赖组件和平台登录状态。

本实现只接收已经验收通过的：

- 微信公众号标准文章；
- 知乎独立文章；
- CSDN 技术文章；
- 掘金技术文章。

不处理公众号卡片、知乎回答、小红书和其他已经移出 `broadcast` 正式范围的形态。安装、凭据、登录、素材上传、草稿保存和公开发布继续遵守通用契约中的独立授权边界。

## 选择官方入口

使用当前环境已经可用、最直接的官方入口：

1. 已连接的 Wechatsync MCP；
2. MCP 未安装时，自动触发下述官方 MCP 安装和重新发现；
3. MCP 安装失败或重载后仍不可用时，在已安装的官方 Wechatsync Skill 与依赖组件已连接的 Wechatsync CLI 中选择当前最直接、满足契约的入口；
4. 用户可操作的 Wechatsync 浏览器扩展；
5. 无可用入口时，交付人工发布包。

不要仅凭文件存在就声称入口可用。必须实际检查命令、工具连接和平台登录状态。

发布 MCP 缺失时直接进入下述自动安装流程。Skill、CLI、浏览器扩展或其他组件缺失时，按 [dependencies.md](dependencies.md) 处理各自安装或配置边界；MCP 自动安装授权不覆盖这些组件。

## 自动安装 MCP

用户已经明确要求投递且当前没有可用发布 MCP 时，按 [publishing.md](publishing.md) 自动触发官方 Wechatsync MCP 安装，不再单独请求一次 MCP 安装确认。

按当前官方文档，Wechatsync MCP 不是可以凭空假设存在的通用 `npx` 包。优先调用宿主提供的官方 MCP 插件、安装或连接能力；没有这种入口时，才执行以下受控流程：

1. 从 [Wechatsync 官方仓库](https://github.com/wechatsync/Wechatsync) 取得明确版本或提交，核对许可、README、Node.js 与 pnpm 等运行要求；
2. 按官方流程构建项目，确认 `packages/mcp-server/dist/index.js` 实际生成；
3. 在当前 MCP 客户端中注册由 `node` 启动的上述绝对路径，保留客户端现有其他 Server 配置；
4. 不把真实 `MCP_TOKEN` 写入 Skill、发布包、安装记录或示例；需要 Token 时触发用户通过宿主安全入口配置；
5. 重新发现工具，并至少确认 `list_platforms`、`check_auth` 和 `sync_article` 的当前 schema；
6. 当前会话不能热加载时标记“已安装待重载”，不继续投递，也不把安装文件存在写成 MCP 已连接。

不得编造 `@wechatsync/mcp`、`wechatsync-mcp` 或其他官方文档没有声明的包名。不得为了完成自动安装覆盖整个 MCP 客户端配置、安装浏览器扩展、生成 Token 或代替用户登录平台。

## 发布前预检

完成通用发布预检后，额外检查：

- Wechatsync 入口可调用；
- 当前入口依赖的浏览器扩展或桥接已经连接；
- 目标平台处于已登录状态；
- 当前入口能够承载目标 Markdown、正文图片和目标形态；
- 当前版本的工具 schema 与本文记录一致。

命令、MCP schema 或界面存在某个参数，只能证明入口接收该字段，不能证明目标平台适配器已经应用。不能依赖适配器自动删除正文首个 H1；平台稿必须在进入发布工具前完成标题与正文分离。首次投递、入口升级或平台适配器变化后，应结合当前文档、实现、预览或真实草稿重新确认。

## 使用 CLI

只有 CLI 命令真实可用、扩展已连接、Token 已由用户配置、目标平台已登录且用户授权时才运行。仅命令存在不算 CLI 可用。

先检查：

```text
wechatsync platforms --auth
```

如果当前版本支持，先使用预览：

```text
wechatsync sync <article.md> -p <platform> --dry-run
```

检查 dry-run 或等价预览中的正文起点：正文应从导语开始，不能再次出现文章标题。确认预览和目标无误后再保存草稿：

```text
wechatsync sync <article.md> -p <platform>
```

平台 ID 以当前 `wechatsync platforms` 和官方文档为准。不得把旧清单当作永久事实。

## 使用 MCP

优先调用只读工具检查平台和授权状态，再调用草稿同步工具。

当前官方 MCP 文档中的核心能力包括：

- `list_platforms`：列出平台和登录状态；
- `check_auth`：检查指定平台登录状态；
- `sync_article`：把文章保存为草稿；
- `upload_image_file`：按需上传本地图片；
- `extract_article`：从当前浏览器页面提取文章。

调用前核对当前已连接工具的真实 schema，不根据本文猜参数。

图片只有在目标发布包需要且用户授权上传时才上传。记录本地文件、目标平台和返回地址的对应关系。

## 安全要求

除 [publishing.md](publishing.md) 的通用安全要求外，不把 Wechatsync Token 写入 Skill、发布包、日志或回复。

官方文档说明远程桥接的 Token 可能明文传输。除非用户明确授权并已使用 SSH 隧道、VPN 或等价保护，否则不建立远程桥接。

## 逐平台投递

遵守 [publishing.md](publishing.md) 的逐平台单次提交和状态记录。即使 Wechatsync 支持多平台参数，也不要把多个平台合并成无法独立判断副作用的一次操作。

## 草稿落地验收

Wechatsync 返回成功不能替代 [publishing.md](publishing.md) 的真实草稿验收。可以通过安全入口查看草稿时逐项核对；无法查看时，把相应字段标为“未确认”。草稿已经创建但字段缺失时保留草稿并报告人工处理项，不自动重复投递。

## 状态词

把 Wechatsync 返回映射到 [publishing.md](publishing.md) 的统一状态。不得新增“同步成功”等含义不明确的中间状态。

## 降级

MCP 缺失时先执行自动安装和重新发现。原生安装与官方受控安装都不可执行、安装失败或重载后仍不可用时，在官方 Skill 和 CLI 中选择当前已知满足契约且最直接的入口。所有 Wechatsync 入口都不可用或不满足通用契约时，交付人工发布包，不用通用浏览器自动化复刻批量发布流程。
