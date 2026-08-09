# 依赖与更新

只在检查本 Skill 更新，或当前任务确实需要下游能力时读取本文件。

## Skill 依赖运行规则

1. 以当前 Agent 暴露的可用 Skill 列表为准；目录存在不等于可以调用。
2. 依赖已经可用时直接调用，不询问安装。
3. 依赖缺失时，说明用途、来源、版本或分支、安装位置和降级方案。
4. 用户确认后，优先调用系统 `$skill-installer` 从声明的地址安装，不复制下载实现。
5. 安装后执行 Skill 结构校验。当前会话仍未发现时，本轮降级并说明下一轮可用。
6. 用户拒绝或安装失败时执行表中的降级方案。

上述 Skill 依赖的安装确认、账号连接、素材上传、保存草稿和公开发布是相互独立的授权。发布 MCP 是唯一例外：用户明确要求投递时，该请求同时授权本次官方 Playwright MCP 的安装、四个平台实例注册，以及在用户指定或项目已经声明的登录缓存根目录中创建 Profile；首次登录和公开发布仍不随之授权。

系统 `$skill-installer` 不可用时，只报告准确安装地址和降级方案，不临时发明安装命令。

## Playwright MCP 自动安装

发布 MCP 不使用 `$skill-installer`。用户明确要求投递、发布包已经通过验收且目标平台的 `publisher_*` 实例未连接时，按 [publishing-playwright.md](publishing-playwright.md) 自动安装并注册官方 `@playwright/mcp`，不再请求第二次安装确认。

1. 优先调用宿主原生 MCP 安装、插件或连接能力。
2. 宿主没有原生能力时，按当前客户端真实配置格式注册 `publisher_wechat`、`publisher_zhihu`、`publisher_csdn` 和 `publisher_juejin`。
3. 安装前核对 Microsoft 官方来源、Apache-2.0 许可、固定包版本、Node.js 运行时、客户端配置位置、Profile 根目录来源和 Git 忽略状态。
4. 只新增缺失节点，不覆盖其他 Server 配置；不写入 Cookie、Token、验证码或平台凭据。
5. 安装后重新发现工具并逐实例检查 schema；需要重载时标记“已安装待重载”，本轮不继续投递。
6. 安装、注册或启动失败时交付人工发布包，不自动切换到扩展、Token、CLI 或 WebSocket 桥接。

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
      "version": "3.8.0",
      "last_check_attempt": "2026-08-09T00:00:00Z",
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

| 能力或入口 | 触发条件 | 可信来源 | 降级 |
|---|---|---|---|
| `lightning` | 输入仍然零散、冲突或缺少清晰内容内核 | `https://github.com/bryce-code-world/skills/tree/main/lightning` | 人工建立来源账本；事实仍不清楚时停止转译 |
| `writing-style` | 每次公开长文的写作前风格说明、完整稿结构去模板化和平台终检 | `https://github.com/bryce-code-world/skills/tree/main/writing-style` | 使用“广播”通用默认风格并执行同等人工门禁，明确记录降级 |
| `frontend-design` | 图片需要精确表达对比、流程、因果、层级、连续谱、框架、数据或中文文字 | `https://github.com/anthropics/skills/tree/main/skills/frontend-design` | 交付准确视觉规格，不用艺术图替代结构图，并标记对应图文产物未完成 |
| `canvas-design` | 图片需要平台封面、概念视觉、编辑插画、视觉隐喻或鲜明艺术方向 | `https://github.com/anthropics/skills/tree/main/skills/canvas-design` | 任务允许时降级为 `frontend-design` 文字型封面或 `imagegen` 概念位图，并明确记录降级 |
| `imagegen` 或等价位图能力 | 已确定的视觉方向需要照片、写实场景、复杂插画或纹理素材 | 当前 Agent 暴露的可用视觉 Skill | 继续生成代码视觉；只有依赖位图素材的产物标记为未完成 |
| [publishing-playwright.md](publishing-playwright.md) 定义的官方 Playwright MCP | 用户已经明确要求投递，且发布包通过验收 | `@playwright/mcp@0.0.79`；按平台注册四个独立持久化实例 | 交付人工发布包 |

Playwright MCP 可调用，不代表专属 Profile 已登录、账号已核对或本次投递已通过预检。安装、连接、首次登录、草稿保存和公开发布仍需分别满足授权边界。
