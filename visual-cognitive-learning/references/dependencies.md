# 依赖与更新

只在检查本 Skill 更新，或当前任务确实需要可选能力时读取本文件。

## 一、核心依赖

生成的 HTML 没有外部运行时依赖。确定性校验优先使用系统原生适配器：

- Windows PowerShell 5.1 及以上。
- Linux、macOS 的 POSIX `sh` 和系统基础工具。
- Python 3.8 及以上只作后备和参考实现。

三套脚本都不是打开最终 HTML 的依赖。

## 二、可选能力

| 能力 | 触发条件 | 降级 |
|---|---|---|
| `lightning` | 输入仍零散、冲突或缺少清晰内容内核 | 自行建立来源账本；事实仍不清楚时停止对应模拟 |
| 当前 Agent 已暴露的视觉设计能力 | 交互规格已经明确，主题需要专项视觉方向 | 使用本 Skill 的主题化视觉原则 |
| 浏览器控制或测试能力 | 需要实际打开、操作、截图或窄屏验证 | 完成事实和静态检查，明确浏览器未验证 |

以当前 Agent 暴露的 Skill 和工具为准，目录存在不等于可调用。缺失时先说明用途、可信来源和降级方案；只有用户确认后才安装。

## 三、自身更新

本地版本读取 [release.json](release.json)。更新检查状态依次使用：

```text
<SKILL_DEPENDENCY_HOME>/state.json
<CODEX_HOME>/skill-dependencies/state.json
<用户主目录>/.codex/skill-dependencies/state.json
```

每次触发时：

1. 距离 `visual-cognitive-learning` 上次检查或尝试不足 24 小时时，跳过联网。
2. 到期时读取 `https://raw.githubusercontent.com/bryce-code-world/skills/main/visual-cognitive-learning/references/release.json`。
3. 检查失败、版本相同或发现新版本时，都继续当前任务。
4. 发现新版本时只在交付时说明，等待用户确认，不自动覆盖。

无法取得可靠版本时，不声称已经是最新版。安装或更新授权不扩大读取、上传、发布或覆盖文件的权限。
