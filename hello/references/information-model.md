# 个人信息与资料空间

本文件说明 `hello` 当前兼容目录和目标资料包的读取边界。需要理解完整分层、模型来源、实体字段和迁移阶段时，先读 [profile-architecture.md](profile-architecture.md)。

## 一、资料包边界

个人资料只保存在用户明确指定的根目录，不保存在 Skill 目录。目标结构按来源、收件箱、权威、派生和治理五层组织：

```text
<root>/
├── README.md
├── 个人全景档案.md                 # 聚合索引、速览和导航
├── 主题覆盖矩阵.md
├── 访谈进度.md
├── 待确认信息.md                  # 未确认候选
├── 资料索引.md
├── 原始访谈/<year>/<session>/<turn>.md
├── 权威/声明/<topic_id>/*.md
├── 权威/事件/E-*.md
├── 权威/决策/D-*.md
├── 权威/未知与冲突.md
├── 权威/声明索引.json
├── 迁移映射.md                    # 仅迁移阶段生成的来源映射
├── 派生/自传/{README.md,时间线.md,主题叙事.md}
├── 派生/AI背景包/{README.md,当前协作背景.md,协作偏好.md}
├── 派生/AI克隆底座/{README.md,决策规则.md,偏好与边界.md,表达样本索引.md,反事实记录.md}
├── 历史版本/
├── .backups/
├── .trash/
├── 迭代日志.md
└── .hello-state
```

当前兼容阶段仍允许根目录只有一份旧版《个人全景档案》正文；它是旧 schema 的权威综合文件。目标阶段，《个人全景档案.md》只做资料包唯一的聚合入口和导航门面，详细事实的唯一 owner 在 `权威/` 中的稳定 ID 条目。物理迁移必须旁路、保留来源并经用户确认，不能因目录存在就自动执行；目标 manifest 还应在 P1 冻结 `package_id`、`subject_id`、主体语言/所有者和默认用途等包级身份元数据，样板不填真实身份。

一个资料根目录对应一个主体；多人资料必须使用彼此独立的根目录和 `subject_id`，不能把不同主体的权威条目、候选或原始访谈混合。关系主题只保留理解当前主体所需的最小称谓或化名，不自动扩展为第三方人物档案。`package_id` 标识资料包，`subject_id` 标识主体，具体格式和跨包引用规则待目标 P1 冻结。

## 二、读取顺序和权限

**读取总闸门（强制）**：在读取任何个人资料前先判断当前任务的产出物去向。若产出物会提交远端、写入非私密目录或对外发布，必须先读取并执行 [context-contract.md](context-contract.md)，列出最小读取范围、抽象化方式和敏感排除；协议完成前不得读取整篇档案或整套 `权威/`。

默认读取（本地任务）：

1. `README.md`，确认用途、隐私和阅读规则。
2. `个人全景档案.md` 的速览层和主题导航。
3. 目标目录按任务读取相关 `权威/声明`、`权威/事件` 或 `权威/决策`；兼容目录才在确有需要时读取旧正文备查层。

继续访谈时再读取 `访谈进度.md` 和未处理候选的数量；执行候选审核时才读取 `待确认信息.md` 的相关条目；核验来源或理解变化时才定位相关原始轮次、资料索引、历史版本和派生视图。

任务产出物会离开本地时，必须在上述任何资料读取前先读并执行 [context-contract.md](context-contract.md)，不得默认读取整篇权威档案或整套权威目录；协议完成后再运行 `status`、记录知情披露并按清单读取。

## 三、信息实体

### 1. 来源、信号和候选

- `Source`：原始轮次、用户授权材料或明确的用户修正的定位，不等于事实本身。
- `Signal`：宿主从当前消息发现的与本人有关的线索；没有宿主 Hook 时只能在 Skill 被调用时产生。
- `Candidate`：已经分类、等待用户处置的最小信息单元。状态至少包括 `pending_confirmation`、`needs_clarification`、`accepted`、`corrected`、`merged`、`deferred`、`rejected`、`withdrawn` 和 `expired`。

自动发现只产生 `Signal`；按实际 `capture_mode` 暂存才产生 `Candidate`；用户确认后才进入权威层。

### 2. 权威声明、事件和决策

每个权威条目只有一个 owner，并有稳定 ID、主题、内容类型、状态、时间、来源、敏感级别、允许用途和替代/冲突关系。

声明 `Claim` 的内容类型至少区分用户事实陈述、外部证据事实、原始记忆、本人理解、AI 假设、未知和冲突。重要字段：

```text
claim_id, topic_id, kind, statement, status,
occurred_at / valid_from / valid_to, stated_at, confirmed_at,
evidence_level, source_refs, evidence_refs, relation_refs,
sensitivity, allowed_uses,
supersedes, conflict_set, review_at
```

`Claim` 的主字段是单数 `topic_id`，表示唯一主主题；索引可将它及经确认的交叉主题映射派生为复数 `topic_ids` 导航字段。索引字段不改变声明的唯一 owner，也不反写声明正文。

主主题由结论主要回答的问题和维护责任决定，只能有一个；交叉主题只作为经确认的检索入口，不复制事实或产生第二 owner。主题边界相近时（如 `environment`/`resources`、`work`/`capability`、`health`/`emotion`），按用户叙述重点选择主主题，并在 P1 冻结交叉映射和冲突处理准则。

`Claim` 是权威声明容器，不等于所有内容都进入默认背景。只有 `status=confirmed` 且 `kind` 不是 AI 假设、未知或冲突的声明，才可投影到默认速览和协作上下文；其他类型必须显式标记并按用途排除或单独呈现。AI 假设应记录生成者、生成时间、依据摘要和复核状态，默认不向派生视图投影。

`Claim`、`Event`、`Decision` 的权威状态采用待 P1 冻结的最小拟议枚举：`draft`、`confirmed`、`stale`、`superseded`、`withdrawn`、`conflicted`、`unknown`。只有当前确认且未被其他状态排除的条目进入默认背景；每次状态转换保留操作者、时间、原因和来源，不能靠删除文件表示。字段名和转换细节冻结前不视为当前适配器已实现。

事件 `Event` 用于人生时间线和影响链：

```text
event_id, life_chapter, topic_ids, start_at / end_at, context,
choice, outcome, then_view, now_view, impact,
source_refs, claim_refs, status
```

决策 `Decision` 用于保留判断过程，而不是只留结果：

```text
decision_id, topic_ids, time, question, options, constraints,
tradeoffs, choice, result, review, source_refs, claim_refs, status
```

“未知、拒答、不适用”是可观察状态，不用空白伪装成已覆盖。

## 四、主题与覆盖

主题地图可以包含：当前处境、人生章节、成长环境、教育学习、职业项目、能力证据、健康精力、经济安全、关系责任、习惯行动、情绪压力、认知世界观、价值意义、高低点、资源环境、未来设想和 AI 协作偏好。

每个主题在 `主题覆盖矩阵.md` 中使用以下状态之一：

```text
not_started, signals_only, partial, confirmed_minimum, deepened,
stale, conflicted, declined, not_applicable
```

另行标注“基线必答”或“可长期补充”。只有基线必答项未达到 `confirmed_minimum` 且未被用户标为 `declined` / `not_applicable` 时，才阻塞基线收口。

当前 17 个主题 ID 是可扩展的起始注册表，不是声称穷尽一个人的唯一标准；新增或改义必须登记映射、版本和迁移关系。兼容 schema 2 的“情绪与压力”“高低点与转折”“资源与环境”等宽主题，在目标迁移时才展开为 `emotion`、`turning-points`、`resources` 及相关稳定 ID；宽主题已覆盖不能直接冒充目标主题的 `confirmed_minimum`。

访谈按每主题的“定位、证据、意义/规则、变化复核”四层递进，并用稳定 `question_id` 指向下一步；每层是否完成以 [profile-architecture.md](profile-architecture.md) 的最低覆盖锚点和来源为准，不以回答长度或清单勾选代替确认。

## 五、时间、来源和派生关系

重要信息尽量分开记录：事件发生时间、状态有效期、讲述时间、确认时间、写入时间和派生生成时间。旧状态被替代时保留 `supersedes` 或冲突关系，不静默抹除历史。

`source_refs` 优先指向稳定的 `source_id`；原始文件路径、会话和轮次只作为可变定位提示。迁移或换存储位置时先更新来源映射，不能让路径变化破坏溯源。

聚合索引是由权威层生成的导航门面；自传、AI 背景包和克隆底座是按用途生成的派生视图。目标包聚合索引和实体索引（覆盖 Claim/Event/Decision）拟定注明 `index_source_version`、`index_source_progress_version`、`index_source_matrix_version`、`generated_at` 和生成输入哈希；索引项使用一个或多个 `topic_ids`。这些字段的名称、格式、哈希算法和 freshness 规则待目标 P1 冻结，当前 schema 2 不生成也不校验。覆盖状态的唯一 owner 是 `主题覆盖矩阵.md`，聚合档案中的状态只能是生成投影。派生视图必须注明 `source_authority_version`（兼容 schema 2 可记录对应的 `source_profile_version`）、用途、允许使用范围和失效条件。索引或视图过期时只读降级并报告，不把空索引当作空资料。派生视图可以按阅读任务拆成目录和文件，但不能各自维护事实；它们不能反写权威层，撤回后必须失效并重建。

## 六、候选、进度和日志

目标 P1 候选记录至少包含 `candidate_id`、来源信号、主题、类型、最小摘要、事件/有效时间、敏感级别、用途范围和处置状态；兼容 schema 2 的 `stage` 目前只保证候选编号、暂存时间、类型、来源和待确认状态，不能声称目标字段已经结构化落盘。候选审核结果不能只靠移除 Markdown 块表示。

`访谈进度.md` 只保存恢复访谈所需的版本、覆盖状态、基线必答、长期补充、暂不收集和游标：目标包使用机器 `resume_cursor`，兼容 schema 2 使用 `next_question`/恢复游标文本；不复制完整问答或权威事实正文。

隐式发现已经分类为 `Candidate`/需要持久化，或继续访谈时，在 `status` 后必须向用户展示当前采集策略；用户确认理解后由 `record-disclosure --capture-mode <当前模式> --confirmed --root <已授权目录>` 写入 `last_capture_disclosed_at` 和对应披露模式。纯 `Signal`（一次性情绪、临时参数等）只在会话内处理，不运行 `status` 或 `record-disclosure`。披露记录只证明受控流程记录了展示，不代替用户对候选内容的逐条确认，也不是跨会话授权本身。非 `explicit` 模式的 `stage` 还要求披露时间存在且模式与当前策略匹配；“过期”由宿主按会话、设备、策略版本、用户记忆和约定时限等策略判定；当前适配器不自行设定 TTL 或验证新鲜度。并发披露或策略变更必须沿用资料版本/事务护栏，冲突时停写并重新读取，不能让较旧回执覆盖较新策略。

`迭代日志.md` 记录版本、时间、触发原因、来源、更新类型、位置、摘要、确认状态和工具标识，不重复堆放敏感原文。

## 七、兼容迁移

从 v21 或其他单文件档案迁移时：先只读盘点和隔离快照，再按章节和段落建立主题/声明/事件/决策映射；保留原来源标注，无法判断的内容标为未知或待确认。用户确认速览、映射和差异后才写入目标包；双读校验完成前保留旧文件和回退路径。迁移不修改、移动或删除用户未授权的资料。
