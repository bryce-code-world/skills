# 按任务选择工具

当前 Agent 负责理解资料、编稿和判断质量；现有订阅不会自动提供第三方模型、素材或语音 API。已有能力足够时直接使用，不为单条视频另配文本模型或安装整套工具。

## 制作所需

| 场景 | 工具 | 必要边界 |
| --- | --- | --- |
| 单条产品片、讲解与定点修改 | 本包 Remotion 模板 + Node/npm | 使用工程锁文件；无需 video-shotcraft 或 MPT。见 [QUICK_VIDEO](QUICK_VIDEO.md) |
| 复用上游模板依赖与配置 | 已安装 [video-shotcraft](https://github.com/Vincentwei1021/video-shotcraft) | 用 `--shotcraft-dir` 显式指定；镜头库和声音素材需另行移植并保留相应许可 |
| 本地视频剪辑、音轨装配及检查 | [FFmpeg/ffprobe](https://ffmpeg.org/) | 使用已安装或指定的二进制；分发和编解码许可依具体构建而定 |
| 已有素材的视频自动合成 | [MoneyPrinterTurbo](https://github.com/harry0703/MoneyPrinterTurbo)，安装组件 `mpt` | 可复用 Agent 写好的稿件；素材、TTS、模型服务各自验证配置与费用 |
| 中文旁白 | 宿主已有或用户授权的自然 TTS | 先做短样本试听，再按实际时长安排画面；FFmpeg 本身不会生成旁白 |

Remotion 的免费使用有条件，具体以其[官方许可](https://www.remotion.dev/license)和实际使用主体为准；不能把整个制作链路概括为无条件免费。没有合适配音能力时明确交付无旁白预览，不把 Windows SAPI 的技术验证声音默认当作正式成片音色。

## 按需扩展

以下只是适配候选，不是默认安装清单，也不代表当前环境已经通过真实使用验收。

| 需求 | 候选工具 / 安装组件 | 使用条件 |
| --- | --- | --- |
| 内容策略方法 | [Marketing Skills](https://github.com/coreyhaines31/marketingskills) / `marketing` | 当前 Agent 需要具体方法时再读或安装 |
| 封面、图文及公众号适配 | [baoyu-skills](https://github.com/JimLiu/baoyu-skills) / `baoyu` | 部分图片服务可能收费；发布需对应账号权限 |
| 视频平台投稿 | [social-auto-upload](https://github.com/dreammis/social-auto-upload) / `social` | 按指定平台和账号验证登录、投稿与最终作品链接 |
| 小红书运营能力 | [xiaohongshu-mcp](https://github.com/xpzouying/xiaohongshu-mcp) / `xhs-mcp` | 可选；下载源码不等于已注册、启动或连通 |
| 知乎图文适配 | [ZhihuPublisher](https://github.com/zhihu/ZhihuPublisher) / `zhihu` | 未验证投稿适配时只交付发布包，不承诺视频自动上传 |

安装器 `--component` 可重复指定，优先于整组 profile；`core` 目前包含 marketing/baoyu，不应为了快速视频默认安装。安装前核对来源、当前版本、许可与外部服务费用；首次安装记录实际 SHA，后续不自动升级第三方代码。MPT 和 social 的依赖沿用其锁文件。账号登录、浏览器下载和真实投稿分别验证。

## 素材与声音

本地、NAS、单次文件和获准下载的素材统一通过 `materials.py` 记录来源与许可，不绑定 MPT。在线素材服务可能需要 API Key；只有当前任务允许且费用、传播权限已核实才调用。详见 [素材来源](MATERIAL_SOURCES.md)。

完整生产使用 `speech-plan` 准备逐镜头输入，稳定稿件后审核，再生成配音并通过 `studio voiceover` 交给 FFmpeg 装配；字段和失效规则只在 [内容契约](CONTENT_SCHEMA.md) 定义。不要用文本预检、ASR 或音量正常替代发音与自然度试听。

语音能力按实际引擎核实，例如 [edge-tts 不支持任意自定义 SSML](https://github.com/rany2/edge-tts#custom-ssml)，不能假设添加音标标签就能修正读音。未处理的风险应改稿或更换已授权音色后重验。

## MCP 与宿主适配

CLI 已能完成任务时无需额外注册 MCP。`configure_mcp.py` 仅用于 Codex 项目级配置：默认显示计划，`--enable-xhs` 在已有可用本地服务且任务授权包含该连接时才写 `.codex/config.toml`，密钥通过 `XHS_MCP_TOKEN` 引用。实际调用成功才能证明连通。

其他宿主使用自己的配置方式，不能直接套用 Codex TOML。能力边界见 [Agent 兼容指南](AGENT_COMPATIBILITY.md)，首次安装与环境复用见 [START_HERE](START_HERE.md)。
