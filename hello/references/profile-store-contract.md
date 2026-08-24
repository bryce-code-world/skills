# 个人资料存储协议

## 一、适配器与根目录

三个适配器必须遵守同一行为契约：Windows PowerShell 5.1+ 使用 `scripts/profile_store.ps1`，POSIX 系统使用 `scripts/profile_store.sh`，后备使用 Python 3.8+ 的 `scripts/profile_store.py`。PowerShell 和 Shell 不得调用 Python 或 Node.js。

根目录只按 `--root <path>`、`HELLO_HOME` 的顺序解析；两者都没有时失败。所有文本使用 UTF-8，路径必须支持中文和空格。

## 二、命令

```text
resolve-root [--root <path>]
init --confirmed [--root <path>]
validate [--root <path>]
status [--root <path>]
configure [--capture-mode auto-stage|prompt|explicit] [--next-review-at <ISO-8601|none>] [--review-stage baseline|first-review|stable] --confirmed [--root <path>]
diff --input <candidate-profile.md> [--root <path>]
stage --input <candidate.md> [--kind <kind>] [--source <source>] --confirmed [--root <path>]
apply --input <candidate-profile.md> --summary-input <summary.md> --expected-version <n> --confirmed [--root <path>]
record-turn --session-id <yyyy-mm-dd...> --turn-id <id> --input <turn.md> --progress-input <progress.md> --expected-progress-version <n> --confirmed [--root <path>]
withdraw --id <candidate-id> --confirmed [--root <path>]
recover --confirmed [--root <path>]
self-test
```

`init`、`configure`、`stage`、`apply`、`record-turn`、`withdraw`、`recover` 都要求 `--confirmed`。它只防误调用，不能替代用户授权。

## 三、状态与兼容

新空间写入 schema 2；schema 1 仍可读取和校验，首次 `apply` 或 `record-turn` 后迁移为 schema 2。未知键必须保留。

```text
schema_version=2
profile_version=<positive integer>
progress_version=<positive integer>
capture_mode=auto-stage|prompt|explicit
created_at=<ISO 8601 UTC>
updated_at=<ISO 8601 UTC>
last_confirmed_at=<empty or ISO 8601 UTC>
next_review_at=<empty or ISO 8601 UTC>
review_stage=baseline|first-review|stable
last_interview_at=<empty or ISO 8601 UTC>
last_session_id=<empty or session id>
last_turn_id=<empty or turn id>
```

新空间的 `capture_mode` 是 `prompt`。进入 `first-review` 时必须同时给出 `next_review_at`；`apply` 不自动改变维护阶段。

## 四、结构校验

`validate` 不只检查文件存在，还必须检查：

- 状态字段、枚举、正整数版本与未完成事务标记。
- 主档案唯一标题、唯一版本元数据、唯一最近确认时间、全部规定章节，以及主档案版本与状态一致。
- 访谈进度唯一标题、全部规定章节；schema 2 下必须有唯一进度版本并与状态一致。
- 待确认候选编号不重复。
- 当前主档案版本在迭代日志中存在，版本编号不重复；适配器能够检查时还应检查顺序。
- 适配器能够读取权限时，私密目录不得向组或其他用户开放，私密文件不得有组或其他用户权限。

结构无效时禁止权威写入。`diff` 必须对顺序敏感；仅重排内容也应显示差异。

## 五、写入语义

### 候选

`stage` 只写 `待确认信息.md`，候选编号唯一；`kind` 和 `source` 的换行压缩为空格。`withdraw` 把候选块移到 `.trash/candidates/`，不直接擦除。

### 权威档案

`apply` 必须：

1. 校验预期版本、完整主档案结构和真实内容变化。
2. 要求摘要中各有一条：触发原因、信息来源、更新类型、更新位置、更新摘要、用户确认状态、执行工具。
3. 把旧主档案保存到 `历史版本/` 与 `.backups/profile/`。
4. 在同一可恢复事务中更新主档案、迭代日志和状态。
5. 写后严格校验成功才清除事务标记。

允许的摘要更新类型是：新增、状态变化、事实纠正、解释变化、假设验证、撤回隐藏。

### 访谈轮次

`record-turn` 是正式访谈的唯一写入入口。每轮写入：

```text
原始访谈/<year>/<session-id>/<turn-id>.md
访谈进度.md
.hello-state
```

原始轮次文件不可覆盖；`session-id + turn-id` 是幂等键。相同键已成功写入时返回 `idempotent: true`，其他碰撞失败。进度使用独立乐观锁 `expected-progress-version`，不消耗主档案版本。

## 六、事务与恢复

`apply` 和 `record-turn` 在写正式文件前创建 `.hello-transaction`，并在 `.backups/transactions/` 保存恢复所需副本。任何中途错误应先自动回滚；无法完成时保留事务标记，下一次写入必须停止并要求 `recover`。成功提交并通过写后校验后删除本次事务副本；`recover` 也在恢复并校验成功后清理本次副本。`recover` 只按标记恢复已知目标，恢复后再次校验。

初始化和临时文件使用最小权限：POSIX 新目录 `0700`、新文件 `0600`；Windows 依赖当前用户 ACL，不擅自扩大继承权限。`init` 不覆盖已有文件。

## 七、输出与退出码

除 `diff` 外，输出 UTF-8 JSON，至少包含 `ok`、`command`，涉及资料空间时包含 `root`。失败包含可行动的 `error`。

| 退出码 | 含义 |
|---:|---|
| 0 | 命令成功 |
| 1 | `validate` 或 `status` 发现资料空间无效 |
| 2 | 参数、确认、版本、输入、事务或文件操作失败 |

## 八、自测

每个适配器的 `self-test` 只能使用隔离临时目录和虚构数据，至少覆盖中文与空格路径、幂等初始化、确认护栏、严格校验、候选暂存与撤回、顺序敏感差异、无实质变化拒绝、版本冲突、事务回滚、轮次幂等、显式基线完成和最终校验。不得接触真实用户空间。
