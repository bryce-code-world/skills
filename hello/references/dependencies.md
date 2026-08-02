# 依赖与更新

本 Skill 的访谈、候选识别、资料维护和上下文生成没有外部运行时强依赖。

确定性存储优先使用系统原生适配器：Windows PowerShell 5.1 及以上，或 POSIX `sh` 和系统基础工具。Python 3.8 及以上只作后备。

本地版本读取 [release.json](release.json)。更新检查状态与其他 Bryce Skills 共用：`SKILL_DEPENDENCY_HOME/state.json`、`CODEX_HOME/skill-dependencies/state.json`，或用户主目录 `.codex/skill-dependencies/state.json`。

同一 Skill 距离上次检查或尝试不足 24 小时时跳过联网。到期时读取：

```text
https://raw.githubusercontent.com/bryce-code-world/skills/main/hello/references/release.json
```

检查失败或发现新版本时继续当前任务，只在交付时报告。更新必须由用户确认，不自动覆盖 Skill 或个人资料。

