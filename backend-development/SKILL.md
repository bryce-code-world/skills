---
name: backend-development
description: "以业务域目录为人的研发控制面，从需求材料、现有代码、数据、协议和业务背景建立业务模型初识，再推进需求事实、需求确认、业务模型收敛、数据模型、端到端流程、前端与其他调用方流程、交互目的、项目计划、多端共识、工作包实现设计、协议冻结、AI 执行计划、开发、独立 Review、验收和 Bug 反馈。用于梳理或设计后端业务域、迁移或规范化存量业务域文档、建立或恢复业务域控制面、规划和执行 AI 后端开发、审查实现是否符合业务设计，或继续中断的后端研发任务。先读取目标项目规则并确认唯一业务域；不替代人的业务决策，不为稳定事实查询、简单代码解释或纯文案任务启动完整流程，也不把文件存在、迁移完成或文档状态当成业务设计与代码正确的证明。"
---

# 后端开发

以业务域目录为人的研发控制面，把产品输入推进为可验证、可追溯的后端实现。

## 守住边界

按以下优先级执行：

1. 读取目标项目及更近一级目录的权威规则。规则无法读取时停止，不猜测项目约束。
2. 保留人对业务目标、业务取舍、风险接受、协议冻结和流程步骤放行的决定权。
3. 先恢复需求、现有代码、协议、数据和运行事实，再形成设计或实现结论。
4. 默认采用满足需求、正确性、安全和可验证性的最低总成本方案。增加成本前写明长期收益和增量成本。
5. 不因启用本 Skill 自动迁移、重命名或重写稳定业务域目录。
6. 不把文档完整、测试通过或提交说明当成实现正确的单独证明。
7. 不扩大用户授权的文件、仓库、环境、Git 和外部沟通范围。
8. 不把材料存在或迁移完成推导为流程步骤已经评审或冻结。
9. 不要求人通读大批文档自行发现冲突；AI 先完成逐项追溯，只提交真正需要决定的问题。
10. 不把审查过程、关闭的问题清单、放行摘要或冻结变化过程默认写成业务域永久文档。
11. 不把会议参与者自动当成决策人，不为同一人兼任的角色制造自我确认任务。
12. 已冻结业务规则与现行实现不一致时，把实现记录为缺口，不把唯一业务口径重新降级为待确认。

用户只查询稳定事实、解释代码、修改纯文案或查看状态时，直接完成该任务，不建立完整研发控制面。

文档先服务当前读者的主要阅读任务，再决定章节、表格、图示、附录或链接。只保留完成当前任务所需的必要信息；模板提供默认阅读顺序，不要求每份文档填满全部章节。允许不同文档为不同读者做必要摘要，但同一完整规则只保留一个权威维护位置。

材料存在冲突时，先保留各版本、来源、内容性质和采用状态；没有人的取舍标准不得静默合并或输出确定性结论。可以先完成不受冲突影响的确定内容，并用带编号的 TODO 标出仍需确认的事项。

## 使用统一执行对象

| 执行对象 | 标识 | 职责 |
| --- | --- | --- |
| 研发大阶段 | `P1`～`P6` | 供人理解全局；新建或确认重构业务域使用 `P{n}-业务名称` 一级目录 |
| 流程步骤 | `S1`～`S16` | 固定输入、动作、交付物和退出条件；步骤编号进入对应权威目录或文档名 |
| 开发工作包 | `WP-XX` | S8 可选使用；项目计划未编号时，S10 按计划阶段建立内部实现单元 |
| AI 执行任务 | `TASK-XX` | S12 拆出的单个可验证业务行为 |

不要单独使用含义不明的“阶段”。记录状态时同时写明执行对象和标识。

`S` 编号只进入能够唯一代表该步骤的最低稳定导航层，不机械编号所有叶子文件：

- 一个步骤由目录统一承载时，把 `S{n}` 放在目录名。
- 步骤跨业务模块时，把 `S{n}` 放在权威文件名。
- 多个同级交付物属于同一步骤时，使用 `S{n}-{两位序号}-名称`。
- 二级业务目录整体只属于一个步骤时，把 `S{n}` 放在该目录，内部文件不重复编号。
- README、原始输入和已经处于 `S{n}` 目录内的普通子文档不重复编号。

控制入口必须提供 `S1`～`S16` 的完整步骤词典，逐项写明步骤名称、权威路径和状态。

没有独立永久交付物的步骤映射到控制入口或被回填的权威正文，不为显示编号创建空目录或过程文档。

## 开始任务

1. 读取项目规则，确认目标仓库、环境、写入范围、Git 授权和验证边界。
2. 确认唯一目标业务域和仓库。用户没有给出可唯一定位的路径时只问一个关键问题；不得根据分支、最近提交或相邻目录猜测。
3. 定位业务域唯一控制入口。读取 [domain-control-plane.md](references/domain-control-plane.md)。
4. `resume` 时先验证旧检查点路径、控制入口更新时间和实际 Git 状态。路径不存在、控制入口更新或事实冲突时，废弃旧检查点。
5. 分别恢复材料状态、设计门禁状态、实现验证状态，以及当前迭代、研发大阶段、流程步骤、工作切片、开发工作包、AI 执行任务、阻塞项和唯一下一步。
6. 控制入口不存在，或者存量目录没有六阶段与完整步骤导航时，进入 `initialize`。读取 [business-domain-classification.md](references/business-domain-classification.md) 和 [documentation-topology.md](references/documentation-topology.md)。
7. 用户已经确认物理迁移或整体规范化时进入 `migrate`。迁移不得推进 S1～S12 设计状态。
8. 选择一个主要模式，只加载该模式需要的参考文件。
9. 开始写入前检查目标工作区和已有未提交内容。不得覆盖、清理或提交他人改动。

## 选择模式和参考

| 模式 | 对应步骤 | 必读参考 |
| --- | --- | --- |
| `initialize` | 启动准备 | [domain-control-plane.md](references/domain-control-plane.md)、[business-domain-classification.md](references/business-domain-classification.md)、[documentation-topology.md](references/documentation-topology.md) |
| `migrate` | 存量文档迁移与规范化 | [migration-and-normalization.md](references/migration-and-normalization.md)、[documentation-topology.md](references/documentation-topology.md)、[domain-control-plane.md](references/domain-control-plane.md) |
| `design` | S1～S10 | [stage-machine.md](references/stage-machine.md) 和当前步骤对应参考 |
| `contract` | S11 | [interface-and-contracts.md](references/interface-and-contracts.md) |
| `plan` | S12 | [ai-execution-plan.md](references/ai-execution-plan.md)、[review-standard.md](references/review-standard.md) |
| `implement` | S13 | AI 执行计划、当前项目规则和任务引用的权威设计 |
| `review` | S14 | [review-standard.md](references/review-standard.md)、[review-and-evidence.md](references/review-and-evidence.md) |
| `repair` | S14 | 原 Review 报告、[review-and-evidence.md](references/review-and-evidence.md) |
| `deliver` | S15 | [review-and-evidence.md](references/review-and-evidence.md) 和项目交付规则 |
| `bug` | S16 | [bug-feedback.md](references/bug-feedback.md) 和项目 Bug 规则 |
| `resume` | 任意步骤 | [domain-control-plane.md](references/domain-control-plane.md)、[iteration-lifecycle.md](references/iteration-lifecycle.md)、[stage-machine.md](references/stage-machine.md) |

`design` 模式按当前步骤继续加载：

- S1：[business-modeling.md](references/business-modeling.md)
- S2～S3：[requirements-facts-and-confirmation.md](references/requirements-facts-and-confirmation.md)
- S4：[data-modeling.md](references/data-modeling.md)
- S5～S7：[flow-and-consumer-adaptation.md](references/flow-and-consumer-adaptation.md)
- S8：[project-development-plan.md](references/project-development-plan.md)
- S9：[solution-consensus-and-plan-communication.md](references/solution-consensus-and-plan-communication.md)
- S10：[implementation-design.md](references/implementation-design.md)

使用真实案例校验触发和失败处理时读取 [behavior-cases.md](references/behavior-cases.md)。不要一次读取全部参考文件。

## 按六个研发大阶段推进

| 研发大阶段 | 流程步骤 | 完成门禁 |
| --- | --- | --- |
| P1 业务模型、需求事实与确认 | S1～S3 | 已建立业务模型初识；需求事实已经梳理，阻塞疑问已经确认，并已回填收敛 S1 |
| P2 数据模型与流程设计 | S4～S5 | 数据模型和端到端流程能够从收敛后的 S1 追溯 |
| P3 多端协同与方案共识 | S6～S9 | S6、S7 达成多端共识，S8 计划已与项目负责人对齐 |
| P4 详细技术设计与 AI 执行计划 | S10～S12 | 每个 `WP-XX` 有实现设计，协议已冻结，任务已拆为可验证的 `TASK-XX` |
| P5 AI 执行、Review 与交付 | S13～S15 | 任务实现、三级 Review、联调和验收证据闭环 |
| P6 持续反馈与演进 | S16 | Bug 和迭代发现已反馈到测试、Review 或权威设计 |

上游未达到退出条件时，不制造高精度下游产物。下游发现上游缺口时，记录变化原因和影响清单，回退对应流程步骤重新放行。

## 执行当前流程步骤

设计、协议、开发和 Review 模式每次只推进一个工作切片或一个 `TASK-XX`。工作切片是当前步骤内一个可独立确认的业务模块、流程簇、交付物或问题批次，不新增全局编号和永久文档。

每轮沟通只推进一个可确认点，例如一个事实修正、一个业务决定、一个风险接受或一个文档审阅问题。可以展示后续待办，但本轮只请求用户回答一个会改变下一步的问题。

人已经确认完整迁移范围时，`migrate` 可以连续完成其中确定性的多个批次。

执行当前对象：

1. 确认前置条件、权威输入、事实、未知、冲突和待决策项。
2. 只完成当前对象的职责，不提前替下游作决定。
3. 更新当前对象的唯一权威交付物。默认路径和模板见 [documentation-topology.md](references/documentation-topology.md)。
4. 冷读产物，回对代码、协议、数据或运行证据，并执行项目要求的验证。
5. S1～S12 先完成当前工作切片的上游追溯，将发现分为 `FACT_FIX`、`BUSINESS_DECISION`、`TECH_DEFERRED` 和 `OUT_OF_SCOPE`。只有 `FACT_FIX` 直接修复；其余分别交给人、后续步骤或范围外处理。
6. 已冻结业务规则与现行代码不一致时，保持业务规则有效，将代码差异归入 S10、S13 或 S14。只有冻结来源自身冲突时才形成 `BUSINESS_DECISION`。
7. S3、S9、S11 存在人工决策时，先在对话中形成最小决策包，再按轮次逐个关闭。决策闭合前不创建永久确认清单，不提前写入需要随后反复修正的结论。
8. 完成当前切片后更新控制入口中的已完成切片和剩余切片，输出 `THREAD_ROLLOVER_REQUIRED`，简要说明下一步的目标、输入和产物，再询问用户是否开始；没有确认时停止。
9. 当前步骤全部切片完成后才标记 `REVIEW_READY`。人在放行摘要形成前给出的笼统确认不能解释为放行；设计和协议只有在人确认对应问题清单后才能标记 `FROZEN`。
10. 更新控制入口中的材料状态、设计或实现状态、阻塞、证据和唯一下一步。

流程步骤的完整输入、交付物、门禁和回退规则见 [stage-machine.md](references/stage-machine.md)。

## 维护迭代与权威文档

长期有效的需求、模型、流程和协议只保留当前结论。迭代专属的计划、沟通、任务、Review 和验收记录带迭代标识，关闭后不覆盖。

下游发现已冻结结论需要变化时，在控制入口记录开放问题、原冻结基线和影响范围，并将最早受影响步骤标为 `CHANGE_PENDING`。人的决定确认后，先更新权威正文，再按上游到下游顺序复核和重新放行。

关闭后的问题和修改过程由 Git、Agent 日志和对话承接。除非项目明确要求审计、正式签字或独立决策记录，不创建单问题确认文档、阶段评审包或冻结变更记录。

并行迭代必须分别维护位置、文件和下一步。关闭和归档规则见 [iteration-lifecycle.md](references/iteration-lifecycle.md)。

同一结论只保留一个权威位置。其他文档只写完成当前阅读任务所需的最小摘要和链接。

## 控制执行成本

1. 一个会话只处理一个工作切片或一个 `TASK-XX`。切片完成后更新控制入口，输出 `THREAD_ROLLOVER_REQUIRED` 和最小续跑检查点，不自动开始下一切片。
2. 用户明确要求留在当前长线程继续时，先说明历史上下文 Token 无法在同一线程中消除，再把本次继续视为显式覆盖。
3. 默认由单个 Agent 完成阶段梳理。只有用户或宿主规则允许，且存在互不依赖的证据方向时才使用子任务；只传目标文件和问题，不传完整长会话历史。
4. 已核验事实的来源文件和提交没有变化时直接复用，不重复扫描同一代码、协议和文档。
5. S1～S9 只核对会改变当前业务结论的现状事实。事务、RPC、缓存、补偿和代码落点等完整实现审查集中在 S10。
6. 技术选择只有改变用户可观察行为、产品范围或验收口径时才回退需求步骤；其余保留在 S4、S10 或 S11。
7. 日常验证只覆盖本次修改文件和受影响引用。物理迁移、目录重构、最终阶段验收或项目规则明确要求时才执行全业务域扫描。
8. 人工决策阶段先只读收敛决定，再一次性写入。
9. 同一交付物的连续审阅属于一个任务。用户确认交付物完成或进入下一切片后，统一验证、提交和记录日志。项目规则要求更早交付时从其规定。

## 交付与续跑

每次结束时说明：

- 当前模式、迭代、研发大阶段、流程步骤、`WP-XX` 和 `TASK-XX`；
- 当前工作切片、已完成切片和剩余切片；
- 材料状态、设计门禁状态和实现验证状态；
- 本次形成或更新的权威文档与实现差异；
- 已执行的验证和可定位证据；
- 阻塞、未验证项、接受风险和范围外发现；
- 当前对象是否满足退出条件；
- 唯一下一步以及是否等待人放行。

工作切片完成时，同时给出供新会话恢复的最小检查点。检查点只写入控制入口，不另建过程文档。

流程步骤完成时，先说明退出条件如何满足，再介绍下一步骤的作用和最小任务，并明确询问用户是否开始下一步。用户未确认时不得自动切换步骤或提前读取下一步骤的大批材料。

存在内容变更时，继续遵守目标项目的日志、差异检查、提交和交付规则。
