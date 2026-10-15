# 初次安装、共享工具环境与手动备用流程

## 推荐：交给当前 AI Agent

把下面 GitHub Skill 地址发给你正在使用的**兼容 Agent Skills 的 AI Agent**，让它采用自身可用的 Skill 安装方式获取完整目录，不需要用户先下载 ZIP：

`https://github.com/bryce-code-world/skills/tree/main/ai-multi-media-kit`

先让宿主检查它是否具备当前任务所需的本机文件、终端和网络权限；**能读取 SKILL.md 不等于有权访问本机电脑**。详见 [Agent 兼容指南](AGENT_COMPATIBILITY.md)。有本地命令能力时，首次选择独立的工具目录和企业知识库目录，再调用 `SETUP-WINDOWS.ps1`（Windows）或 `SETUP-UNIX.sh`（macOS/Linux）；第三方依赖先审查来源和费用后经用户授权按需安装。不改变系统级 PATH。

## 不同 Agent 如何复用之前的工具环境

首次成功初始化后，工具目录与知识库目录会登记到**当前操作系统用户共享**的安装索引：

- Windows：`%LOCALAPPDATA%\ai-multi-media-kit\local-install.json`
- macOS/Linux：`${XDG_CONFIG_HOME:-~/.config}/ai-multi-media-kit/local-install.json`

另一款 Agent 只要以**相同的系统用户身份且有本地文件权限**运行，就可读取这个路径索引；再与工具目录的 `config/workspace.json` 核对，不需要重新安装 Python 和 FFmpeg。共享索引只是小型元数据（可能位于系统盘），工具、浏览器运行环境、缓存、输出仍在用户选定的工作区。

旧版 V0.3 使用主 Skill 目录 `config/local-install.json` 的索引，仅在共享索引缺失时回退读取；若共享索引损坏或路径失效，停止并询问原工作区路径，不进行磁盘扫描或自动重装。可使用已可用的 Python 运行主 Skill 内 `scripts/workspace_locator.py show` 查看路径和来源；需显式恢复时执行 `scripts/workspace_locator.py register --install-root <已有工具目录>`。纯云端隔离 Agent 无法分享用户本地的这个索引。

## 手动备用安装

如果当前 AI Agent 不支持从 GitHub 直接导入 Skill，请将本目录复制到该宿主能发现的 Skill 位置，再通过内置引导器初始化**运行环境**，不是另外安装一套 Skill：

Windows（需要 PowerShell 5.1+）：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\SETUP-WINDOWS.ps1
```

macOS/Linux：

```bash
bash ./SETUP-UNIX.sh
```

按提示输入两个互不嵌套的目录：工具工作区、企业知识库。引导器将可用的 Python 3.12/uv、便携 Git（Windows）与 FFmpeg/FFprobe、各类缓存尽量放在工具目录。再次运行只复用符合校验的现有工具和知识库内容，不自动覆盖。下载需网络/证书和系统基础解压工具；Windows ARM64 的 FFmpeg、Linux musl 等需单独检查支持情况。少量系统配置、下载安全日志可能仍位于系统盘。

## 日常命令（由具备终端能力的 Agent 调用）

在**已经初始化的工具工作区**，可通过绝对路径调用：

Windows：

```powershell
.\RUN-STUDIO-WINDOWS.ps1 -Task doctor --scope core --strict
.\RUN-STUDIO-WINDOWS.ps1 -Task materials sources
.\RUN-STUDIO-WINDOWS.ps1 -Task studio new --id demo-001 --title "我的第一条视频"
.\RUN-STUDIO-WINDOWS.ps1 -Task installer --component mpt # 仅显示安装计划
```

macOS/Linux：

```bash
bash ./run-studio.sh doctor --scope core --strict
bash ./run-studio.sh materials sources
bash ./run-studio.sh studio new --id demo-001 --title "我的第一条视频"
bash ./run-studio.sh installer --component mpt  # 仅显示安装计划
```

然后由当前 Agent 读企业知识库的 `brand.md`、`audience.md`、`review-rules.md`，调用内部 `ai-media-*` Skill 生产脚本、执行审查和选材。脚本、成片、发布包都可以让用户**直接在当前对话中明确批准对应内容 ID/阶段**，Agent 原样引用该用户消息执行 `studio approve --chat-message` 登记，不需用户手动输入终端口令；没有明确真人表态时不能推断批准。真正视频制作需 FFmpeg/MPT 已装且可用；真实平台上传仍有独立的 `PUBLISH` 确认。参见 [内容结构](CONTENT_SCHEMA.md)、[素材源](MATERIAL_SOURCES.md)、[工具依赖](TOOLCHAIN.md)。

仅需文本回答的 Agent 可以跳过全部本地命令，绝不能把无法执行的视频渲染、浏览器登录或投稿说成已经完成。
