# ai-multi-media-kit

把一个视频需求推进到 **MP4 + 可编辑工程**。当前 AI 负责理解主题、写文案、安排镜头和质量判断；Remotion、TTS 与 FFmpeg 负责实际制作。

| 需求 | 使用方式 |
| --- | --- |
| 产品宣传、知识讲解、操作演示 | [快速制作](docs/QUICK_VIDEO.md)：内置 Remotion 模板，复用图片与配音 |
| 修改指定时间段 | 直接修改中文分镜，Agent 执行 `studio rebuild` 更新成片并保存旧版本 |
| 企业内容、批量选题、平台包 | [完整生产](.agents/skills/ai-media-studio/SKILL.md)：知识库、审核与素材流程按需启用 |
| 公开发布 | 仅按用户明确授权的平台和账号执行；生成发布包不等于发布成功 |

单条视频不要求先配置额外文本模型 API 或平台账号，也不强制安装 video-shotcraft。其已安装镜头配方和资源可显式选用。快速模板是创作起点，画面、节奏与听感仍需要 Agent 实际检查。

## 使用

将 [Skill 地址](https://github.com/bryce-code-world/skills/tree/main/ai-multi-media-kit) 交给拥有本地文件和终端能力的 Agent：

> 使用 ai-multi-media-kit，依据我提供的产品资料制作一条手机观看的宣传视频，控制在一分钟内。重点讲清痛点、解决方案和实际改变。复用已有工作区，交付 MP4 和可编辑工程，本次不发布。

Agent 读取 [SKILL.md](SKILL.md) 后按任务执行。需要首次安装或升级时看 [START_HERE](docs/START_HERE.md)；已安装环境直接复用，不反复初始化。源码更新、客户端 Skill 更新和工具工作区升级是不同操作。

已有工作区的最短命令：

```powershell
& "<工具目录>\RUN-STUDIO-WINDOWS.ps1" -Task studio quick --spec "<分镜.json>" --topic demo --agent codex --dry-run
& "<工具目录>\RUN-STUDIO-WINDOWS.ps1" -Task studio quick --spec "<分镜.json>" --topic demo --agent codex
```

分镜由 Agent 根据任务准备，普通用户不需要填写 JSON。成果位于 `workspace.json.output_root/<内容ID>/`，直接打开 **`成品视频.mp4`**、**`视频封面.png`**，旁边是 `01-文案与分镜/`、`02-媒体素材/`、`03-修改与版本/`；依赖和 Remotion 源码统一放在 `99-专业工程/`。目录和编辑方式见 [中文作品规范](docs/PROJECT_LAYOUT.md)。

## 质量与能力

- 快速渲染生成技术预览，记录 `technical_only`，不会伪造脚本或成片审核 PASS。
- 技术检查与实际画面、配音验收分别记录。按完整语义句配音，字幕换行与切镜不切断声音；没有试听能力时保留未验证项。
- 完整生产保留当前版本的脚本、发音、音轨和视频审核；打包与发布均验证证据及任务范围。
- 各宿主的本地文件、浏览器、音频及账号能力不同；文本生成、可播放视频、可编辑工程和真实投稿分别验证。

详细约定：[内容契约](docs/CONTENT_SCHEMA.md) · [素材来源](docs/MATERIAL_SOURCES.md) · [工具与参考](docs/TOOLCHAIN.md) · [兼容性](docs/AGENT_COMPATIBILITY.md) · [验收](docs/ACCEPTANCE_V3.md)。
