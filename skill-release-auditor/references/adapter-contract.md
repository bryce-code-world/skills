# 适配器契约

## 一、GitHub 固定副本

只接受 GitHub URL 或 `owner/repo`。先用只读 Git 命令解析 ref，再固定为完整 commit。

1. 使用 `git ls-remote <url> <ref>` 取得候选引用。
2. 没有唯一结果时，区分不存在、无权限和网络不可达；不要猜测默认分支。
3. 在系统临时目录初始化空仓库，执行浅层 fetch，并检出解析出的 commit。
4. 确认 `git rev-parse HEAD` 等于固定 commit。
5. 验证用户指定 Skill 路径存在且唯一。多 Skill 仓库只选择目标目录。

私有仓库没有现成只读权限时标记 `BLOCKED`。不要发起登录，不要请求或保存 Token。

远端层阻塞后不再读取仓库内容。结构、发布、安装、发现和行为层全部标记为 `NOT_RUN`。

## 二、Frontmatter 子集

原生脚本不解析通用 YAML，只接受 Skill 入口实际需要的可移植子集：

- `---` 必须位于首行，结束分隔符必须位于第四行；
- 分隔符之间只能有 `name: <value>` 和 `description: <value>`，顺序不限且各出现一次；
- 字段不得缩进，冒号后必须有一个空格；
- 值必须是非空单行字符串；允许无转义的单引号或双引号包裹；
- 未加引号的值不得包含 YAML 集合、锚点、标签、块文本、注释或嵌套映射控制字符。

多行字符串、数组、对象、锚点、引用、标签和其他复杂 YAML 直接判为 `FAIL`。检查器不下载解析器，不申请安装授权，也不因 PATH 中存在某个工具而改变判定。

结构检查还会核对 Skill 入口中的 Markdown 相对链接：链接目标必须位于 Skill 目录内且实际存在；锚点和外部 URL 不参与本地文件检查。若存在 `agents/openai.yaml`，当前无依赖检查器接受以下最小标量结构：`interface.display_name`、`interface.short_description`、`interface.default_prompt` 必须是非空值，`policy.allow_implicit_invocation`（如存在）只能是 `true` 或 `false`；不符合该子集时判为 `FAIL`。

## 三、直接安装

原生脚本的 `--installer direct` 把固定 Skill 目录复制到本次临时目录。
安装位置为 `.agents/skills/<name>`。

脚本比较文件数量和 SHA-256。这个适配器不写入用户目录，也不证明 Codex 已经发现 Skill。

## 四、npx 安装

只在用户要求、发布说明声明或需要验证该安装入口时运行。使用固定副本作为输入，避免默认分支在检查过程中变化。

1. 确认 Node.js 和 npx 已存在；缺失时标记 `BLOCKED`，不要为本层自动安装运行时。
2. 创建本次隔离工作目录和隔离 npm 缓存，并在工作目录初始化 Git 仓库，使安装器选择项目范围。
3. 在隔离工作目录运行：

```text
npx --yes skills@1.5.22 add <fixed-checkout> --skill <name> --agent codex --copy --yes
```

4. 检查 `.agents/skills/<name>/SKILL.md`、安装器退出码和目标身份。
5. 把安装结果与固定副本逐文件比较。不能绑定或证明固定 commit 时标记 `BLOCKED`。
6. 清理隔离工作目录和 npm 缓存。发现隔离范围外副作用时如实报告。

不要使用 `--global`。不要执行候选 Skill 的脚本。

## 五、Codex 发现与行为

把安装副本置于全新的隔离仓库 `.agents/skills/<name>`。

根据官方 OpenAI Skills 文档，Codex 会从当前目录到仓库根扫描 `.agents/skills`。目录存在本身仍不是发现证据。

只有宿主能够输出目标 Skill 名称与实际路径、调用记录或等价证据时，才判发现通过。

无法观察时标记 `BLOCKED`。

行为检查使用新会话。样本必须包括：

- 一个明确匹配 description 的正向请求；
- 一个语义相近但在范围外的反向请求；
- 一个试图扩大路径、安装或外部写权限的边界请求；
- 一个输入或可选能力缺失的失败请求。

优先读取目标 Skill 内的 `references/behavior-cases.md`。文件必须同时给出四类用户请求、是否触发、预期行为、禁止行为和通过标准，而且不能引用目标 Skill 目录之外的文件。

没有案例文件时，只接受用户提供的案例或经用户确认的 AI 草案。案例不完整或预期未经确认时标记 `BLOCKED`。

被测新会话只能获得用户请求，不能获得预期行为、禁止行为和通过标准。读取目标 `SKILL.md` 的真实路径、宿主调用记录或等价轨迹作为触发证据；只根据回答内容猜测是否调用 Skill 不构成证据。
