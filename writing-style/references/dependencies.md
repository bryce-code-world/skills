# 依赖与更新

只在检查本 Skill 更新，或调研新参照风格确实需要额外能力时读取本文件。

## 运行规则

1. 以当前 Agent 暴露的可用 Skill 列表为准；目录存在不等于可以调用。
2. 依赖已经可用时直接调用，不询问安装。
3. 缺失能力必须有明确、可信的来源，才能向用户请求安装确认。
4. 用户确认后，优先调用系统 `$skill-installer`，不复制下载实现。
5. 安装后执行 Skill 结构校验。当前会话仍未发现时，本轮使用已有风格资料继续。
6. 用户拒绝、来源不明确或安装失败时，不影响已有风格库和用户档案。

`broadcast` 是调用方，不是本 Skill 需要反向安装的依赖。

安装检索或文档处理 Skill 不等于授权扫描用户未指定的文章、账号和目录。

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

状态只记录 Skill、来源、版本、最近检查时间和校验结果，不保存凭据、样文和风格档案。

使用统一结构，并在写入时保留其他 Skill 的记录：

```json
{
  "schema_version": 1,
  "skills": {
    "writing-style": {
      "source": "https://github.com/bryce-code-world/skills",
      "version": "1.1.0",
      "last_check_attempt": "2026-07-31T00:00:00Z",
      "last_check_result": "current"
    }
  }
}
```

每次触发时执行非阻塞检查：

1. 距离 `writing-style` 上次检查或尝试不足 24 小时时跳过联网。
2. 到期时读取
   `https://raw.githubusercontent.com/bryce-code-world/skills/main/writing-style/references/release.json`。
3. 记录本次检查时间和结果。
4. 远端版本等于本地版本时继续当前任务。
5. 远端版本高于本地版本时，继续使用当前版本完成本轮任务，并在交付时说明差异、等待更新确认。
6. 远端版本低于本地版本时不降级，报告版本异常。
7. 用户确认更新后，在临时目录准备候选版本，校验通过再备份和切换；失败时保留或恢复旧版本。

安装目录是链接或 Junction 时，不替换链接。先检查源码仓库；存在未提交修改、冲突或无法快进时停止更新。

无法取得可靠版本时，不声称已经是最新版本。

已安装的可选能力只在当前任务实际需要时检查更新，同一依赖 24 小时内最多检查一次。来源提供版本清单时比较版本；否则比较声明分支的远端提交。发现更新后仍需用户确认，不自动覆盖。

## 可选能力

对话采集、样文提炼、档案管理、风格选择和语言层应用没有运行时强依赖。

调研新参照风格时，优先使用当前环境已经可用的检索、浏览和文档处理能力。

用户明确指定专项 Skill 但当前不可用时，使用其权威来源触发一次安装确认；来源不明确时请求用户提供或确认，不自动搜索同名包。
