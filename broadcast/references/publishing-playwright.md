# Playwright MCP 网页草稿投递

本文件是 Broadcast 默认发布入口的实现说明。它使用 Microsoft 官方 `@playwright/mcp`，为四个平台分别启动一个有头浏览器实例，并通过独立 `user-data-dir` 持久化登录态。

## 为什么采用四个实例

- 微信公众号网页后台不需要个人用户申请 AppID、AppSecret 或配置 IP 白名单；
- 不依赖 Wechatsync 浏览器扩展、Token、WebSocket 端口和当前 Chrome 标签页；
- 首次登录后，Cookie、IndexedDB 和站点权限随专属 Profile 跨会话保留；
- 平台之间互不共享账号状态，一个平台失效不会污染其他平台；
- MCP 暴露当前页面结构，Agent 可以在页面变化后重新定位字段，不依赖长期硬编码选择器。

这个方案不能绕过扫码、验证码、风控或平台权限。首次登录和平台要求的二次确认仍由用户本人完成。

## 可信实现

默认实现：

- npm 包：`@playwright/mcp@0.0.79`
- 上游：`https://github.com/microsoft/playwright-mcp`
- 许可：Apache-2.0
- 运行时：Node.js 18 或更高版本
- 启动方式：`npx -y @playwright/mcp@0.0.79`

固定版本只表示当前 Skill 已核对的安装基线。升级前重新核对官方来源、许可、命令参数和工具 schema，再更新 [release.json](release.json) 或本文件；不得静默改用 `latest`。

## Profile 布局

安装时在仓库外选择本机绝对路径，建议布局：

~~~text
<local-app-data>/broadcast-publisher/
└── profiles/
    ├── wechat/
    ├── zhihu/
    ├── csdn/
    └── juejin/
~~~

不要把目录建在 `E:\agent`、文章发布包或任何 Git 仓库内，也不要指向用户日常 Chrome 或 Edge 的 User Data 目录。

一个持久化 Profile 同时只能被一个浏览器实例使用。四个平台可以使用不同 Profile 并行打开，但同一平台不得由多个会话并发操作。

## 客户端注册

为每个平台注册一个独立 MCP Server。下面是结构示例；安装程序必须把占位符替换为当前机器上的绝对路径，并写入当前 MCP 客户端支持的真实配置格式：

~~~toml
[mcp_servers.publisher_wechat]
command = "npx"
args = ["-y", "@playwright/mcp@0.0.79", "--browser", "chrome", "--user-data-dir", "<absolute-profile-root>/wechat"]

[mcp_servers.publisher_zhihu]
command = "npx"
args = ["-y", "@playwright/mcp@0.0.79", "--browser", "chrome", "--user-data-dir", "<absolute-profile-root>/zhihu"]

[mcp_servers.publisher_csdn]
command = "npx"
args = ["-y", "@playwright/mcp@0.0.79", "--browser", "chrome", "--user-data-dir", "<absolute-profile-root>/csdn"]

[mcp_servers.publisher_juejin]
command = "npx"
args = ["-y", "@playwright/mcp@0.0.79", "--browser", "chrome", "--user-data-dir", "<absolute-profile-root>/juejin"]
~~~

默认使用有头模式，不添加 `--headless`、`--isolated`、`--storage-state`、`--extension` 或 `--cdp-endpoint`。如果当前机器没有 Chrome，先检查官方参数支持的已安装浏览器，再明确修改 `--browser`；不要猜测可执行文件路径。

## 自动安装

用户明确要求投递，而任一目标平台实例未连接时：

1. 检查 Node.js 版本和 `npx` 是否可用。
2. 优先调用宿主原生 MCP 安装或连接能力；没有原生入口时，再修改当前客户端的 MCP 配置。
3. 核对上游、固定包版本、许可、配置文件路径和 Profile 根目录。
4. 只新增缺失的 `publisher_*` 节点，不覆盖或重排其他 MCP 配置。
5. 让 `npx -y` 从官方 npm 包取得固定版本；不执行第三方安装脚本。
6. 重新发现工具，并对每个实例分别检查启动结果与真实 schema。
7. 当前会话不能热加载时标记“已安装待重载”，停止本轮投递；下一会话从工具检查继续。

自动安装不写入 Token、Cookie 或平台凭据，也不安装浏览器扩展。配置完成不等于 Profile 已登录。

## 首次登录

每个平台单独完成：

1. 调用对应 `publisher_*` 实例打开平台官方创作后台。
2. 若进入登录页，保持有头浏览器打开，并告诉用户当前等待的具体平台。
3. 用户本人完成扫码、验证码、账号选择或风险确认。
4. 登录后核对页面显示的账号身份；账号不明确时停止，不猜测。
5. 关闭该实例并重新打开一次，确认登录态由同一 Profile 成功恢复。

不要让用户粘贴 Cookie、扩展 Token 或账号密码，也不要把登录二维码截图写入磁盘或日志。

## 页面操作

每次投递都从当前页面结构出发，不保存长期 DOM 选择器：

1. 打开平台创作后台，从可见导航进入新建文章或草稿编辑器。
2. 先识别标题、正文和保存草稿控件，再识别图片、封面、分类、标签等适用字段。
3. 字段不明确、存在多个同名账号或页面进入风控时停止，让用户处理。
4. 填入一次内容并保存一次草稿。
5. 跳转或打开草稿箱，使用可见标题和正文开头确认草稿真实存在。
6. 记录未确认字段；不为了“全自动”点击含义不清的控件。

平台的“发布”“群发”“提交审核”“定时发布”等按钮不属于草稿授权。即使页面只有发布按钮能触发自动保存，也不得点击，除非用户另行明确授权公开动作并确认平台语义。

## 并发与恢复

- 同一 `publisher_*` 实例一次只服务一个会话；发现 Profile 锁或已打开浏览器时，不强制结束进程或删除锁文件。
- 多会话并发投递同一平台时，后到会话停止在“Profile 被占用”，由最后持有该 Profile 的会话完成本次平台记录。
- 页面超时或保存结果未知时，先用同一 Profile 查询草稿箱；确认没有目标草稿后才能重试。
- 一个目标平台失败不影响其他平台，但不得复用失败平台的 Profile、页面引用或成功状态。

## 验收记录

每个平台至少记录：

- MCP 实例是否已连接；
- Profile 是否独立、可用且未被占用；
- 登录账号是否已核对；
- 保存草稿动作是否只执行一次；
- 草稿箱是否出现目标标题；
- 标题是否唯一、正文是否从导语开始；
- 正文图片、封面、分类和标签中的适用字段是否已确认；
- 是否存在人工处理项；
- 是否始终没有触发公开发布。

日志不得包含 Cookie、Token、二维码、验证码、账号密码或 Profile 文件内容。
