# 档案与用户空间

## 目录

- [路径解析](#路径解析)
- [用户空间结构](#用户空间结构)
- [配置文件](#配置文件)
- [统一风格卡](#统一风格卡)
- [写入规则](#写入规则)
- [脚本操作](#脚本操作)

## 路径解析

按以下顺序选择根目录：

1. 用户在本次请求中明确指定的目录；
2. 环境变量 `WRITING_STYLE_HOME`；
3. Windows 的 `%USERPROFILE%\.writing-style` 或其他系统的 `$HOME/.writing-style`。

不把机器专属路径写入发布版 Skill。

路径不存在时先确认创建。路径不可访问时，不自动改用其他持久化位置。

## 用户空间结构

```text
<root>/
├── config.md
├── personal-profiles/
│   └── <profile-id>.md
└── reference-profiles/
    └── <profile-id>.md
```

- `personal-profiles`：本人、团队或账号的长期身份风格。
- `reference-profiles`：从其他作者材料提炼的私人参照风格。
- 文件名使用小写字母、数字和连字符；显示名称可以使用中文。
- 不在用户空间保存内置风格副本。

## 配置文件

使用以下最小格式：

```markdown
# 声纹用户空间

- schema_version: 1
- default_personal_profile: none
```

`default_personal_profile` 填写 `personal-profiles` 下的档案标识，不填写扩展名。

不存在默认档案时使用 `none`，并降级为内置通用默认风格。

不要在配置文件保存隐私原文、平台凭据或完整历史文章。

## 统一风格卡

```markdown
# <显示名称>

- id: <稳定标识>
- type: personal | reference
- version: 1
- status: candidate | confirmed
- updated_at: YYYY-MM-DD

## 来源

- 作者：
- 材料范围：
- 来源位置：
- 来源性质：用户陈述 | 来源事实 | 编辑推断

## 核心风格

- 核心气质：
- 价值取向：
- 观察视角：
- 作者—读者关系：

## 表达方法

- 用词：
- 句式：
- 段落与节奏：
- 结构与论证：
- 叙事方式：
- 信息密度与解释深度：

## 可调节范围

- 严肃度：
- 温度：
- 锋利度：
- 幽默度：
- 自我暴露：

## 使用边界

- 适合：
- 不适合：
- 需要收敛：
- 禁止项：

## 证据与判断

| 特征 | 来源位置 | 内容性质 | 支持或反例 | 置信度 |
|---|---|---|---|---|

## 未确认项

- none
```

要求：

- 每项稳定特征至少有一条证据；
- 单篇样文只能标记低置信度；
- 反例不能删除；
- 编辑推断不能写成用户明确偏好；
- 不保存不必要的长段原文；
- 参照档案不得包含冒充作者身份的指令。

## 写入规则

写入前展示：

```text
操作：
目标：
旧版本：
新版本：
主要变更：
来源：
影响：
```

只有用户明确确认后才执行。

更新成功后报告准确路径和版本。写入失败时保留候选内容，不声称已经保存。

## 脚本操作

先读取 [profile-store-contract.md](profile-store-contract.md)，再按系统选择：

- Windows：`powershell -NoProfile -ExecutionPolicy Bypass -File scripts/profile_store.ps1 <command>`；
- Linux、macOS：`sh scripts/profile_store.sh <command>`；
- 原生适配器不可运行时：`<python> scripts/profile_store.py <command>`。

三个适配器使用相同的命令参数：

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
```

不要手工覆盖配置或已有档案。命令、确认、版本、备份、回收、输出和退出码规则统一以存储协议为准。
