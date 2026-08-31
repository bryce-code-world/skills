# 目标资料包模板

此目录是目标架构的空白样板，不含任何真实个人资料。**它不是可运行的 schema 2 资料空间：当前适配器不得对本目录直接执行 `init`、`status`、`validate`、`diff` 或 `apply`；其中的目录和链接只是实例占位。**运行时目标布局协议见 [target-protocol.md](../../../references/target-protocol.md)，真实实例必须由该协议生成并经过用户确认；当前 schema 2 适配器仍从上一级模板初始化兼容单文件空间。

目标实例至少需要：

- `个人全景档案.md`：聚合索引和速览。
- `主题覆盖矩阵.md`：基线必答、长期补充和未知状态。
- `原始访谈/<year>/<session>/<turn>.md`：不可变的逐轮原始表达和来源锚点。
- `权威/声明/`、`权威/事件/`、`权威/决策/`：按稳定 ID 保存权威条目。
- `权威/未知与冲突.md`、`权威/声明索引.json`：保留未知/冲突并提供 Claim/Event/Decision 的机器导航（沿用兼容文件名；索引可重建，不能取代条目）。
- `派生/`：只读生成的自传、AI 背景包和克隆底座；每种视图再按阅读任务拆分为目录和小文件。
- `README.md`、`待确认信息.md`、`资料索引.md`、`迁移映射.md`、`.hello-state`、历史/回收目录和迭代日志：分别承载入口、候选、来源、迁移、治理和恢复信息。目标 manifest 还需记录 `package_id`、`subject_id`、主体语言、所有者/`owner`、默认用途和接收方/`audience`（字段待 P1 冻结，样板不填真实身份）。

本样板当前只提供 `README.md`、聚合档案和 `主题覆盖矩阵.md` 三个设计文件；上列其余目录、索引、manifest、状态和治理文件由目标协议在实例化/迁移时生成，不能因样板缺少它们而猜测布局已可运行。目标 manifest 的 metadata-only 最小字段与 [context-contract.md](../../../references/context-contract.md) 对齐：`package_id`、`subject_id`、`owner`、`audience`、`layout`、`schema_version`/`layout_version`。

一个目标包只描述一个主体；多个人应使用独立根目录和 `subject_id`。关系信息只保留当前主体理解所必需的最小称谓或化名，不在同一包内建立未经同意的第三方人物档案。

访谈按 `主题覆盖矩阵.md` 中的最低覆盖锚点推进，并沿“定位 → 证据 → 意义/规则 → 变化复核”递进；恢复游标使用稳定的 `question_id`，不把回答正文复制到进度文件。锚点只是可调整的覆盖起点，不是人格量表或一次性填空清单。

建议的派生拆分为：`自传/时间线.md`、`自传/主题叙事.md`、`AI背景包/当前协作背景.md`、`AI背景包/协作偏好.md`、`AI克隆底座/决策规则.md`、`AI克隆底座/偏好与边界.md`、`AI克隆底座/表达样本索引.md` 和 `AI克隆底座/反事实记录.md`。这些文件只由权威条目生成，不能各自维护事实。

物理迁移必须先在独立旁路根目录生成，保留旧文件和来源映射，并经用户确认后才由 `migrate-apply`/`switch-layout` 切换适配器；用户确认的资料根目录仍是最终 canonical root，旁路根不能成为第二个长期事实源。双读验收通过后才把目标包设为该根目录的唯一活动布局，旧单文件作为可回溯历史保留。兼容 `apply` 不可直接写入目标包；目标索引由 `rebuild-index` 生成，freshness 元数据和切换/回退命令见目标协议。覆盖状态以 `主题覆盖矩阵.md` 为唯一 owner，聚合档案中的状态只能是生成投影。

`layout=target-draft` 仅是本样板的示意标识，不是运行时 marker；本样板没有根级 `.hello-state` 或 manifest，不能因目录存在而推断布局。Skill/宿主必须把本样板视为设计占位并停止，不能交给 schema 2 `apply`。目标实例应由目标协议在根级 `.hello-state` 或 manifest 中写入并校验 `layout=target-draft|target`，草稿与正式布局的 schema 分别为 `target-draft-0.1` 与 `3`。
