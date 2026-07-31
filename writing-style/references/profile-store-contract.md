# 声纹档案存储协议

## 目的

PowerShell、POSIX Shell 和 Python 适配器必须遵守本协议。平台脚本可以使用不同实现方式，但不得改变档案格式、路径优先级、确认护栏、版本规则和退出码语义。

## 适配器选择

按当前操作系统选择，不要求用户额外安装运行时：

1. Windows：`scripts/profile_store.ps1`，支持 Windows PowerShell 5.1 及以上；
2. Linux、macOS：`scripts/profile_store.sh`，使用 POSIX `sh` 和系统基础工具；
3. 原生适配器不可运行时：尝试 Python 3.8 及以上的 `scripts/profile_store.py`；
4. 三者都不可用时：Agent 只能按本协议使用自身文件工具执行；如果没有安全文件工具，则只保留会话内候选结果。

Python 是可选增强和参考实现，不是声纹 Skill 的硬依赖。

## 路径和数据

根目录优先级固定为：

1. 本次命令的 `--root <path>`；
2. 环境变量 `WRITING_STYLE_HOME`；
3. 当前用户主目录下的 `.writing-style`。

所有文本使用 UTF-8。用户空间和风格卡格式以 [profile-schema.md](profile-schema.md) 为准。

档案标识必须匹配：

```text
[a-z0-9][a-z0-9-]{0,63}
```

## 命令

所有适配器提供相同命令和参数：

```text
resolve-root [--root <path>]
validate [--root <path>]
list [--root <path>] [--kind personal|reference]
diff --kind <kind> --id <id> --input <candidate.md> [--root <path>]
init --confirmed [--root <path>]
save --kind <kind> --id <id> --input <candidate.md> --confirmed [--root <path>]
save --kind <kind> --id <id> --input <candidate.md> --replace --expected-version <n> --confirmed [--root <path>]
set-default --id <personal-id|none> --confirmed [--root <path>]
delete --kind <kind> --id <id> --confirmed [--clear-default] [--root <path>]
self-test
```

## 不变量

- `init` 不覆盖现有 `config.md`。
- 所有变更命令都要求 `--confirmed`。
- `--confirmed` 只防止误调用，不能替代对话中的用户确认。
- 新档案版本必须为 `1`。
- 更新必须同时提供 `--replace` 和当前 `--expected-version`。
- 更新后的版本必须等于旧版本加 `1`。
- 覆盖前复制到 `.backups`。
- 删除移动到 `.trash`，不直接擦除。
- 默认个人档案不能被静默删除；必须先切换默认，或显式使用 `--clear-default`。
- 单个档案的保存采用同目录临时文件后替换，避免写入半个文件。

## 输出和退出码

正常结果使用 UTF-8 JSON；`diff` 的标准输出是供人审核的文本差异。不同适配器可以采用不同的差异算法，但必须明确旧文件和候选文件，且内容相同时返回 `No changes.`。

所有 JSON 结果至少包含：

```json
{
  "ok": true,
  "command": "validate",
  "root": "<resolved path>"
}
```

失败结果至少包含：

```json
{
  "ok": false,
  "error": "<actionable message>"
}
```

退出码：

| 退出码 | 含义 |
|---:|---|
| `0` | 命令成功，或校验结果有效 |
| `1` | `validate` 或 `list` 发现用户空间/档案无效 |
| `2` | 参数、前置条件、确认、版本或文件操作失败 |

## 一致性测试

每个适配器的 `self-test` 必须在隔离临时目录执行，并至少覆盖：

1. 路径解析优先级；
2. 变更确认护栏；
3. 中文和空格路径；
4. 初始化；
5. 非法根目录；
6. 创建档案；
7. 设置默认档案；
8. 差异生成；
9. 预期版本护栏；
10. 版本递增更新；
11. 完整性校验；
12. 默认档案删除护栏；
13. 可恢复删除。

真实用户空间不得写入测试档案。
