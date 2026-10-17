# 工具选型与真实能力边界（2026-10-12）

| 组件 | 地址 | 类型 | 职责 | 安装状态 |
|---|---|---|---|---|
| Marketing Skills | https://github.com/coreyhaines31/marketingskills | 第三方 Skills | 内容策略、文案、剪辑创意 | 按需安装，V2 本包不内置第三方代码 |
| baoyu-skills | https://github.com/JimLiu/baoyu-skills | 第三方 Skills | 公众号图文/封面卡片 | 同上；图片生成可能需独立付费 API |
| social-auto-upload | https://github.com/dreammis/social-auto-upload | CLI + 投稿脚本 | 小红书、抖音、视频号、B站、快手 | 当前维护中，逐账号验收 |
| MoneyPrinterTurbo | https://github.com/harry0703/MoneyPrinterTurbo | CLI | 本地素材 + 文案 + TTS/字幕 + MP4 | `uv sync --frozen` 后验证当前环境 |
| FFmpeg | https://ffmpeg.org | CLI | 本地视频处理，统一输出 9:16 MP4 | 系统 PATH 或指定二进制目录 |
| xiaohongshu-mcp | https://github.com/xpzouying/xiaohongshu-mcp | 可选 MCP | 小红书搜索、评论互动 | 默认只下载源码，不注册/启动服务 |
| ZhihuPublisher | https://github.com/zhihu/ZhihuPublisher | 实验性 Skill | 知乎文章、想法、问题 | 需要本人完成登录/账号授权（如适用），当前不支持该工具自动视频投稿 |

平台能力对应：

- 小红书/抖音/视频号/B站/快手：优先使用 social-auto-upload CLI，账号首次登录需要用户操作；CLI 返回值不等于平台审核通过。
- 公众号：将短视频衍生为文章/图文，用 baoyu-post-to-wechat 的 API 或浏览器发布（需要微信公众号账户及权限）。
- 知乎：将内容衍生为文章/想法，使用 ZhihuPublisher；其 README 明确当前发布流程不支持视频上传，需要平台登录或凭证；本套件未验证自动投稿时仅生成发布包。
- 评论、运营数据：**V2 不承诺全平台互通**。有合法官方 API 或经用户授权的小红书 MCP 才做；否则保存人工导入文件进行分析。

## 多来源真实视频素材

素材入口不绑定 MoneyPrinterTurbo：`materials.py` 支持默认企业素材目录、其他本地/NAS 共享目录、单次提供文件及外部合法下载文件的索引、标签、来源 URL 与授权说明。在线素材由已安装 MPT 执行 Pexels/Pixabay/Coverr 的 `--stop-at materials`，只在核实免费额度和传播许可后由 Agent 自主执行；若需提供商 API 凭证则按实际可用性处理；从外部 AI 视频生成服务获得的文件可按单次文件导入，V3 不默认调用收费服务。详细操作见 [MATERIAL_SOURCES.md](MATERIAL_SOURCES.md)。

## 为什么不将全部 MCP 默认启用？

只要 CLI 现成脚本可完成稳定上传，就无需多余 MCP。MCP 只是连接协议，底层官方 API/浏览器自动化的可靠性、账号风险和授权范围各不相同。管理 Cookie 的 MCP 必须用户确认并独立登录。

## 中文 TTS 与合成质量

FFmpeg 负责处理音频，不自动生成口播。选择已验证免费/合法且听感自然的中文 TTS（可复用已配置 MPT 或宿主配音服务）；Windows SAPI/Huihui 适合技术验证，不自动视为成片级品质。无需注册收费语音 API。

将逐镜头原始 WAV 交给 `studio voiceover --id <ID> --takes ...`，使用 FFmpeg 完成采样率转换与配音槽位装配，禁止每个 Agent 重写采样循环。最终 `studio check/package` 会重解码音轨并检查异常静音，但自然度、发音及字幕实际同步仍需试听，不能用 `volumedetect` 有声和 SRT 文本相同冒充音频验收。FFmpeg 缺少 `subtitles` 滤镜时可逐帧烧录字幕，但仍需实际观看核对。

## MPT 与宿主 Agent 订阅

任何宿主 AI Agent 的订阅登录，都不会自动支付第三方项目的模型、素材或 TTS API 费用。本 Skill 让当前 Agent 根据企业知识库生成脚本，再尽量用 MPT 的 `--video-script` + 本地素材 + Edge TTS 减少额外模型 API；仍需验证 MPT 依赖与配置，不承诺所有场景零成本。

## 安装边界

安装器会抓取用户初始任务范围内经过核实的免费白名单 URL，锁定第一安装 SHA，不自动升级。对 social-auto-upload 和 MPT 执行上游 `uv sync --frozen`，需要 Git/uv/可联网环境。浏览器内核单独下载、平台身份登录由用户本人完成；收费服务默认禁止，MCP 注册仅在宿主权限与初始任务范围允许时执行，**当前 ZIP 不包含或绕过这些服务**。

## 小红书 MCP 可选项目级注册（Codex 专属适配）

在已经有可用的 `xiaohongshu-mcp` 服务（仅绑定本机）的前提下：

```powershell
python scripts/configure_mcp.py --root .                 # 仅展示计划
python scripts/configure_mcp.py --root . --enable-xhs    # 初始任务范围内有必要时执行，不再输入 REGISTER 口令
```

这段脚本**只支持 Codex 项目级适配**：生成 `.codex/config.toml`，通过 `XHS_MCP_TOKEN` 环境变量引用密钥，不保存明文 Token。Codex 仅在信任工作区时加载其项目配置；重启后实际调用才能证明连通。其他 AI Agent 请根据当前宿主支持的 MCP 配置方式自行完成授权和连接验收，勿直接套用 Codex TOML；详见 [Agent 兼容指南](AGENT_COMPATIBILITY.md)。
## 已知多音词的 TTS 输入准备

V0.9 的 `speech-plan` 读取可配置词典，输出普通文本逐镜头输入。默认用上下文改写处理风险词，不内置任何厂商的 phoneme/SSML 适配。edge-tts 上游明确说明不支持任意自定义 SSML，不能假定追加音标标签即可纠正发音；来源：[edge-tts Custom SSML](https://github.com/rany2/edge-tts#custom-ssml)（核验于2026-10-17）。

已知词预检不是完整汉字多音识别器；同一模型和不同音色的读音可能不同。服务/音色、脚本、输入文本和音轨都记录哈希便于复核，但输入哈希不能证明 TTS 读对，实际音频验收仍独立进行。
