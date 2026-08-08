# 平台 Markdown 标题契约

本文件定义公众号、知乎、CSDN 和掘金平台稿共同遵守的标题结构。生成平台稿、执行平台验收或准备投递时必须读取。

## 标题只有一个发布来源

平台稿使用 front matter 的 `title` 作为发布标题。正文不再写文章一级标题，直接从导语开始，后续最高使用二级标题。

```markdown
---
platform: wechat
title: "推荐标题"
summary: "文章摘要"
source: "01-大众基础长文.md"
---

正文导语……

## 第一个正文小标题
```

对四个平台稿执行以下硬约束：

- front matter 必须包含目标平台和非空 `title`；
- 正文不得出现任何 `# 一级标题`；
- 正文第一个非空内容不得再次写出与 `title` 相同的纯文本标题；
- 正文必须从导语、场景、问题或判断开始；
- 正文小标题从 `##` 开始。

`01-大众基础长文.md` 是独立阅读的完整对外母稿，仍保留一个正文 H1。把母稿重构为平台稿时，将选定标题写入 front matter，并删除正文 H1。

不要依赖发布工具自动删除重复标题。不同入口对 front matter 和首个 H1 的处理并不一致，标题与正文必须在本地发布包中已经分离。

## 机器检查

平台稿生成和语言终检完成后，发布或交付前运行当前系统的原生检查器：

```text
Windows:
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/check_platform_title.ps1 -Path <file-or-directory>

Linux / macOS:
sh scripts/check_platform_title.sh <file-or-directory>
```

检查器只处理 front matter 中 `platform` 为 `wechat`、`zhihu`、`csdn` 或 `juejin` 的 Markdown 文件。缺少标题、正文为空、正文含 H1 或首段重复标题时返回失败。

检查器通过只能证明标题结构正确，不能替代事实、深度、传播、风格、平台格式和真实草稿验收。格式与渲染继续读取 [platform-format-contract.md](platform-format-contract.md)。
