# 个人资料存储协议

## 一、适配器与根目录

三个适配器必须遵守同一行为契约：Windows PowerShell 5.1+ 使用 `scripts/profile_store.ps1`，POSIX 系统使用 `scripts/profile_store.sh`，后备使用 Python 3.8+ 的 `scripts/profile_store.py`。PowerShell 和 Shell 不得调用 Python 或 Node.js。

根目录按 `--root <path>`、`HELLO_HOME` 的顺序解析；两者都没有时失败。`--root` 一旦显式出现，空字符串值即为参数错误并应失败关闭，不得回退到 `HELLO_HOME`。为避免探针或包装器漏掉参数后误写资料，所有会改变资料空间的命令（`init`、`configure`、`record-disclosure`、`stage`、`apply`、`record-turn`、`withdraw`、`recover`）必须显式传入 `--root`；只有只读的 `resolve-root`、`validate`、`status`、`diff` 可以在完全省略 `--root` 时使用 `HELLO_HOME`。测试和审查一律使用明确的隔离临时根，不依赖环境变量。所有文本使用 UTF-8，路径必须支持中文和空格。当前适配器维护兼容 schema 2 的根目录文件；目标目录的声明、事件、决策拆分见 [profile-architecture.md](profile-architecture.md)，在协议升级前不得假装已经支持物理拆分。

状态文件和事务标记的键名按大小写不敏感规则判重；因此保留未知键时，只有不与保留键或其他未知键形成大小写变体的键才会被保留。这样可避免 PowerShell、Python 和 POSIX 适配器对同一份状态产生不同解释。

## 二、命令

```text
resolve-root [--root <path>]
init --confirmed --root <path>
validate [--root <path>]
status [--root <path>]
configure [--capture-mode auto-stage|prompt|explicit] [--next-review-at <ISO-8601|none>] [--review-stage baseline|first-review|stable] --confirmed --root <path>
record-disclosure [--capture-mode auto-stage|prompt|explicit] --confirmed --root <path>
diff --input <candidate-profile.md> [--root <path>]
stage --input <candidate.md> [--kind <kind>] [--source <source>] --confirmed --root <path>
apply --input <candidate-profile.md> --summary-input <summary.md> --expected-version <n> --confirmed --root <path> [--simulate-failure]
record-turn --session-id <yyyy-mm-dd...> --turn-id <id> --input <turn.md> --progress-input <progress.md> --expected-progress-version <n> --confirmed --root <path> [--simulate-failure]
withdraw --id <candidate-id> --confirmed --root <path>
recover --confirmed --root <path>
self-test
```

`init`、`configure`、`record-disclosure`、`stage`、`apply`、`record-turn`、`withdraw`、`recover` 都要求 `--confirmed`。它只防误调用，不能替代用户授权。适配器无法知道宿主是否真的向用户展示了策略或披露是否已过期；但在非 `explicit` 模式，`stage` 会拒绝缺少合法 ISO 8601 UTC `last_capture_disclosed_at` 或 `last_capture_disclosed_mode` 不匹配当前 `capture_mode` 的状态，`explicit` 模式不要求披露回执。隐式发现的披露闸门仍由 `hello`/宿主流程负责，未完成披露时不得调用 `stage`，不能把命令护栏误当成知情证明。`--simulate-failure` 仅供三套适配器的隔离故障注入和 `self-test` 使用：在 `apply` 或 `record-turn` 写完状态后故意失败并验证回滚，生产流程不得传入。

命令行采用严格长选项语法：选项名必须完整匹配（不接受缩写），值必须作为紧随其后的独立参数，值选项和 `--confirmed` 不得重复；`--name=value`、裸 `--` 和未知选项均失败。`--expected-version` 与 `--expected-progress-version` 只接受规范正十进制整数 `[1-9][0-9]*`，不接受 `0`、前导零或带符号形式。Windows PowerShell 可能在脚本收到参数前拦截裸 `--` 并输出宿主错误；调用方应避免传入该终止符，若需验证失败 JSON，应通过能把参数原样传入脚本的包装器执行。

所有会写资料的公开命令（包括 `configure`、`record-disclosure`、`stage`、`apply`、`record-turn`、`withdraw` 和 `recover`，以及会创建空间的 `init`）必须先获取该资料根目录专属的进程间锁。锁采用不可覆盖的创建语义；检测到同一根目录已有锁时返回可行动的 busy 错误，调用方可在锁释放后重试，不能抢占或删除未知锁。

## 三、状态与兼容

新空间写入 schema 2；schema 1 仍可读取和校验，首次 `apply` 或 `record-turn` 后迁移为 schema 2。未知键必须保留。

```text
schema_version=2
profile_version=<canonical positive integer [1-9][0-9]*>
progress_version=<canonical positive integer [1-9][0-9]*>
capture_mode=auto-stage|prompt|explicit
created_at=<ISO 8601 UTC>
updated_at=<ISO 8601 UTC>
last_confirmed_at=<empty or ISO 8601 UTC>
next_review_at=<empty or ISO 8601 UTC>
review_stage=baseline|first-review|stable
last_interview_at=<empty or ISO 8601 UTC>
last_session_id=<empty or session id>
last_turn_id=<empty or turn id>
last_capture_disclosed_at=<empty or ISO 8601 UTC; latest recorded disclosure after status was shown>
last_capture_disclosed_mode=<empty or auto-stage|prompt|explicit; mode recorded with the latest disclosure>
```

新空间的 `capture_mode` 是 `prompt`。进入 `first-review` 时必须同时给出 `next_review_at`；`apply` 不自动改变维护阶段。

## 四、结构校验

`validate` 不只检查文件存在，还必须检查：

- 状态字段、枚举、正整数版本与未完成事务标记。
- 主档案唯一标题、唯一版本元数据、唯一最近确认时间、全部规定章节，以及主档案版本与状态一致。
- 访谈进度唯一标题、全部规定章节；schema 2 下必须有唯一进度版本并与状态一致。
- 档案和进度中的版本元数据也必须使用规范正十进制 `[1-9][0-9]*`，避免不同适配器把前导零解释成不同版本。
- 待确认候选编号不重复。
- 当前主档案版本在迭代日志中存在，版本编号不重复且按升序排列。
- 适配器能够读取权限时，私密目录不得向组或其他用户开放，私密文件不得有组或其他用户权限。

结构无效时禁止权威写入。`diff` 必须对顺序敏感；仅重排内容也应显示差异。

## 五、写入语义

### 候选

兼容 schema 2 的 `stage` 只写 `待确认信息.md`，候选编号唯一；`kind` 和 `source` 的换行压缩为空格。目标 P1 协议还要为每条候选保存主题、时间、敏感级别、用途范围和完整处置状态；在三套适配器升级前，不能把兼容字段当成这些目标字段已经落盘。`withdraw` 把候选块移到 `.trash/candidates/`，不直接擦除；移动后的块保留候选 ID 和原始处置上下文，便于人工追溯。当前兼容 schema 2 没有独立的机器化拒绝/合并 tombstone 或权威条目删除命令，不能声称已实现完整候选审计；目标 P1 应增加带处置时间、原因、替代/合并 ID 的候选状态索引。候选不得因暂存而成为权威事实。

### 权威档案

`apply` 必须：

1. 校验预期版本、完整主档案结构和真实内容变化。
2. 要求摘要中各有一条：触发原因、信息来源、更新类型、更新位置、更新摘要、用户确认状态、执行工具。
3. 把旧主档案保存到 `历史版本/` 与 `.backups/profile/`。
4. 在同一可恢复事务中更新主档案、迭代日志和状态。
5. 写后严格校验成功才清除事务标记。

当前 `apply` 只更新兼容 schema 2 的根级综合档案；权威 Claim/Event/Decision 的撤回、隐藏、删除和派生失效仍是目标 P1/P2/P3 协议，不能把单文件差异应用描述成已完成的目录化撤回。

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

`apply` 和 `record-turn` 在写正式文件前创建 `.hello-transaction`，并在 `.backups/transactions/` 保存恢复所需副本。任何中途错误应先自动回滚；无法完成时保留事务标记，下一次写入必须停止并要求 `recover`。成功提交并通过写后校验后删除本次事务副本；`recover` 必须先按标记恢复已知目标、在仍保留标记和副本时完成写后校验，只有校验成功才清理本次副本和标记；校验失败时必须保留它们以便重试。

隔离恢复测试建议：在系统临时目录构造虚构资料空间和中断标记，分别覆盖合法标记、缺失副本、路径越界、重复键及无 `=` 坏行。坏标记或缺副本时，`recover --confirmed --root <隔离根目录>` 应返回退出码 `2`，且标记、副本和正式文件都保留，不能因校验失败而静默清理；合法标记恢复并通过 `validate --root <隔离根目录>` 后才删除本次标记/副本。每套适配器都应独立运行这些夹具，并在测试结束确认临时目录已删除。

事务标记 `.hello-transaction` 必须以不可覆盖的原子 `CreateNew`/独占创建语义建立；发现已有标记时不得截断、替换或把新事务叠加其上。PowerShell 使用等价的 `CreateNew`，Python 使用独占创建，POSIX 使用等价的 `O_EXCL`/noclobber 语义；三套适配器都应在竞争时返回 busy/中断事务错误并保留原标记。

### 会话终止

一个 `session_id` 在以下任一条件命中时终止：跨自然日、跨设备、连续超过 50 轮，或用户明确表示结束本次访谈。自然日当前按适配器使用的 UTC 日期判定，用户本地时区边界尚待验证；跨设备和用户显式结束依赖宿主传入或记录，现有适配器没有统一输入/终止状态，尚未在适配器层验证。适配器能确定的条件由 `record-turn` 检查。命中后 `record-turn` 仍可保存当前轮次，但返回 `new_session_required: true`、原因列表和“请开启新会话”的提示；适配器本身只负责提示，不记录终止状态或阻止下一次调用，宿主必须阻止复用已终止的会话编号并传入新的 `session_id`。

初始化和临时文件使用最小权限：POSIX 新目录 `0700`、新文件 `0600`；Windows 依赖当前用户 ACL，不擅自扩大继承权限。`init` 不覆盖已有文件。

## 七、输出与退出码

JSON 中所有版本字段（包括 `profile_version`、`progress_version`、`old_version` 及其嵌套/结果字段）统一序列化为规范十进制字符串，而不是 JSON number；调用方应按字符串规则比较，不能依赖语言的数值精度或自动类型转换。

除 `diff` 外，输出 UTF-8 JSON，至少包含 `ok`、`command`，涉及资料空间时包含 `root`。失败包含可行动的 `error`。

命令行解析失败（未知命令、未知选项、缺少参数或参数类型错误）也属于失败：三个适配器都应在标准输出给出一条 UTF-8 JSON，`ok=false`、`command` 为已识别的首个命令（尚未识别命令时为空字符串）并包含 `error`，退出码为 `2`；不得把解析器 usage/traceback 当作唯一结果。错误文字和选项枚举可保留适配器原生措辞，不要求逐字一致。交互式 `--help` 展示和 `diff` 的纯文本输出是有意例外。

`status` 成功输出除 `capture_mode` 外，还必须包含：

- `capture_strategy`：当前采集策略的人类可读名称（仅显式 / 提示确认 / 自动暂存）；
- `last_capture_disclosed_at`（兼容字段名）：最近一次在展示 `status` 后由 `record-disclosure --confirmed --root <已授权目录>` 留下的知情审计时间。只有 `record-disclosure` 更新此字段；`configure` 只改变采集策略、维护阶段或回访日期，不得把策略变更当成实际披露。空值表示尚未有受控记录，过期时间不能替代本次披露。
- `last_capture_disclosed_mode`：上述最近一次披露所对应的采集模式；适配器用它与当前 `capture_mode` 做匹配校验。策略变化后旧模式回执不再满足非 `explicit` 的 `stage` 门禁。

Skill 在读取 `status` 后必须实际向用户披露上述字段；披露完成且用户确认理解后调用 `record-disclosure --confirmed --root <已授权目录>`（可带 `--capture-mode`，适配器会校验它仍是当前策略）。用户不记得或时间过期时暂停暂存并重新确认策略，不能把旧时间戳当成本次知情证明。

基线收口字段也必须可核查：`baseline_required_remaining`（基线必答项数组）、`baseline_closure_blocked`（仍有必答项时为 `true`）、`baseline_split_unknown`（旧 schema 1 或缺少固定分组时为 `true`）和 `long_term_backlog`（可长期补充项数组）。兼容 schema 2 仅根据《访谈进度》两个固定子标题下的清单计算，并不读取目标包覆盖矩阵的冲突、`declined` 或 `not_applicable` 状态；目标 P1 `status` 才合并这些状态。缺少任一子标题时应返回 `baseline_split_unknown=true` 和 `legacy-unclassified` 占位项并保持阻塞，不能把空结果解释为已收口。

| 退出码 | 含义 |
|---:|---|
| 0 | 命令成功 |
| 1 | `validate` 或 `status` 发现资料空间无效 |
| 2 | 参数、确认、版本、输入、事务或文件操作失败 |

## 八、自测

每个适配器的 `self-test` 只能使用隔离临时目录和虚构数据，至少覆盖中文与空格路径、幂等初始化、确认护栏、UTF-8+LF 输出、严格校验、命令行未知命令/选项的 JSON 失败契约、候选暂存与撤回、知情审计及策略不匹配拒绝、顺序敏感差异、无实质变化拒绝、版本冲突、事务回滚、坏事务标记保留、轮次幂等、显式基线完成和最终校验。不得接触真实用户空间。
