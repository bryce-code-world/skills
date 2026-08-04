# 依赖与更新

只在检查本 Skill 更新，或当前任务实际需要底层能力时读取本文件。

## 一、运行规则

1. 以当前 Agent 暴露的 Skill 列表判断可调用性；普通源码目录存在不等于已经安装。
2. 只准备当前主绘图路径实际需要的依赖，不预装整组能力。
3. 白名单依赖缺失时从本文件声明的可信来源自动安装，不询问用户。
4. 使用系统 `skill-installer` 或等价安全安装器；候选内容校验通过后再进入目标目录。
5. 来源未知、来源变化、版本无法核验、安装失败或目标已有冲突内容时不强行覆盖，执行对应降级。
6. 新安装的普通 Skill 在当前会话仍不可发现时，本轮降级，并说明下一轮可用。
7. 自动安装只授权准备依赖，不授权自动更新、覆盖脏源码、上传、发布或其他外部操作。

## 二、安装位置

普通 Skill 安装到当前环境的用户级 Skill 目录。

同名上游 `markdown-viewer/architecture` 不能注册为第二个 `architecture`。将它安装为隔离规则源：

```text
设置 SKILL_DEPENDENCY_HOME：
  <SKILL_DEPENDENCY_HOME>/sources/markdown-viewer-architecture-rule-source

否则设置 CODEX_HOME：
  <CODEX_HOME>/skill-dependencies/sources/markdown-viewer-architecture-rule-source

否则：
  <用户主目录>/.codex/skill-dependencies/sources/markdown-viewer-architecture-rule-source
```

隔离规则源不进入 Agent 的 Skill 自动发现目录。安装器必须使用独立 `--dest` 和 `--name`，不能覆盖本 Skill。

## 三、白名单依赖

| 依赖 | 触发条件 | 可信来源与基线 | 失败降级 |
|---|---|---|---|
| `markdown-viewer/architecture` 规则源 | 静态分层、分域、侧栏、嵌套网格或复杂连接器 | `https://github.com/markdown-viewer/skills/tree/main/architecture`，`main` | 只完成架构图规格，不伪造同等静态成品 |
| `visual-cognitive-learning` | 架构演化、逐层探索或路径聚焦确实需要交互 | `https://github.com/bryce-code-world/skills/tree/main/visual-cognitive-learning`，读取其 `release.json` | 静态表达仍满足任务时降级为静态蓝图，否则停止交互产物 |
| `frontend-design` | 用户明确要求品牌化、视觉定向或去模板化 | `https://github.com/anthropics/skills/tree/main/skills/frontend-design`，`main` | 使用本 Skill 的企业蓝图默认视觉规则 |
| `lightning` | 输入零散、冲突或缺少清晰内容内核 | `https://github.com/bryce-code-world/skills/tree/main/lightning`，读取其 `release.json` | 建立最小事实清单；关键事实仍不清楚时停止对应绘制 |

白名单来源发生变化时，不沿用本次自动安装授权。

## 四、自身更新

本地版本读取 [release.json](release.json)。状态依次保存到：

```text
<SKILL_DEPENDENCY_HOME>/state.json
<CODEX_HOME>/skill-dependencies/state.json
<用户主目录>/.codex/skill-dependencies/state.json
```

每次触发时：

1. 距离 `architecture` 上次检查或尝试不足 24 小时时跳过联网。
2. 到期时读取 `https://raw.githubusercontent.com/bryce-code-world/skills/main/architecture/references/release.json`。
3. 检查失败、版本相同或发现新版本时都继续当前任务。
4. 发现新版本时只在交付时报告，等待用户确认后再更新。
5. 安装目录是链接或 Junction 时不替换链接；源码仓库存在未提交修改、冲突或无法快进时不自动更新。

无法取得可靠版本时，不声称已经是最新版。
