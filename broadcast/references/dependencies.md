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
      "version": "2.5.1",
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
| `writing-style` | 每次公开长文的风格说明、去模板化编辑和平台稿语言终检 | `https://github.com/bryce-code-world/skills/tree/main/writing-style` | 使用“广播”通用默认风格并执行同等人工门禁，明确记录降级 |
| `frontend-design` | 图片需要精确表达对比、流程、因果、层级、连续谱、框架、数据或中文文字 | `https://github.com/anthropics/skills/tree/main/skills/frontend-design` | 交付准确视觉规格，不用艺术图替代结构图，并标记对应图文产物未完成 |
| `canvas-design` | 图片需要平台封面、概念视觉、编辑插画、视觉隐喻或鲜明艺术方向 | `https://github.com/anthropics/skills/tree/main/skills/canvas-design` | 任务允许时降级为 `frontend-design` 文字型封面或 `imagegen` 概念位图，并明确记录降级 |
| `imagegen` 或等价位图能力 | 已确定的视觉方向需要照片、写实场景、复杂插画或纹理素材 | 当前 Agent 暴露的可用视觉 Skill | 继续生成代码视觉；只有依赖位图素材的产物标记为未完成 |
| `wechatsync` | 用户已经明确要求投递，且发布包通过验收 | `https://github.com/wechatsync/Wechatsync/tree/v2/skills/wechatsync` | 交付人工发布包 |

Wechatsync Skill 安装后，仍需用户分别完成 CLI、浏览器扩展、Token、平台登录和本次投递授权。
