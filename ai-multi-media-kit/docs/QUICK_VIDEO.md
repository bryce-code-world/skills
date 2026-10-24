# 单条视频与定点修改

默认用内置 Remotion 模板制作可编辑 MP4。只读取当前任务需要的资料；批量选题、企业审核或平台包转到 [完整生产](../.agents/skills/ai-media-studio/SKILL.md)。

## 准备到制作

1. 固定受众、核心问题、要展示的改变和证据。产品宣传用痛点与结果组织镜头；用户要求教程时再展示操作步骤。
2. 先完成一个代表镜头和短配音样本。真实软件界面用获准的截图；桌面截图用于竖屏时局部裁切、放大重点，避免整屏缩成无法阅读的小图。
3. 先写连贯口播、生成完整语义句的配音，再安排画面和字幕。用实际声音决定镜头时长，留出句尾；没有自然配音服务时交付明确标注的无旁白预览，不擅自启用收费服务。
4. 预检、渲染、检查实际结果。模板是起点，复杂镜头直接修改 React 工程；不为已有任务重新初始化工具、配置额外文本模型或连接平台账号。

## 口播、镜头与字幕

口播原文、音频、画面切镜和字幕显示是不同对象。按以下顺序处理：

- 先把旁白写成正常交谈能一口说顺的句子，再送 TTS。显示换行只写入字幕或画面数据，不写入口播，不按字数或字幕行拆音频。密集术语先改成自然表达，例如“先生成配音，再按声音安排画面”。
- 模板每项支持一份音频。一个完整句需要多个画面时，在同一项内切换画面，或在可编辑工程中使用连续音轨；不要为切镜重新起读。`studio voiceover` 的逐镜头装配同样要求先按完整语义划段。
- 实测原始音频的发声起止与句间停顿，再决定镜头留白。已有首尾静音不要再机械叠加空白；修剪须保留弱辅音、尾音和必要呼吸，不裁句中停顿来掩盖错读。异常断词先改写该句或重做该段配音。
- 字幕从确定的口播和音频生成：优先完整词组、标点或真实词边界分句，再按宽度折行。避免词内断开、标点孤行和标题末行只剩一个字；没有词级时间戳时如实使用句级字幕，不声称逐词同步。

试听包含词内停顿和相邻句衔接。配音槽位未溢出、波形有能量、ASR 文字一致都不能证明口播自然。

## 输入

路径相对于 JSON 文件，或使用绝对路径。以下示例演示格式，不预设其他产品的卖点；`image`、`audio` 可省略。

```json
{
  "title": "把重复整理交给工具",
  "audience": "需要处理大量文件的人",
  "primary_value": "减少在文件之间反复复制的操作",
  "aspect": "9:16",
  "shots": [
    {
      "title": "每天都在重复整理？",
      "caption": "文件散落，重复操作",
      "seconds": 5,
      "image": "screen.png",
      "voiceover": "文件散在各处，整理一次又一次。",
      "audio": "voice.wav"
    }
  ]
}
```

- `aspect` 默认 `9:16`（1080×1920），也支持 `16:9`（1920×1080）；固定 30fps。
- 每镜头 2～20 秒，1～12 段，总时长不超过 180 秒。短宣传片可先按约 45～55 秒规划，用户指定的时长和画幅优先。
- 每镜头 `title` 是画面主句，`caption` 是简短提示，各不超过 60 字符；模板还会按实际字体检查可读布局，超限时应缩短文案。`caption` **不是自动生成的逐字字幕**。`voiceover` 保存旁白稿，`audio` 才是实际播放的配音。逐字字幕需在工程中按真实音频切句和配时。
- 图片支持 PNG/JPEG/WebP/SVG，音频支持 PCM WAV/MP3/M4A；单文件不超过 80MB。MP3/M4A 在预检时就需要已有 ffprobe，PCM WAV 由 Python 直接检查。实际配音须比镜头至少短 0.15 秒，不能靠截断获得短时长。
- JSON 由 Agent 编写。用户提供的录音、素材来源及授权应保留；有声音不代表读音或自然度已通过。

## 运行

使用共享工作区启动器的绝对路径：

```powershell
& "<工具目录>\RUN-STUDIO-WINDOWS.ps1" -Task studio quick --spec "<分镜.json>" --topic demo --agent codex --dry-run
& "<工具目录>\RUN-STUDIO-WINDOWS.ps1" -Task studio quick --spec "<分镜.json>" --topic demo --agent codex
```

Linux/macOS 使用 `bash "<工具目录>/run-studio.sh" studio quick ...`。初次安装、已安装版本不符或依赖缺失时见 [START_HERE](START_HERE.md)。

`--dry-run` 不创建项目，也不安装依赖。实际渲染需要 Node/npm；首次项目会按锁文件安装本地 npm 依赖，浏览器资源可能需要下载。当前环境的许可和网络可用性须单独核对，不能把预检通过说成已成片。

默认使用本包模板。`--shotcraft-dir <实际目录>` 仅复用已安装 video-shotcraft 的模板依赖、配置和许可证，画面仍由本包组件生成；不会自动导入其镜头库或音频。需要这些资源时另行移植并保留相应许可。

成果位于 `workspace.json.output_root/<内容ID>/`：

| 文件 | 用途 |
| --- | --- |
| `video/master.mp4` | 导出的 MP4 |
| `shotlist.json` | 渲染使用的镜头内容、帧数及素材清单 |
| `src/`、`public/` | 可编辑动画源码和项目素材 |
| `package.json`、`package-lock.json` | 项目命令与锁定依赖 |
| `script.json`、`content.json`、`video/render.json` | 内容、归属和本次技术渲染记录 |

## 定点修改

先找到用户指向的工程和当前成片，确认时间段、要改的内容及需保留部分。普通修订在原工程进行并保留可恢复版本；另做方案或跨 Agent 接力时使用独立项目。

1. 读取 `shotlist.json` 的累计帧数与 `src/`，定位镜头。30fps 下第 23 秒从第 690 帧开始；时间不是镜头序号。
2. 简单文案和素材改时间轴数据，动效改组件；口播或音色改变才重做受影响的配音。只改画面复用音频，只改时长重排音轨和字幕。时长由 `shotlist.json` 的 `frames` 驱动：同步更新 `frames = round(seconds × fps)` 和 `seconds`，核对后续起止。其他工程保留其数据源。
3. 复用项目已有依赖；仅依赖缺失或锁文件变化才运行 `npm ci`。先渲染受影响区间及相邻转场，检查后再导出完整成片；不对旧项目重新执行 `studio quick`。

在工程目录运行：

```bash
npm run dev
npx --no-install remotion still src/index.tsx QuickVideo video/check.png --frame=690
npx --no-install remotion render src/index.tsx QuickVideo video/preview.mp4 --frames=660-809
npx --no-install remotion render src/index.tsx QuickVideo video/master-v2.mp4
```

这些命令适用于本模板；其他工程使用其实际入口和 composition ID。本模板默认拒绝覆盖已有文件，重渲染使用新文件名；确需替换且已保留可恢复版本时才加 `--overwrite`。区间预览只用于检查，不能替代完整交付。参数说明见 Remotion 官方 [render](https://www.remotion.dev/docs/cli/render) / [still](https://www.remotion.dev/docs/cli/still)。

直接从 Remotion 重渲会使旧 `render.json` 的哈希过期，不能据此宣称旧审核仍有效。需要正式打包时，先按最终时间轴同步 `script.json`，完成 [脚本及发音检查](CONTENT_SCHEMA.md)，再用 `studio import-video --id <ID> --file <成片路径> --replace` 更新技术记录并重新审片。

## 完成标准

- 技术：实际 MP4 的画幅、时长、音轨与需求一致，旁白完整且无异常静音。
- 画面：抽查每个镜头、转场和结尾，检查手机可读性、字幕断句、内容遮挡和信息变化。静态画面可以保留阅读时间，但不能靠光点、进度条重复运动代替内容推进。
- 声音：正常速度核对语气、发音、停顿和音乐平衡。记录实际检查的时间段；不能试听时明确未验证项。
- 交付：给出 MP4 和工程位置，说明缺失旁白或未验证项。`render_status=technical_only`、`NOT_REVIEWED` 是程序记录，不代表已通过完整生产审核。需要平台包或公开发布时按 [内容契约](CONTENT_SCHEMA.md) 补齐真实证据，不能改状态值绕过检查。

维护验证入口与实测范围见 [验收](ACCEPTANCE_V3.md)。
