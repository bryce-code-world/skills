# 可选编排

仅在核心能力不足以完成当前任务时读取本文件。

不要把可选编排变成固定流水线。

准备调用外部 Skill 前，先确认它出现在当前 Agent 的可用 Skill 列表中。不可用时执行本文件声明的降级方案，不在本 Skill 中安装或更新外部能力；不要仅凭本地目录存在就声称可用。

## 图示

目标环境支持 Mermaid，且只需在文档内展示时，直接生成 Mermaid。

需要独立 SVG、PNG 或可编辑 Excalidraw 文件时，调用可用的 `gstack/diagram`。

需要特定图示语法时，按内容选择可用的 `markdown-viewer` Skill：

- 流程、时序、状态、类和依赖关系：`uml`。
- 系统分层和微服务：`architecture`。
- 业务流程：`bpmn`。
- 数据图表：`vega`。
- 指标、时间线和方案对比：`infographic`。
- 概念关系：`mindmap` 或 `canvas`。
- 云、网络、安全、数据链路和物联网：使用同名专项 Skill。

同一张图只选择一种实现。

外部图示 Skill 不可用时，退回 Mermaid、表格或紧凑 ASCII 图。

## 文档库治理

只在用户明确要求整理文档库或知识库时调用可用的 `neat-freak`。

将其用于去重、合并、归档和入口收敛，不用于普通文档写作。

涉及已有文件的移动、删除或同步时，先获得用户确认。

## 项目与领域能力

用户、项目规则或目标格式指定专项 Skill 时，按需调用。

让专项 Skill 提供领域结构、专业约束或文件处理能力。

最终结构、表达和质量仍由 `lightning` 负责。

## 独立读者

不要调用完整的 `doc-coauthoring`。

需要读者测试时，使用无讨论上下文的独立读者能力。

只传入最终文档、主要阅读任务和检查问题。

要求其只报告问题和位置，不直接重写文档。

## 不直接调用

- `ljg-plain`：只吸收简单词汇、一次说清和删除废话等原则。
- `doc-coauthoring`：只吸收必要上下文检查、全文复查和独立读者测试。
- `gstack/document-generate`：完整铺开与轻量核心冲突。
- `khazix-writer`：面向公众号长文。
- `baoyu-article-illustrator`：面向对外文章配图。

`ai-writing-auditor` 是 Agent 配置，不是 Skill。
