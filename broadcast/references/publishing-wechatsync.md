# Wechatsync 旧发布链路

本文件只保留迁移背景，不属于 Broadcast 默认发布路由。

旧链路通过 Wechatsync MCP、Skill 或 CLI，再连接浏览器扩展和当前 Chrome 会话。实测中反复出现扩展 Token、环境变量、WebSocket 端口、浏览器 Profile、账号会话和桥接重连之间的状态错位；工具返回成功也不能稳定证明平台草稿已经持久化。

自 Broadcast 2.8.0 起：

- 默认使用 [publishing-playwright.md](publishing-playwright.md) 定义的四个独立 Playwright MCP 实例；
- 不自动安装 Wechatsync 扩展，不索取或配置扩展 Token；
- 不启动 Wechatsync CLI、HTTP/WebSocket 桥接或复用当前 Chrome Profile；
- Wechatsync 已安装、Token 已存在或扩展已连接，也不代表它会被自动选中；
- 既有 Wechatsync 四平台投递结果只作为历史证据；Playwright 四平台可见草稿保存已单独完成回归，但内容深度和排版仍需按文章独立验收。

只有用户明确点名要求使用 Wechatsync，并接受它的扩展、Token 和桥接边界时，才按当时官方文档重新核对来源、版本、schema、登录状态和草稿证据。Broadcast 不再维护其安装命令、端口、Token 配置或重连步骤。

迁移不会删除用户现有扩展、环境变量、MCP 配置或浏览器数据。清理这些旧资产属于独立的破坏性任务，必须由用户另行明确授权。
