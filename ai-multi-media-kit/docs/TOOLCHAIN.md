# 工具选型与真实能力边界（2026-10-12）

| 组件 | 地址 | 类型 | 职责 | 安装状态 |
|---|---|---|---|---|
| Marketing Skills | https://github.com/coreyhaines31/marketingskills | 第三方 Skills | 内容策略、文案、剪辑创意 | 按需安装，V2 本包不内置第三方代码 |
| baoyu-skills | https://github.com/JimLiu/baoyu-skills | 第三方 Skills | 公众号图文/封面卡片 | 同上；图片生成可能需独立付费 API |
| social-auto-upload | https://github.com/dreammis/social-auto-upload | CLI + 投稿脚本 | 小红书、抖音、视频号、B站、快手 | 当前维护中，逐账号验收 |
| MoneyPrinterTurbo | https://github.com/harry0703/MoneyPrinterTurbo | CLI | 本地素材 + 文案 + TTS/字幕 + MP4 | `uv sync --frozen` 后验证当前环境 |
| FFmpeg | https://ffmpeg.org | CLI | 本地视频处理，统一输出 9:16 MP4 | 系统 PATH 或指定二进制目录 |
| xiaohongshu-mcp | https://github.com/xpzouying/xiaohongshu-mcp | 可选 MCP | 小红书搜索、评论互动 | 默认只下载源码，不注册/启动服务 |
| ZhihuPublisher | https://github.com/zhihu/ZhihuPublisher | 实验性 Skill | 知乎文章、想法、问题 | 需要知乎授权，官方当前不支持这个发布流程中的视频上传 |

平台能力对应：

- 小红书/抖音/视频号/B站/快手：优先使用 social-auto-upload CLI，账号首次登录需要用户操作；CLI 返回值不等于平台审核通过。
- 公众号：将短视频衍生为文章/图文，用 baoyu-post-to-wechat 的 API 或浏览器发布（需要微信公众号账户及权限）。
- 知乎：将内容衍生为文章/想法，使用 ZhihuPublisher；其 README 明确当前发布流程不支持视频上传，需要凭证和人工确认。
- 评论、运营数据：**V2 不承诺全平台互通**。有合法官方 API 或经用户授权的小红书 MCP 才做；否则保存人工导入文件进行分析。

## 多来源真实视频素材

素材入口不绑定 MoneyPrinterTurbo：`materials.py` 支持默认企业素材目录、其他本地/NAS 共享目录、单次提供文件及外部合法下载文件的索引、标签、来源 URL 与授权说明。在线素材由已安装 MPT 执行 Pexels/Pixabay/Coverr 的 `--stop-at materials`，必须有人工确认和提供商 API 凭证（如适用）；从外部 AI 视频生成服务获得的文件可按单次文件导入，V3 不默认调用收费服务。详细操作见 [MATERIAL_SOURCES.md](MATERIAL_SOURCES.md)。

## 为什么不将全部 MCP 默认启用？

只要 CLI 现成脚本可完成稳定上传，就无需多余 MCP。MCP 只是连接协议，底层官方 API/浏览器自动化的可靠性、账号风险和授权范围各不相同。管理 Cookie 的 MCP 必须用户确认并独立登录。

## MPT 与 ChatGPT 订阅

Codex 的订阅登录并不会让第三方项目中的 OpenAI API 调用自动免费。本 Skill 将脚本生成放到 Codex，尽量使用 MPT 的 `--video-script` + 本地素材 + Edge TTS（无需 TTS API Key）；仍可能需要安装专用模型及相关环境，不承诺所有场景零成本。

## 安装边界

安装器会抓取用户批准的白名单 URL，锁定第一安装 SHA，不自动升级。对 social-auto-upload 和 MPT 执行上游 `uv sync --frozen`，需要 Git/uv/可联网环境。浏览器内核单独下载、用户平台授权、收费服务配置、MCP 注册均由用户授权后执行，**当前 ZIP 不包含或绕过这些服务**。

## 小红书 MCP 可选项目级注册

在已经有可用的 `xiaohongshu-mcp` 服务（仅绑定本机）的前提下：

```powershell
python scripts/configure_mcp.py --root .                 # 仅展示计划
python scripts/configure_mcp.py --root . --enable-xhs    # 输入 REGISTER:xhs-mcp 确认
```

它只生成 `.codex/config.toml`，引用 `XHS_MCP_TOKEN` 环境变量，不保存明文令牌。需要用户另外给 MCP 服务设置相同的 `AUTH_TOKEN`、先手动登录账户并启动本机服务。Codex 仅在信任此工作区时加载项目配置；重启 Codex 后实际调用才能证明连接成功，创建配置不代表连接已验证。
