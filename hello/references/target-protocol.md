# 目标布局运行协议（schema 3）

本协议把 `target-draft` 迁移草稿安全地提升为资料根目录的 `target` 布局。它只描述存储与切换，不把草稿中的声明自动变成用户确认的事实。

## 根标识

目标根必须同时有根级 `.hello-state` 和 `manifest.json`。两者至少声明：

```text
layout=target-draft|target
layout_version=1
schema_version=target-draft-0.1 (草稿) 或 3 (正式)
migration_id=<稳定迁移批次 ID>
package_id=<脱离真实身份的资料包 ID>
subject_id=<脱离真实身份的主体 ID>
```

`manifest.json` 的 `source` 保存旧根档案、进度和收件箱的版本与 SHA-256。`target-validate` 只返回元数据、计数和校验结果，不把个人正文回显到命令输出。

正式 `layout=target` 的 marker 还必须保留完整 schema 3 兼容游标：`profile_version`、`progress_version`、`capture_mode`、`created_at`、`updated_at`、`last_confirmed_at`、`next_review_at`、`review_stage`、`last_interview_at`、`last_session_id`、`last_turn_id`、`last_capture_disclosed_at`、`last_capture_disclosed_mode`；允许为空的字段也必须显式存在，保证三套适配器读取同一份状态。

## 命令与写入边界

```text
target-validate --root <target-root>
migrate-plan --root <source-root> --target <target-draft> [--migration-id <id>]
migrate-apply --root <source-root> --target <target-draft> --destination <formal-target> --expected-version <n> --expected-progress-version <n> --confirmed
rebuild-index --root <target-root> --confirmed
switch-layout --root <canonical-root> --target <formal-target> --expected-version <n> --expected-progress-version <n> --confirmed
rollback-layout --root <canonical-root> --migration-id <id> --confirmed
```

- `target-validate`、`migrate-plan` 是只读检查；不创建目录、不读取未授权目录。
- `migrate-plan` 对已经存在的草稿只做校验；目标不存在时也只返回“尚未创建”。若实现提供创建草稿的便捷入口，必须另有显式 `--confirmed`，并仍须使用独立根和来源指纹；普通计划调用不得产生目录副作用。
- `migrate-apply` 把已验证的草稿提升为 `layout=target`：可以复制到另一个独立正式根，也可以在草稿根原地提升；源根必须保持字节不变。原地提升先写快照和事务标记，验证成功后清理成功事务标记。
- `rebuild-index` 从权威条目确定性重建 `权威/声明索引.json` 和 freshness 元数据；索引不是第二事实源。
- `switch-layout` 要求两个根互不为对方的父子目录，检查源版本/哈希和目标映射，取得两个根的锁后创建不可覆盖的事务标记。旧 canonical 文件先完整快照到 `历史版本/compat-v<version>-<migration_id>/`，再原子写入目标包并将 marker 改为 `layout=target`。写后双读校验失败时自动回退并保留事务材料。
- `rollback-layout` 只从已验证的迁移快照恢复；没有匹配快照、版本不符或路径越界时拒绝操作，不删除未知文件。
- 所有会改变任一根的命令必须显式给出准确的 `--root`，并带 `--confirmed`；`HELLO_HOME` 只可用于只读探针。`--expected-version` 和 `--expected-progress-version` 保留乐观锁护栏。

## 旧资料迁移边界

正式运行的 `status`、访谈和写入只接受 `layout=target`，走目标校验、覆盖矩阵和目标事务。旧 schema 2/1 只允许作为迁移命令的只读输入；迁移完成后，旧根级文件只作为 `历史版本` 快照，不再是详细事实的 owner。当前三套适配器已提供目标布局的迁移、索引、切换和回退；目标实体的逐条确认、撤回/合并审计和完整机器 `resume_cursor` 写入口仍按后续冻结范围执行。正式切换后的 `authority_status=active-pending-review` 只表示实体仍待逐条复核，不表示物理布局尚未获确认。目标草稿不得交给旧 `apply`；正式目标只能走目标入口或明确失败。

## 失败恢复与幂等

迁移 ID、源指纹和目标版本构成幂等键。重复执行同一已完成切换返回已完成结果，不覆盖新的资料；源或目标任一版本变化必须返回冲突并要求重新生成映射。中断事务保留 marker、副本和锁信息，下一次写入先 `recover` 或 `rollback-layout`，不得猜测性清理。回退后重新运行 `target-validate`，确认旧文件、版本和状态均恢复，再允许继续访谈。

本协议的一个迁移教训：整篇搬运只能复述“我做过什么”，答不出“我擅长什么”。最小上下文不只是隐私问题，也是质量问题；生成具体任务上下文时必须先按 `context-contract.md` 选择与任务相关的能力证据、约束和目标，而不是把整份档案复制出去。
