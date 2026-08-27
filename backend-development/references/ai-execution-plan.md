# AI 执行计划

S12 把工作包实现设计和冻结协议转成可逐项独立执行、验证、Review 和续跑的任务。

## 建立执行基线

1. 建立需求点到业务模型、数据模型、S5 子业务与流程、调用方流程、协议、实现和测试的追溯矩阵。
2. 建立正常、异常、边界、权限、并发、依赖失败、迁移和回滚用例。
3. 按 `WP-XX` 分组，再按真实技术依赖排列任务。
4. 为当前业务生成任务级、工作包级和整体级 Review 清单。

使用 [traceability-matrix.md](../assets/templates/traceability-matrix.md) 和 [business-review-checklist.md](../assets/templates/business-review-checklist.md)。

## 拆分 `TASK-XX`

每个任务只实现一个可验证业务行为，并固定：

- 目标行为和预期结果；
- 所属迭代、`WP-XX` 和任务标识；
- 前置任务和权威设计；
- 涉及仓库、服务、允许修改文件和禁止事项；
- 输入、异常、权限、并发和依赖失败边界；
- 失败验证命令、通过标准、回归范围和 Review 检查点；
- Git、环境和外部沟通授权；
- 断点续跑、阻塞和止损条件。

任务仍需跨多个开放业务边界、无法独立验证或需要 AI 自行补充业务决定时继续拆分，不进入 S13。

使用 [ai-execution-plan.md](../assets/templates/ai-execution-plan.md)。

## 执行规则

S13 一次只执行一个 `TASK-XX`。先重新读取项目规则和任务引用，再按项目测试与实现流程完成开发、验证和差异检查。

任务完成后使用 [task-execution-record.md](../assets/templates/task-execution-record.md) 记录实际差异、命令、证据、未验证项和下一任务。不得借实现、测试或重构扩大范围。
