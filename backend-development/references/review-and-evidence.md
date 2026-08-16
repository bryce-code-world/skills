# Review 与证据闭环

## 建立追溯矩阵

至少映射：需求点、业务模型、数据模型、整体流程、调用方流程、交互清单或协议、实现位置、测试证据和 Review 状态。

不存在设计依据的实现、没有实现位置的协议、没有测试证据的高风险规则不能判为完成。

使用 [traceability-matrix.md](../assets/templates/traceability-matrix.md)。

## 执行 Review

按任务级、工作包级和整体级分别审查。每一级都执行项目规范、业务符合性、风险和证据四层检查，并明确未执行项。

使用 [review-report.md](../assets/templates/review-report.md)。报告包含目标、范围、基线、权威文档、实际检查对象、发现、证据、严重度、修复方向、未执行项和剩余风险。

Review 报告不复制现行设计。长期结论变化时更新权威设计并从报告链接。

## 发现状态

| 状态 | 含义 |
| --- | --- |
| `OPEN` | 问题已确认，尚未处理 |
| `FIXING` | 正在修复 |
| `RESOLVED` | 已修复并取得回归证据 |
| `ACCEPTED_RISK` | 人已接受风险并记录边界 |
| `DEFERRED` | 已进入明确后续迭代 |
| `BLOCKED` | 缺少决策、环境或外部条件 |

修复只处理 Review 已确认问题和允许范围。修复后重新执行目标回归，再由独立 Reviewer 复审。

## 完成门禁

- 任务级通过后才进入下一任务。
- 工作包级通过后才标记 `WP-XX` 完成。
- 整体级通过后才进入 S15。
- `BLOCKER`、`HIGH` 未关闭时不得通过。
- `ACCEPTED_RISK` 和 `DEFERRED` 必须有明确的人、边界、后续迭代或触发条件。

S15 使用 [delivery-acceptance.md](../assets/templates/delivery-acceptance.md) 固定联调、验收、上线和回滚证据。
