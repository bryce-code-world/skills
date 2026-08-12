# 适配器契约

## 一、GitHub 固定副本

只接受 GitHub URL 或 `owner/repo`。先用只读 Git 命令解析 ref，再固定为完整 commit。

1. 使用 `git ls-remote <url> <ref>` 取得候选引用。
2. 没有唯一结果时，区分不存在、无权限和网络不可达；不要猜测默认分支。
3. 在系统临时目录初始化空仓库，执行浅层 fetch，并检出解析出的 commit。
4. 确认 `git rev-parse HEAD` 等于固定 commit。
5. 验证用户指定 Skill 路径存在且唯一。多 Skill 仓库只选择目标目录。

私有仓库没有现成只读权限时标记 `BLOCKED`。不要发起登录，不要请求或保存 Token。

## 二、严格 YAML

优先使用 PATH 中能够通过正常和损坏 YAML 自测的 `yq`。不可用时，原生脚本返回 `authorization_required: true`。

用户同意后增加 `--allow-temp-yaml-parser`。脚本按系统和架构下载 `mikefarah/yq` `v4.53.3`，并使用脚本内固定 SHA-256 校验：

| 平台 | 文件 | SHA-256 |
|---|---|---|
| Windows x64 | `yq_windows_amd64.exe` | `e279bc506a452eeafcdf364f91a025455e402a8001169083caf01f4b64a544e2` |
| Windows ARM64 | `yq_windows_arm64.exe` | `c80ac96ff2a8d77d452d91304e11feef8fb23239900b3d1d88f47c2ec93be970` |
| macOS Intel | `yq_darwin_amd64` | `b4ba1ecce3c47f00803f4f964de38394326c7a32eb6540616e04fb2935a0f08d` |
| macOS Apple Silicon | `yq_darwin_arm64` | `877de31753a4dd2401aa048937aa9a7fc4d5f6ce858cf31508c5802954297213` |

哈希不一致时不执行下载文件。该授权不包含全局安装、PATH 修改、包管理器或其他工具。

## 三、直接安装

原生脚本的 `--installer direct` 把固定 Skill 目录复制到本次临时目录下的 `.agents/skills/<name>`。

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

预期结果必须来自用户、Skill 自带验收样本，或经用户确认的 AI 草案。只根据回答内容猜测是否调用 Skill 不构成证据。
