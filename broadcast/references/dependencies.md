# 依赖与更新

只在检查本 Skill 更新，或当前任务确实需要下游能力时读取本文件。

## 运行规则

1. 以当前 Agent 暴露的可用 Skill 列表为准；目录存在不等于可以调用。
2. 依赖已经可用时直接调用，不询问安装。
3. 依赖缺失时，说明用途、来源、版本或分支、安装位置和降级方案。
4. 用户确认后，优先调用系统 `$skill-installer` 从声明的地址安装，不复制下载实现。
5. 安装后执行 Skill 结构校验。当前会话仍未发现时，本轮降级并说明下一轮可用。
6. 用户拒绝或安装失败时执行表中的降级方案。

安装确认、账号连接、凭据配置、素材上传、保存草稿和公开发布是相互独立的授权。

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

状态只记录 Skill、来源、版本、最近检查时间和校验结果，不保存凭据、账号信息或文章内容。

使用统一结构，并在写入时保留其他 Skill 的记录：

```json
{
  "schema_version": 1,
  "skills": {
    "broadcast": {
      "source": "https://github.com/bryce-code-world/skills",
      "version": "1.0.0",
      "last_check_attempt": "2026-07-31T00:00:00Z",
      "last_check_result": "current"
    }
  }
}
```

每次触发时执行非阻塞检查：

1. 距离 `broadcast` 上次检查或尝试不足 24 小时时跳过联网。
2. 到期时读取
   `https://raw.githubusercontent.com/bryce-code-world/skills/main/broadcast/references/release.json`。
3. 记录本次检查时间和结果。
4. 远端版本等于本地版本时继续当前任务。
5. 远端版本高于本地版本时，继续使用当前版本完成本轮任务，并在交付时说明差异、等待更新确认。
6. 远端版本低于本地版本时不降级，报告版本异常。
7. 用户确认更新后，在临时目录准备候选版本，校验通过再备份和切换；失败时保留或恢复旧版本。

安装目录是链接或 Junction 时，不替换链接。先检查源码仓库；存在未提交修改、冲突或无法快进时停止更新。

无法取得可靠版本时，不声称已经是最新版本。

已安装的条件依赖只在当前任务实际需要时检查更新，同一依赖 24 小时内最多检查一次。`lightning` 和 `writing-style` 读取各自的 `release.json`；其他来源比较声明分支的远端提交。发现更新后仍需用户确认，不自动覆盖。

## 条件依赖

| Skill | 触发条件 | 可信来源 | 降级 |
|---|---|---|---|
| `lightning` | 输入仍然零散、冲突或缺少清晰内容内核 | `https://github.com/bryce-code-world/skills/tree/main/lightning` | 人工建立来源账本；事实仍不清楚时停止转译 |
| `writing-style` | 需要选择、提炼、应用或验收个人与参照风格 | `https://github.com/bryce-code-world/skills/tree/main/writing-style` | 使用“广播”通用默认风格 |
| `baoyu-article-illustrator` | 用户要求文章插图 | `https://github.com/JimLiu/baoyu-skills/tree/main/skills/baoyu-article-illustrator` | 交付插图规格 |
| `baoyu-xhs-images` | 用户要求渲染小红书图卡 | `https://github.com/JimLiu/baoyu-skills/tree/main/skills/baoyu-xhs-images` | 交付逐卡内容与视觉规格 |
| `baoyu-format-markdown` | 用户要求额外 Markdown 排版 | `https://github.com/JimLiu/baoyu-skills/tree/main/skills/baoyu-format-markdown` | 交付未额外美化的完整成稿 |
| `wechatsync` | 用户已经明确要求投递，且发布包通过验收 | `https://github.com/wechatsync/Wechatsync/tree/v2/skills/wechatsync` | 交付人工发布包 |

Wechatsync Skill 安装后，仍需用户分别完成 CLI、浏览器扩展、Token、平台登录和本次投递授权。
