<div align="center">

**中文** · [English](./README.en.md)

# ⚡ Bryce Skills

为自己与 AI 协作构建的实用 Skill。

</div>

这些 Skill 先解决自己的真实问题，再整理成可复用的开放指令。

仓库遵循通用的 `SKILL.md` 目录结构。

## Skill 清单

| Skill | 作用 |
|---|---|
| [闪电（lightning）](./lightning/SKILL.md) | 在不丢失关键信息的前提下，把内部文档整理成自己易读、AI 易于行动的形式。 |
| [声纹（writing-style）](./writing-style/SKILL.md) | 提炼、管理、选择并应用稳定可识别的个人图文表达风格。 |

## 安装

在支持 `SKILL.md` 的 Agent 中安装：

```text
帮我安装这个 Skill：
https://github.com/bryce-code-world/skills/tree/main/lightning
```

也可以把 `lightning` 目录复制到本地 Skill 目录。

安装声纹时，将链接或目录名替换为 `writing-style`。

## 闪电

适用于：

- 内部文档的创建、修改、整理和审查。
- 分析报告、设计方案、审查报告和任务说明。
- 零散材料和知识库内容的结构化整理。
- 为自己和 AI 准备可快速理解的任务上下文。

不适用于公众号、新闻、博客、论文、营销文案和文学创作。

核心原则：

> 在不丢失关键信息的前提下，把内容整理成最容易理解的形式。

使用示例：

```text
使用 $lightning 整理这份内部文档。
```

## 声纹

适用于：

- 从对话或历史文章提炼本人及他人的表达风格。
- 管理多个命名个人档案和一个默认档案。
- 为文章选择主风格和场景语气。
- 应用风格并检查跨平台一致性。

不会静默学习或修改档案，也不会冒充参照作者、虚构经历或为了风格改变事实。

使用示例：

```text
使用 $writing-style 从这些文章提炼我的个人风格，先展示候选档案，确认后再保存。
```

## License

[MIT](./LICENSE)
