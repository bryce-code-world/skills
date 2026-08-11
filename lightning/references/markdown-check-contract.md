# Markdown 机械护栏协议

## 边界

原生检查器只发现可以机械确定的问题：

- 未闭合的反引号或波浪线代码围栏；
- 指向不存在文件或目录的本地 Markdown 链接；
- 重复定义的 `TODO-NN`；
- 原文与成稿之间需要人工复核的高风险字面量差异。
- 需要人工复核的高负载正文句子。

高负载句子只是复核候选，不是机械错误。检查器不能证明事实完整、语义正确、结构合理或文档易懂。脚本通过后，仍要执行 `lightning` 的来源账本核对和全文自检。

## 适配器

| 系统 | 命令 |
|---|---|
| Windows | `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/check_markdown.ps1` |
| Linux、macOS | `sh scripts/check_markdown.sh` |

不要求 Python、Node.js 或第三方包。

## 命令

```text
check --path <markdown-file-or-directory>
readability --path <markdown-file-or-directory>
compare --source <source-file> --output <markdown-file>
self-test
```

`check` 对目录递归检查所有 `.md` 文件。

`readability` 排除 YAML frontmatter、标题、表格行、代码围栏和 Markdown 链接目标后，筛选满足任一条件的正文句子：

- 不少于 55 个可见字符；
- 包含至少 3 个逗号、分号或冒号。

结果中的 `review_required` 表示存在候选。Agent 必须判断候选是否包含多个规则单元，不能按字符数或标点数自动拆句。

`compare` 同时检查成稿的机械完整性，并比较以下精确字面量：

- UUID；
- Markdown 行内代码；
- 数字、范围、百分比及常见单位；
- Markdown 中的本地链接目标。

`source_only` 和 `output_only` 只是复核线索。压缩、下沉到附录或增加准确说明都可能产生合理差异，Agent 必须回到来源判断，不能按脚本结果自动补写或删除内容。

## 链接口径

- 检查普通链接、图片链接和引用式链接定义。
- 跳过 `http:`、`https:`、`mailto:`、`data:` 等带协议目标和纯锚点。
- 支持不含空格的普通目标，以及用尖括号包裹的含空格目标。
- 只检查链接目标是否存在，不检查标题锚点是否存在。
- 文件名不得包含换行符。

## 输出和退出码

输出 UTF-8 JSON。

| 退出码 | 含义 |
|---:|---|
| `0` | 机械检查通过；`compare` 可能仍有待人工复核差异 |
| `1` | 发现未闭合围栏、失效链接或重复 TODO 定义 |
| `2` | 参数、路径、读取或运行失败 |

`compare` 只有在成稿的机械检查失败时返回 `1`。字面量存在差异时返回 `0`，并设置 `review_required: true`。

`readability` 在成功完成扫描时始终返回 `0`，并通过 `review_required` 和 `warnings` 输出人工复核线索。参数、路径或读取失败时返回 `2`。
