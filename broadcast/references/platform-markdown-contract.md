# 平台 Markdown 标题契约

公众号、知乎、CSDN 和掘金文章统一使用 front matter 保存唯一发布标题，正文不再重复 H1。

## 文件结构

```markdown
---
platform: wechat
title: "平台文章标题"
summary: "可选摘要"
cover: "assets/<platform>/cover.png"
source: "<权威内部底稿路径>"
---

这里直接开始导语。

## 第一个正文小标题
```

必须满足：

- 文件第一行是 `---`；
- front matter 包含非空 `platform` 和 `title`；
- `cover` 指向当前平台最终封面；封面尚未生成时不得把发布包标记为视觉验收通过；
- `source` 指向权威内部底稿，不指向 `00-广播任务总结.md` 或另一个平台稿；
- front matter 在正文前闭合；
- 正文第一个非空内容是导语，不重复标题；
- 正文不出现 `# 标题`；
- 正文小标题从 `##` 开始；
- 每个平台文章只有一个发布标题来源。

## 固定输出编号

```text
00-广播任务总结.md
01-公众号文章.md
02-知乎文章.md
03-CSDN文章.md
04-掘金文章.md
05-验收报告.md
06-读者测试.md
```

未选择或未通过门禁的平台保留缺号。发布时以 front matter 的 `platform` 为准，不根据编号猜平台。

## 机器检查

运行当前系统原生脚本：

```text
Windows:
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/check_platform_title.ps1 -Path <文件或目录>

Linux / macOS:
sh scripts/check_platform_title.sh <文件或目录>
```

任一平台稿缺少 front matter 标题、正文出现 H1、首段重复标题或正文为空时，检查失败，不进入发布。

标题检查器不验证 `cover` 文件、封面语义、入口承诺和全文传播效果。继续按 [platform-format-contract.md](platform-format-contract.md) 和 [communication-effects.md](communication-effects.md) 完成封面路径、渲染和五道传播门禁。
