---
name: visual-cognitive-learning
description: "把已经梳理清楚的主题文档转译成可观察、可操控、可逐步理解的离线单文件 HTML 学习模型。用于可视化 SOP、业务流程、状态机、因果系统、数学公式与参数关系、物理机制与连续变化、层级或抽象关系，以及用户要求从文档生成可交互学习 HTML 时。不用于普通 Markdown 转 HTML、文章排版、通用网站或仪表盘、纯静态图表，也不在交互无助于理解时强行添加动画。"
---

# 可视化认知学习

识别知识中最难靠文字理解的关系，将它编译成学习者能够亲手操控、亲眼验证的单文件 HTML。

## 维护依赖与版本

每次触发时读取 [dependencies.md](references/dependencies.md)，按其 24 小时规则执行非阻塞自身更新检查。

只在当前任务确实需要时调用可选 Skill 或浏览器能力。依赖缺失不得降低事实、离线、安全或无障碍底线。

## 守住输入门禁

1. 读取主题文档、必要来源和适用的项目规则。
2. 读取 [source-and-learning-contract.md](references/source-and-learning-contract.md)，建立内部来源账本。
3. 如果核心定义、流程、公式、单位、边界或异常仍冲突或缺失，先使用当前已暴露的 `lightning` 整理；不可用或仍不清楚时，停止对应的模拟，不自行补造机制。
4. 确定一个主要学习目标。用户没有说明学习者时，按愿意探索的成年初学者处理。

## 先建学习模型

在写 HTML 前，完成内部学习规格：

- 主要学习目标与理解障碍。
- 主知识关系与主认知模型。
- 学习者动作与可观察反馈。
- 必须始终成立的不变量。
- 边界、反例、异常和未进入模拟的未知项。

读取 [learning-design.md](references/learning-design.md) 决定如何降低理解成本，读取 [interaction-routing.md](references/interaction-routing.md) 选择一个主模型。如果无法明确“做什么”和“看到什么变化”，使用准确的静态图示，不强行交互。

## 实现单文件 HTML

写代码前读取 [offline-html-contract.md](references/offline-html-contract.md)。

1. 先设计学习者动作、反馈、不变量和边界，再设计外观。
2. 从语义 HTML 与 CSS、原生控件与 DOM、内联 SVG、Canvas 中选择最低足够复杂度。
3. 让第一屏直接出现主学习对象和最小控件，不创建宣传式 Hero、统计卡或多余导航。
4. 从主题的真实对象、工具和表达习惯推导视觉语言，不复用固定页面模板。
5. 将 CSS、JavaScript、SVG、数据和图标全部内联；最终产物只有一个 `.html` 文件。
6. 保留语义结构、键盘操作、可见焦点、窄屏布局、`prefers-reduced-motion` 和 JavaScript 失败时的核心静态内容。

## 验证与交付

读取 [validation.md](references/validation.md)，完成事实与模型、离线与静态、浏览器与无障碍、认知四层验收。

确定性校验遵守 [html-validation-contract.md](references/html-validation-contract.md)：

```text
Windows:
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate_html.ps1 check --path <html-file>

Linux / macOS:
sh scripts/validate_html.sh check --path <html-file>

原生适配器不可用时：
python scripts/validate_html.py check --path <html-file>
```

静态校验只发现机械违规，不能证明模型正确或真的有助于理解。没有实际运行的检查不得声称通过。

交付时：

- 只交付最终 HTML，不附带临时文件、CSS、JavaScript、图片或内部学习规格。
- 简要说明主要交互、已实际执行的验证和未模拟的未知项。
- 不静默覆盖已有 HTML；使用新文件名，或先获得明确替换授权。
