# 内容归属、发音准备与质量契约

本文件定义**完整生产**分支的状态和审核字段。单条快速制作、定点修改先用 [QUICK_VIDEO](QUICK_VIDEO.md)，不把下列全部审核对象变成快速预览的前置条件，也不生成虚假 PASS。共享环境与目录规则见 [AGENTS](../AGENTS.md)。

按需查看：[项目身份](#新项目主题agent轮次) · [脚本](#脚本与产品主次) · [字幕](#字幕排版预留画面空间并检查碰撞) · [发音](#发音预检--tts--装配) · [成片](#成片验收技术检查与实际试听分开) · [发布](#发布范围历史与导出)。

## 新项目：主题、Agent、轮次

从工作区启动器调用以下 studio 子命令；Windows 使用 `RUN-STUDIO-WINDOWS.ps1 -Task studio ...`，Unix 使用 `bash run-studio.sh studio ...`。

```text
new --topic product-intro --agent workbuddy --model GLM-5.3-Flash --run-id demo --title "从一个选题到一条视频"
list --topic product-intro
```

新任务应使用 `--topic` 和 `--agent`；能核实当前模型时再传 `--model`，不得猜测。`--run-id` 不传时自动生成 UTC 分钟+随机后缀（例如 `202610172025-abcde`）。**目录/内容 ID 为 `<topic>-<agent>-<model_slug>-<run_id>`**，例如 `product-intro-workbuddy-glm-5-3-flash-demo`；没有可靠模型名时目录含 `model-unknown`，而 `model_id` 保持 null。模型原名不修改，路径使用小写、数字、连字符及必要时带哈希的截断标签。整个内容 ID 最长 64 字符；过长时先缩短模型标签（保留哈希以区分不同模型），仍放不下则要求缩短 topic 或 run-id；原项目不重命名。

`content.json` schema 4 包含 `content_id/topic_id/agent_id/model_id/model_slug/run_id/skill_version`、创建时间、初始发布范围和可选 parent。身份是当前宿主声明，不是身份认证。后续脚本、音轨检查、渲染记录和平台包可通过该身份追溯；平台包额外提供 `<content_id>.mp4` 建议导出文件名。内部 `video/master.mp4` 路径保持兼容。

同一主题的独立 A/B 作品使用相同 topic、不同 Agent/轮次；接力创作加 `--parent-id <来源ID>`，会记录源 content/script/video 已存在文件的哈希，**不会复制、修改源文件或扩大原发布授权**。源主题不符、ID 已占用、非法路径会在创建前拒绝。一个内容 ID 同时只允许一个写者；本版本不是并发协作锁系统。

旧 `new --id ...` 仅保留迁移兼容（schema 3），缺少作者则记录 `unknown`、模型 null；不能靠旧目录名字推断归属，也不自动移动旧项目。`list` 可显示旧记录，但旧内容不会被伪装成已经具有新质量证据。

## 脚本与产品主次

`brief.md` 说明观众、核心价值、次级优势、证据，以及仅用于测试报告的工程事项。新项目 `script.json` 需要以下策划结构，其他既有字段不变：

```json
{
  "editorial_intent": {
    "audience": "需要降低视频制作操作负担的小团队",
    "primary_value": "把一个内容需求自动推进到视频交付",
    "secondary_values": ["环境可以被不同宿主复用"],
    "evidence_plan": ["展示从脚本修改、配音字幕到成片的真实过程"]
  }
}
```

该例只演示字段，不是所有产品的固定定位。`title/narration/shots/duration_seconds` 由 Agent 真实编写；分镜每项有 `seconds/visual/voiceover`，时间之和应等于总时长。

只制作 MP4 时可省略 `platforms/article_markdown`。需要平台包时才补目标平台的 title、tags 和适配文案；支持 `xiaohongshu/douyin/tencent/bilibili/kuaishou/wechat_oa/zhihu`。只有公众号/知乎图文交付需要完整 `article_markdown`，不为凑字段生成占位文章。

`review.json` 保留 `result/checks/facts_to_verify/issues/script_sha256/review_standard_sha256`；schema 4 另须 `focus_alignment: {"result":"PASS","reason":"具体口播、镜头如何服务主线的依据"}`。CLI 检查结构和版本，不会替 Agent 理解观众或判断主次是否真的正确。禁止以“填了字段”“环境检查通过”冒充内容质量。

## 字幕排版：预留画面空间并检查碰撞

烧录字幕时不能把正文卡片和字幕独立地画到同一高度。1080×1920 的程序化竖屏画面推荐使用：
- **主要内容区**：重要文字、卡片、图表的底边不超过画高 72%（1920p 约 y=1382）；
- **字幕专用区**：高度 76%～92%（约 y=1459～1766），两侧至少 7%（约 76 像素），字幕最多两行；不在此区放页脚注释、手机框或其他重要信息。
- **平台 UI 预留**：92% 以下不应放必须阅读的信息，考虑各平台控件的实际遮挡。

`studio render --subtitles` 的默认 SRT 样式以实际视频宽高设置 ASS 坐标、字号和边距，避免虚拟坐标缩放使双行字幕侵入正文。该默认值不保证任意长文本或字体都能装下，仍须检查实际行数和画面。

按实际渲染方式检查文字占位：Pillow 可用实际字体的 `textbbox`，网页渲染器测量最终 DOM；连同背景条、描边计算 bounding boxes。可按镜头输出布局 JSON，例如：

```json
{"width":1080,"height":1920,"shots":[{"content_boxes":[[90,200,990,1320]],"subtitle_boxes":[[90,1490,990,1680]]}]}
```

运行 `python scripts/subtitle_layout.py --layout <布局文件.json>`，失败必须移开冲突元素、重新计算布局再渲染。**此工具只检查渲染器声明的坐标，不自动识别 MP4 里的物体。** 成片后仍需从最终 MP4 的每个含字幕镜头抽取字幕正在显示的帧，检查字幕是否压住正文、内容卡片、底部说明及文字自身换行。`video/review.json` 中应独立记录字幕无遮挡检查的具体时间点；无实际画面核对证据不能以“SRT 正确”“字幕可读”冒充布局 PASS。

## 发音预检 → TTS → 装配

```text
speech-plan --id <内容ID> --tts-engine <实际服务> --voice <实际音色>
hash --id <内容ID>
voiceover --id <内容ID> --takes <镜头1.wav> <镜头2.wav> ...
render --id <内容ID> --materials <合法剪辑...> --rights-confirmed --audio <项目>/work/narration.wav
```

`speech-plan` 本身不调用语音服务，也不保证发音正确。它会：

- 核对 `narration` 与各镜头 `voiceover`；已有 `subtitle_text/subtitle_lines` 也必须一致（允许标点/空格变化）。
- 口播内部不得包含排版换行或制表符；字幕折行只保留在显示字段。分段与试听原则见 [口播、镜头与字幕](QUICK_VIDEO.md#口播镜头与字幕)。
- 读取套件 `config/pronunciation.json` 中的已知易错词；可合并用户知识库的 `pronunciation.json`（同名词条以后者为准）。词典 schema=1，每项有 term、expected_reading、suggestion。默认只覆盖一组已知风险，不是完整汉字注音引擎。
- 命中“重复”等词时输出 `work/speech-plan.json` 的 REVISE 和改写建议，退出2。Agent 按语境保留原义改写正式脚本及字幕，然后 `speech-plan ... --replace`；不全局替换单个汉字，不把拼音当字幕，不自行改为 READY。
- READY 时导出 `work/tts-inputs/<脚本哈希>/shot-NNN.txt`。记录脚本/词典/文本哈希、服务、音色及 `pronunciation_verified=false`。这只表示已知文字风险已处理，**不是音频已经试听过**。

Agent 使用导出的完整语义段生成 WAV，再经 `studio voiceover` 交给 FFmpeg 装配；当前接口每个分镜对应一份 WAV，分镜内可包含多个画面变化。装配在每段起点加 0.15 秒，音频连同该偏移必须装得下；不手写重采样，不加速硬塞。报告记录原始 WAV 哈希、当前脚本、speech-plan、服务音色和创作归属。

脚本或词典改变后更新计划与审核；这不意味着所有配音都要重新合成。对照新旧计划的 `text_sha256/tts_engine/voice`，文本和实际合成设置未变的 take 可以复用；文本或音色变化才重做受影响段。镜头时长变化后重新装配、同步字幕，并更新当前版本的音轨报告。旧计划或旧报告不能直接冒充新版本验收。

默认用**保留原义的上下文改写**规避已知风险，例如“重做”可改“再做一遍”，不能改成含义不同的“对齐”。风险命中不等于已经听到错读，也不应为展示返工流程而刻意制造错误。

不内置某家服务的 phoneme/SSML 适配。不能假设 edge-tts 接受任意自定义 SSML；见其[上游说明](https://github.com/rany2/edge-tts#custom-ssml)。必须保留原词并指定读音时，先验证实际引擎能力。改稿后重新审核最终脚本。

## 成片验收：技术检查与实际试听分开

工程门禁会重新解码真实 MP4，检查有口播分镜的有效声音、异常静音、时长和版本哈希。它主要拦截严重技术异常，不能把“停顿未超过阈值”判成自然，也不能识别每个词内断句。波形、ASR 和输入文字只作辅助。

`video/review.json` 保留当前 `video_sha256/script_sha256/review_standard_sha256`、checks、issues、facts_to_verify。新项目还需：

```json
{
  "pronunciation_check": {
    "result": "PASS",
    "method": "actual_audio_review",
    "speech_plan_sha256": "studio hash 输出的真实值",
    "evidence": [
      {"start": 0.0, "end": 4.5, "note": "实际听到的词句、读音与语气核对结果"}
    ]
  }
}
```

以上只是结构示例，不能复制成真实验收证据。CLI 校验时间段与绑定关系，不能鉴别调用者是否真的试听；Agent 必须基于实际音频输入填写。还需核对中文/英文词、数字、字幕时序与各镜头首/中/尾画面。没有试听能力则 `BLOCK`、如实交付技术测试 MP4 和未验收项；不得以主观分数、ASR 或伪造 evidence 绕过。无需用户逐阶段审批。

## 发布范围、历史与导出

默认内容创建的 `publish_targets` 为空，只制作不投稿。只有用户初始任务明确给出平台和账号，才可在 `new` 时传 `--publish-target platform:account`（同平台不重复）。脚本修改、parent 接力或打包不能自动增加权限；新任务也不继承 parent 的发布权限。

`studio package --platform <目标平台>` 对审核通过的当前版本生成指定平台包，只检查该平台的文案；省略参数或指定 `all` 时保留全平台打包。`publish --execute` 再核对初始范围和实际工具/登录态。退出码0仍是 `submitted_unknown`，需核对官方作品链接再 `confirm-published`；未知状态不盲重试。公众号/知乎没有经验证通用投稿适配时仅输出图文包。

所有正式产物保存在 `workspace.json.output_root/<内容ID>/`；批量选题文件名带 Agent/轮次。共享目录并不意味着允许改写他人结果，也不自动提供同步锁。升级不覆盖企业自有词典、原始资料或历史成片。
