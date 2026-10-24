# 快速创作：video-shotcraft + Remotion

用途：已经明确主题和主线，希望尽快得到可编辑的竖屏/横屏 MP4。与完整自媒体生产流程不同，**快速模式只制作技术预览，不发布，也不伪造内容审核结果**。

## Agent 负责，程序执行

1. 理解真实观众、问题、核心价值和证据，前 3–5 秒先给一个有意义的开场。安装测试不是产品宣传主线。
2. 优先使用用户授权的真实截图/合法素材。素材不足时用明确的概念图或字卡，不假冒产品界面。
3. Agent 按需准备中文神经网络配音文件，先听音和检查字幕，不能因为自带 Windows TTS 可运行就当成成片级自然配音。
4. Agent 为每段写简短的 JSON 分镜，程序调用本机 video-shotcraft 的 Remotion 模板、FlashCut 转场和有来源记录的 BGM 生成 MP4，保留全部可编辑源码和素材。复杂镜头由 Agent 继续参考 video-shotcraft Gallery 中的对应 demo/配方修改代码，而不是堆叠新的 CLI 配置。
5. 渲染前 `--dry-run`；渲染后逐帧、音轨和字幕安全区复核，交付时说明事实核验与语音试听结果。技术成功不代表内容已经通过审查。

## 最小 JSON

`image` 和 `audio` 均可不填；缺少 `audio` 且有旁白稿时将明确输出 `voice_missing`，**不声称视频包含配音**。图片/音频路径按 JSON 所在目录解析，或写绝对路径。

~~~json
{
  "title": "云端 AI 为什么碰不到本地文件",
  "audience": "需要 AI 操作本地项目的开发者",
  "primary_value": "让支持 MCP 的 AI 通过受控连接访问本地工具",
  "aspect": "9:16",
  "shots": [
    {
      "title": "AI 会写代码，却碰不到电脑",
      "caption": "普通网页对话与本地电脑隔离",
      "seconds": 5,
      "image": "screen.png",
      "voiceover": "为什么网页 AI 往往不能直接操作本地文件？",
      "audio": "voice.wav"
    }
  ]
}
~~~

示例只演示格式，不能无证据套用具体产品卖点。用户不需要手工编写 JSON，Agent 应根据任务自动生成。每段 2～20 秒，最多 12 段，总时长最多 180 秒。

## 调用

复用已安装共享工作区，不新建第二套环境、不重复安装 Python/FFmpeg，也不改 PATH。

Windows：

~~~powershell
& "<已有工具目录>\RUN-STUDIO-WINDOWS.ps1" -Task studio quick --spec "<分镜.json>" --topic localbridge --agent codex --dry-run
& "<已有工具目录>\RUN-STUDIO-WINDOWS.ps1" -Task studio quick --spec "<分镜.json>" --topic localbridge --agent codex
~~~

Linux/macOS：

~~~bash
bash "<已有工具目录>/run-studio.sh" studio quick --spec "<分镜.json>" --topic localbridge --agent codex
~~~

默认从用户级 Codex Skills 查找 video-shotcraft；非标准位置可加 `--shotcraft-dir <目录>`。未安装时清楚报错，不默默下载第三方 Skill 或收费工具。需要本地 Node/npm；Remotion 依赖来自 video-shotcraft 的固定版本模板，安装到本项目中。

所有持久化成果统一放在 `config/workspace.json.output_root/<content_id>/`，不写入 Skill 目录、临时目录或其他 Agent 的项目。输出 `video/master.mp4`、`src/`、`shotlist.json`、`public/` 和素材来源说明。`cd <项目目录>; npx remotion studio src/index.tsx` 可精确编辑镜头、字幕与动画。

## 模式分工

- **快速视频**：`studio quick` → 已提供的截图和配音 → Remotion MP4 + 编辑工程；默认 9:16 / 1080×1920 / 30fps，支持 16:9。
- **普通素材拼接**：继续使用原 `studio render --engine ffmpeg`。
- **完整自媒体生产**：沿用 `studio new → speech-plan → AI review → voiceover → render → video review → package`，包含知识库、发音核验、多 Agent 协作和平台包。

快速模式复用原 `studio new` 的身份、项目隔离与发布范围限制；只创建技术预览，不产生假的 `review.json` / `video/review.json`。项目的 `video/render.json` 明确标记 `render_status=technical_only`；因此 `studio package` 和 `publish` 依然受原审核与发布授权约束。若要正式发布，需要补齐真实的脚本/语音和视频审查。

## 验证

`python -X utf8 -m unittest discover -s tests -p test_quick_video.py -v`

默认执行离线测试。设置 `AI_MEDIA_QUICK_REAL_RENDER=1` 会在临时隔离工作区进行真实 Remotion/MP4 冒烟渲染，不修改旧项目或公开投稿。

音频和 BGM 来源见新项目的 `docs/audio-attribution.md`；复用的 video-shotcraft 源码还会同时保留 `docs/video-shotcraft-LICENSE.txt`（Apache-2.0）。素材是否可商用由实际来源和最新许可证决定。
