# 依赖与更新

只在检查本 Skill 更新，或当前任务确实需要可选 Skill 时读取本文件。

## 运行规则

1. 以当前 Agent 暴露的可用 Skill 列表为准；目录存在不等于可以调用。
2. 依赖已经可用时直接调用，不询问安装。
3. 依赖缺失时，说明用途、来源、版本或分支、安装位置和降级方案。
4. 用户确认后，优先调用系统 `$skill-installer` 从声明的地址安装，不复制下载实现。
5. 安装后执行 Skill 结构校验。当前会话仍未发现时，本轮降级并说明下一轮可用。
6. 用户拒绝或安装失败时执行表中的降级方案。

安装确认只授权安装该 Skill，不授权它移动、覆盖、删除或同步用户文件。

系统 `$skill-installer` 不可用时，只报告准确安装地址和降级方案，不临时发明安装命令。

## 自身更新

本地版本读取 [release.json](release.json)。

状态保存到：

```text
SKILL_DEPENDENCY_HOME 已设置：
  <SKILL_DEPENDENCY_HOME>/state.json

否则 CODEX_HOME 已设置：
  <CODEX_HOME>/skill-dependencies/state.json

否则：
  <用户主目录>/.codex/skill-dependencies/state.json
```

状态只记录 Skill、来源、版本、最近检查时间和校验结果，不保存凭据或文档内容。

使用统一结构，并在写入时保留其他 Skill 的记录：

```json
{
  "schema_version": 1,
  "skills": {
    "lightning": {
      "source": "https://github.com/bryce-code-world/skills",
      "version": "1.0.0",
      "last_check_attempt": "2026-07-31T00:00:00Z",
      "last_check_result": "current"
    }
  }
}
```

每次触发时执行非阻塞检查：

1. 距离 `lightning` 上次检查或尝试不足 24 小时时跳过联网。
2. 到期时读取
   `https://raw.githubusercontent.com/bryce-code-world/skills/main/lightning/references/release.json`。
3. 记录本次检查时间和结果。
4. 远端版本等于本地版本时继续当前任务。
5. 远端版本高于本地版本时，继续使用当前版本完成本轮任务，并在交付时说明差异、等待更新确认。
6. 远端版本低于本地版本时不降级，报告版本异常。
7. 用户确认更新后，在临时目录准备候选版本，校验通过再备份和切换；失败时保留或恢复旧版本。

安装目录是链接或 Junction 时，不替换链接。先检查源码仓库；存在未提交修改、冲突或无法快进时停止更新。

无法取得可靠版本时，不声称已经是最新版本。

已安装的可选依赖只在当前任务实际需要时检查更新，同一依赖 24 小时内最多检查一次。来源提供版本清单时比较版本；否则比较声明分支的远端提交。发现更新后仍需用户确认，不自动覆盖。

## 可选依赖

| Skill | 触发条件 | 可信来源 | 降级 |
|---|---|---|---|
| `diagram` | 需要独立 SVG、PNG 或可编辑 Excalidraw | `https://github.com/garrytan/gstack/tree/main/diagram` | Mermaid、表格或紧凑 ASCII |
| `uml`、`architecture`、`bpmn`、`vega`、`infographic`、`mindmap`、`canvas` | 需要对应专项图示语法 | `https://github.com/markdown-viewer/skills/tree/main/<skill>` | Mermaid、表格或紧凑 ASCII |
| `neat-freak` | 用户明确要求治理文档库或知识库 | `https://github.com/KKKKhazix/khazix-skills/tree/main/neat-freak` | 只完成当前文档，不执行库级治理 |
| 项目或领域 Skill | 用户、项目规则或目标格式明确指定 | 使用对应规则给出的来源 | 来源不明确时请求用户确认，不自动搜索安装 |

只检查当前任务实际需要的一项，不预装整组图示 Skill。
