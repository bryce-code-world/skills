# 上游依赖

只在准备、诊断或升级核心依赖时读取本文件。

## 固定来源

- 仓库：`https://github.com/XiaomiMiMo/MiMo-Code`
- 固定提交：`c2059d510917e4eafe5b6ff47b8d15b472ee9d62`
- Skill 路径：`packages/opencode/src/skill/builtin/.bundle/learn-everything`
- Skill 名称：`learn-everything`
- 许可证：MIT，完整文本见 [upstream-license.txt](upstream-license.txt)
- 文件锁：[dependency-lock.json](dependency-lock.json)

自动安装器只下载文件锁列出的内容。校验成功后才把候选目录原子移动到用户级 Skill 目录。

## 自动安装

从本 Skill 目录运行：

```text
python -X utf8 scripts/ensure_learn_everything.py --json
```

安装器依次检查以下位置：

- 当前目录向上的 `.agents/skills`。
- `$CODEX_HOME/skills`。
- `$HOME/.agents/skills`。
- `$HOME/.codex/skills`。

发现一份匹配依赖时直接复用。发现多份同名依赖时停止并报告冲突。

全部缺失时，默认安装到 `$HOME/.agents/skills/learn-everything`。测试或用户明确指定其他用户级 Skill 根目录时，可以传入 `--dest-root <目录>`。

脚本退出状态：

- `0`：`installed` 或 `ready`。
- `2`：网络、权限、路径或读取错误。
- `3`：目标目录存在，但内容与固定版本冲突。
- `4`：下载文件或 Skill 身份校验失败。

目标目录存在时不下载。核心文件哈希完全匹配但缺少许可证或安装元数据时，只补齐这两项。

## 手动安装

自动安装失败时，可以显式调用 Codex 的 `$skill-installer`：

```text
$skill-installer 请从 XiaomiMiMo/MiMo-Code 安装
packages/opencode/src/skill/builtin/.bundle/learn-everything，
ref 固定为 c2059d510917e4eafe5b6ff47b8d15b472ee9d62。
```

安装器可能使用 `$CODEX_HOME/skills`。以它返回的实际路径为准，再对该目录运行本 Skill 的校验流程。

## 更新边界

不要自动跟随 `main`，也不要自动覆盖已有版本。

升级时先审查固定提交之间的差异，再更新文件锁、许可证、行为案例和版本号。来源、提交或哈希不能确认时停止升级。
