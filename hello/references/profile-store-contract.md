# 个人资料存储协议

## 一、适配器

三个适配器必须遵守相同命令、参数、数据结构和退出码：

1. Windows：`scripts/profile_store.ps1`，Windows PowerShell 5.1 及以上。
2. Linux、macOS：`scripts/profile_store.sh`，POSIX `sh` 和系统基础工具。
3. 后备：`scripts/profile_store.py`，Python 3.8 及以上。

PowerShell 和 Shell 适配器不得调用 Python 或 Node.js。

## 二、根目录

解析顺序固定为：

1. `--root <path>`。
2. 环境变量 `HELLO_HOME`。
3. 都不存在时失败，不自行选择默认目录。

所有文本使用 UTF-8。根目录可以包含中文和空格。

## 三、命令

```text
resolve-root [--root <path>]
init --confirmed [--root <path>]
validate [--root <path>]
status [--root <path>]
configure [--capture-mode auto-stage|prompt|explicit] [--next-review-at <ISO-8601|none>] [--review-stage baseline|first-review|stable] --confirmed [--root <path>]
diff --input <candidate-profile.md> [--root <path>]
stage --input <candidate.md> [--kind <kind>] [--source <source>] --confirmed [--root <path>]
apply --input <candidate-profile.md> --summary-input <summary.md> --expected-version <n> --confirmed [--root <path>]
withdraw --id <candidate-id> --confirmed [--root <path>]
self-test
```

## 四、修改护栏

- `init`、`configure`、`stage`、`apply` 和 `withdraw` 必须带 `--confirmed`。
- `--confirmed` 只防误调用，不能代替用户授权。
- 自动暂存的持续授权只适用于 `stage`。
- `init` 不覆盖已有文件。
- `apply` 必须校验 `--expected-version`。
- `apply` 前把旧主档案复制到 `历史版本/` 和 `.backups/profile/`。
- 保存使用目标目录内临时文件，再替换正式文件。
- `withdraw` 把候选块移入 `.trash/candidates/`，不直接擦除。
- 版本冲突、输入为空或结构无效时停止，不修改权威文件。

## 五、状态文件

`.hello-state` 使用 UTF-8 `key=value`，必须包含：

```text
schema_version=1
profile_version=<positive integer>
capture_mode=auto-stage|prompt|explicit
created_at=<ISO 8601 UTC>
updated_at=<ISO 8601 UTC>
last_confirmed_at=<empty or ISO 8601 UTC>
next_review_at=<empty or ISO 8601 UTC>
review_stage=baseline|first-review|stable
```

未知键可以保留。缺少必需键、枚举非法或版本不是正整数时，`validate` 返回无效。

## 六、候选块

`stage` 生成：

```text
## C-<UTC timestamp>-<process id>

- 暂存时间：<ISO 8601 UTC>
- 类型：<kind>
- 来源：<source>
- 状态：待确认

<candidate input>
```

`kind` 和 `source` 中的换行必须压缩为空格。候选输入不能为空。

## 七、输出与退出码

除 `diff` 外，正常输出使用 UTF-8 JSON，至少包含：

```json
{
  "ok": true,
  "command": "validate",
  "root": "<resolved path>"
}
```

失败输出至少包含 `ok: false` 和可行动的 `error`。

| 退出码 | 含义 |
|---:|---|
| 0 | 命令成功 |
| 1 | `validate` 或 `status` 发现资料空间无效 |
| 2 | 参数、确认、版本、输入或文件操作失败 |

`diff` 输出人可读差异；内容相同时输出 `No changes.`。

## 八、自测

每个适配器的 `self-test` 必须只在隔离临时目录运行，并覆盖：

- 中文和空格路径。
- 初始化与不覆盖。
- 确认护栏。
- 结构校验与状态读取。
- 采集策略和回访时间配置。
- 候选暂存和撤回。
- 差异生成。
- 预期版本冲突。
- 快照、版本递增、日志和原子替换。

不得把测试数据写入真实用户空间。
