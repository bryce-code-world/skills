# 平台 Markdown 契约

公众号、知乎、CSDN 和掘金文章统一使用 front matter 保存唯一发布标题，并使用相同的正文图片语义。

## 文件结构

```markdown
---
platform: wechat
title: "平台文章标题"
summary: "可选摘要"
cover: "assets/<platform>/cover.png"
source: "<权威内部底稿路径>"
references:
  - name: "外部资料名称"
    url: "https://example.com/source"
---

这里直接开始导语。

## 第一个正文小标题
```

必须满足：

- 文件第一行是 `---`；
- front matter 包含非空 `platform` 和 `title`；
- `cover` 指向当前平台最终封面；封面尚未生成时不得把发布包标记为视觉验收通过；
- `source` 指向权威内部底稿，不指向 `00-广播任务总结.md` 或另一个平台稿；
- `references` 是可选的外部引用追溯清单，每项使用 `name` 和 `url`；它不属于发布正文，不生成文末来源章节；
- 公众号正文不保留外部链接时，把支撑正文事实的完整地址写入 `references`，正文只按需要保留普通文本形式的机构、报告或实验名称；
- front matter 在正文前闭合；
- 正文第一个非空内容是导语，不重复标题；
- 正文不出现 `# 标题`；
- 正文小标题从 `##` 开始；
- 每个平台文章只有一个发布标题来源。

## 正文图片语义

信息型正文图统一写成：

```markdown
![准确的替代文字](assets/shared/example.png)

图注：读者应从图中理解的核心关系
```

必须满足：

- `alt` 描述图片内容，供图片不可见和无障碍场景使用；它不是可见图注；
- 非空 `alt` 表示信息型图片，下一条非空内容必须是非空 `图注：`；
- `图注：` 只说明图片对当前论证的作用，不首次引入正文尚未解释的事实或概念；
- 纯装饰图使用空 `alt`，不得添加图注；
- 兼容读取紧邻图片的历史 `图：`，新产物统一写 `图注：`；
- 孤立图注、重复图注、信息图缺少图注和装饰图带图注均判定失败。

平台稿只保存语义真相。字体、字号、颜色、对齐、`figure` 或平台原生图注结构由 `distribution` 映射，不能通过把图注降级成普通正文完成投递。

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

任一平台稿缺少 front matter 标题、正文出现 H1、首段重复标题、正文为空或图片语义不完整时，检查失败，不进入发布。标题脚本只检查标题相关机械契约；图片语义由 Broadcast 验收和 Distribution 内容准备脚本检查。

标题检查器不验证 `cover` 文件、封面语义、入口承诺和全文传播效果。继续按 [platform-format-contract.md](platform-format-contract.md) 和 [communication-effects.md](communication-effects.md) 完成封面路径、渲染和五道传播门禁。
