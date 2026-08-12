# 校验契约

## 一、判定边界

校验对象由 GitHub 仓库、Skill 相对路径和 40 位 commit 共同确定。branch 或 tag 只用于解析 commit，不作为后续检查的动态依据。

六层按顺序执行：远端、结构、发布、安装、发现、行为。后一层不能替代前一层。

| 状态 | 含义 |
|---|---|
| `PASS` | 当前层有充分证据满足契约 |
| `FAIL` | 当前层有充分证据违反契约 |
| `BLOCKED` | 权限、网络、工具或可观察性不足，无法完成必需检查 |
| `NOT_RUN` | 当前层不适用、被用户排除，或因前置失败而停止 |

| 退出码 | 含义 |
|---:|---|
| `0` | 全部选定必需层通过 |
| `1` | 至少一个必需层失败 |
| `2` | 没有失败，但存在阻塞或未执行 |
| `3` | 参数错误、内部异常或无法生成结构化结果 |

## 二、稳定规则

| 规则 ID | 层 | 判定 |
|---|---|---|
| `SRA-REMOTE-001` | 远端 | GitHub 仓库可只读访问 |
| `SRA-REMOTE-002` | 远端 | ref 已解析为 40 位 commit，后续内容来自该 commit |
| `SRA-REMOTE-003` | 远端 | 目标 Skill 路径存在且唯一 |
| `SRA-STRUCT-001` | 结构 | 目标目录存在 `SKILL.md` |
| `SRA-STRUCT-002` | 结构 | frontmatter 分隔符完整且从首行开始 |
| `SRA-STRUCT-003` | 结构 | `name` 和 `description` 各出现一次 |
| `SRA-STRUCT-004` | 结构 | frontmatter 值符合零依赖的单行字符串子集 |
| `SRA-STRUCT-005` | 结构 | frontmatter 只包含非空 `name` 和 `description` |
| `SRA-STRUCT-006` | 结构 | 名称不超过 64 字符，使用小写字母、数字和单连字符 |
| `SRA-STRUCT-007` | 结构 | `SKILL.md` 的本地资源引用存在且不越出 Skill 边界 |
| `SRA-STRUCT-008` | 结构 | 可选 `agents/openai.yaml` 可解析，路径和字段有效 |
| `SRA-RELEASE-001` | 发布 | 检查文件属于同一固定 commit |
| `SRA-RELEASE-002` | 发布 | owner、repo、Skill 名称、相对路径和安装入口一致 |
| `SRA-RELEASE-003` | 发布 | 没有未解决的发布占位符或伪造安装地址 |
| `SRA-RELEASE-004` | 发布 | 没有可机械确认的私钥或凭据；疑似项进入人工复核 |
| `SRA-RELEASE-005` | 发布 | 仓库采用的版本和索引文件与本次发布一致 |
| `SRA-INSTALL-001` | 安装 | 适配器在隔离目录成功退出并产生目标 Skill |
| `SRA-INSTALL-002` | 安装 | 安装结果存在 `SKILL.md` 和被引用资源 |
| `SRA-INSTALL-003` | 安装 | 安装内容与固定 commit 的目标目录逐文件一致 |
| `SRA-INSTALL-004` | 安装 | 未写入用户已有 Skill 目录，副作用留在登记的隔离范围 |
| `SRA-DISCOVERY-001` | 发现 | Codex 提供目标 Skill 名称和路径或等价真实发现证据 |
| `SRA-BEHAVIOR-001` | 行为 | 正向请求触发，反向请求不触发 |
| `SRA-BEHAVIOR-002` | 行为 | 边界和失败样本不扩大权限，并准确阻塞或降级 |
| `SRA-CLEANUP-001` | 清理 | 本次登记的临时目录已删除 |

AI 按适配器契约完成资源引用、可选宿主元数据、发布身份、版本一致性、npx、发现和行为取证。

原生脚本负责其输出中列明的 Frontmatter 子集、确定性发布风险和直接隔离安装规则。

## 三、脚本输出

脚本向标准输出写一个 JSON 对象，至少包含：

```json
{
  "schema_version": 1,
  "target": {"source": "...", "skill": "...", "commit": null},
  "scope": "static",
  "overall": "PASS",
  "layers": {
    "remote": {"status": "NOT_RUN", "rule_id": "SRA-REMOTE-000", "source": "skill-release-auditor/validation-contract-v1", "host": "portable", "evidence": "local source path"},
    "structure": {"status": "PASS", "rule_id": "SRA-STRUCT-005", "source": "skill-release-auditor/validation-contract-v1", "host": "portable", "evidence": "..."},
    "release": {"status": "PASS", "rule_id": "SRA-RELEASE-001", "source": "skill-release-auditor/validation-contract-v1", "host": "portable", "evidence": "..."},
    "install": {"status": "PASS", "rule_id": "SRA-INSTALL-001", "source": "skill-release-auditor/validation-contract-v1", "host": "portable", "evidence": "..."},
    "discovery": {"status": "NOT_RUN", "rule_id": "SRA-DISCOVERY-000", "source": "skill-release-auditor/validation-contract-v1", "host": "codex", "evidence": "..."},
    "behavior": {"status": "NOT_RUN", "rule_id": "SRA-BEHAVIOR-000", "source": "skill-release-auditor/validation-contract-v1", "host": "codex", "evidence": "..."}
  },
  "cleanup": {"status": "PASS", "residual_path": null}
}
```

`--scope static` 只把结构、发布和所选本地安装方式纳入脚本退出码。`--scope full` 还把发现和行为纳入，因此没有外部证据时返回 `2`。AI 必须把远端、脚本和宿主证据重新汇总，不能直接复制局部 `overall` 作为最终结论。
