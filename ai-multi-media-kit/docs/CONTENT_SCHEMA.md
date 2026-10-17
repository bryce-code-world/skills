# 内容归属、发音准备与质量契约

## 新项目：主题、Agent、轮次

从工作区启动器调用以下 studio 子命令；Windows 使用 `RUN-STUDIO-WINDOWS.ps1 -Task studio ...`，Unix 使用 `bash run-studio.sh studio ...`。

```text
new --topic product-intro --agent workbuddy --run-id demo --title "从一个选题到一条视频"
list --topic product-intro
```

新任务应使用 `--topic` 和 `--agent`；`--run-id` 不传时自动生成 UTC 时间+随机后缀。目录/内容 ID 为 `<topic>-<agent>-<run_id>`，不超过64字符，topic 最多24、agent 最多16、run-id 最多22字符（小写字母、数字、连字符）。`--model` 仅记录宿主可核实的实际模型名，未知省略。

`content.json` schema 4 包含 `content_id/topic_id/agent_id/model_id/run_id/skill_version`、创建时间、初始发布范围和可选 parent。身份是当前宿主声明，不是身份认证。后续脚本、音轨检查、渲染记录和平台包可通过该身份追溯；平台包额外提供 `<content_id>.mp4` 建议导出文件名。内部 `video/master.mp4` 路径保持兼容。

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

该例只演示字段，不是所有产品的固定定位。`title/narration/shots/duration_seconds/platforms/article_markdown` 仍由 Agent 真实编写；分镜每项有 `seconds/visual/voiceover`，时间之和应等于总时长。平台使用 `xiaohongshu/douyin/tencent/bilibili/kuaishou/wechat_oa/zhihu`，每个平台至少有 title、tags。

`review.json` 保留 `result/checks/facts_to_verify/issues/script_sha256/review_standard_sha256`；schema 4 另须 `focus_alignment: {"result":"PASS","reason":"具体口播、镜头如何服务主线的依据"}`。CLI 检查结构和版本，不会替 Agent 理解观众或判断主次是否真的正确。禁止以“填了字段”“环境检查通过”冒充内容质量。

## 发音预检 → TTS → 装配

```text
speech-plan --id <内容ID> --tts-engine <实际服务> --voice <实际音色>
hash --id <内容ID>
voiceover --id <内容ID> --takes <镜头1.wav> <镜头2.wav> ...
render --id <内容ID> --materials <合法剪辑...> --rights-confirmed --audio <项目>/work/narration.wav
```

`speech-plan` 本身不调用语音服务，也不保证发音正确。它会：

- 核对 `narration` 与各镜头 `voiceover`；已有 `subtitle_text/subtitle_lines` 也必须一致（允许标点/空格变化）。
- 读取套件 `config/pronunciation.json` 中的已知易错词；可合并用户知识库的 `pronunciation.json`（同名词条以后者为准）。词典 schema=1，每项有 term、expected_reading、suggestion。默认只覆盖一组已知风险，不是完整汉字注音引擎。
- 命中“重复”等词时输出 `work/speech-plan.json` 的 REVISE 和改写建议，退出2。Agent 按语境保留原义改写正式脚本及字幕，然后 `speech-plan ... --replace`；不全局替换单个汉字，不把拼音当字幕，不自行改为 READY。
- READY 时导出 `work/tts-inputs/<脚本哈希>/shot-NNN.txt`。记录脚本/词典/文本哈希、服务、音色及 `pronunciation_verified=false`。这只表示已知文字风险已处理，**不是音频已经试听过**。

Agent 使用导出的文本生成逐镜头 WAV，再经 `studio voiceover` 交给 FFmpeg 装配，不手写重采样，不加速硬塞时长。报告记录原始 WAV 哈希、当前脚本、speech-plan、服务音色和创作归属。schema 4 的 FFmpeg 渲染必须引用匹配的音轨与装配报告。改稿、换音色或更新词典后旧计划/音轨不再可用；旧渲染与新计划不匹配时不能通过验收。

本版默认处理方式为**上下文改写规避风险**，不内置某家服务的 phoneme/SSML 适配。不能假设 edge-tts 接受任意自定义 SSML；见其[上游说明](https://github.com/rany2/edge-tts#custom-ssml)。如必须保留原词并指定读音，需要另行验证实际语音引擎的能力，不能仅靠追加标签或拼音声称已解决。

## 成片验收：技术检查与实际试听分开

工程门禁会重新解码真实 MP4，检查有口播分镜的有效声音、异常静音、时长和版本哈希。波形正常、ASR 转写正常、TTS 输入文字正确，都不能证明声调/自然度正确。

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

`studio package` 对审核通过的当前版本生成平台包；`publish --execute` 再核对初始范围和实际工具/登录态。退出码0仍是 `submitted_unknown`，不能声称已公开发布，需核对官方作品链接再 `confirm-published`；未知状态不盲重试。公众号/知乎没有经验证通用投稿适配时仅输出图文包。旧人工审批记录仅作历史，不恢复逐阶段人为审批流程。

所有正式产物保存在 `workspace.json.output_root/<内容ID>/`；批量选题文件名带 Agent/轮次。共享目录并不意味着允许改写他人结果，也不自动提供同步锁。升级不覆盖企业自有词典、原始资料或历史成片。
