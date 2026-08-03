---
name: visual-cognitive-learning
description: "把已经梳理清楚的主题文档转译成可观察、可操控、可逐步理解的离线单文件 HTML 学习模型。用于可视化复杂事物从简单起点到当前形态的演化、方案形成过程与设计权衡、SOP、业务流程、状态机、因果系统、数学公式与参数关系、物理机制与连续变化、层级或抽象关系，以及用户要求从文档生成可交互学习或方案展示 HTML 时。不用于普通 Markdown 转 HTML、文章排版、通用网站或仪表盘、纯静态图表，也不在交互无助于理解时强行添加动画。"
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
- 一次只处理一个认知任务的引导步骤，以及完成后承载整体关系的总览。
- 当前任务、可见主体、主动作、前进/后退/分支和总览节点之间的最小状态映射。
- 必须始终成立的不变量。
- 边界、反例、异常和未进入模拟的未知项。

主模型是演化轨迹时，再明确简单起点、每次转变的推动问题、继承/新增/改变/淘汰的结构、获得的收益、新代价、可能分支和当前形态中仍可见的历史痕迹。不把“后来发生”写成“必然如此”。

读取 [learning-design.md](references/learning-design.md) 决定如何降低理解成本，读取 [interaction-routing.md](references/interaction-routing.md) 选择一个主模型。如果无法明确“做什么”和“看到什么变化”，使用准确的静态图示，不强行交互。

## 实现单文件 HTML

写代码前读取 [offline-html-contract.md](references/offline-html-contract.md)。

1. 先设计学习者动作、反馈、不变量和边界，再设计外观。
2. 从语义 HTML 与 CSS、原生控件与 DOM、内联 SVG、Canvas 中选择最低足够复杂度。
3. 将主要学习路径拆成单一认知步骤；同一时刻只强调一个当前问题、一个视觉主体和一个主动作。
4. 学习态不平铺完整阶段导航、图例、事实分类和辅助控件；完成主要路径后提供可回看节点的全局总览。
5. 学习和教学型方案默认从局部问题走向全貌；决策型方案可以先给一句结论或简化全貌，再逐项展开依据与权衡，最后回到完整方案。
6. 用同一状态来源驱动进度、主对象、活动视图和总览节点；一个控件只承担一个意图，视图切换不得暗中重置学习状态。
7. 从主题的真实对象、工具和表达习惯推导视觉语言，不复用固定页面模板。
8. 将 CSS、JavaScript、SVG、数据和图标全部内联；最终产物只有一个 `.html` 文件。
9. 保留语义结构、键盘操作、可见焦点、窄屏布局、`prefers-reduced-motion` 和 JavaScript 失败时的核心静态内容。

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
