> 本目录是可独立安装的 Codex Skill 源码。直接调用 `$ai-multi-media-kit` 可获取使用引导；实际内容生产需先运行初始化脚本创建独立工作区。

# ai-multi-media-kit（AI Media Studio V3）

这是一个基于 **Codex + 自有企业知识库 + Skills + CLI/MCP** 的国内新媒体工作区。重点支持小红书、抖音、微信视频号、B站、快手、微信公众号、知乎；短视频优先。不是独立的网页产品，也**不自动使用或上传任何平台账号**。

## 现在怎么安装

**Windows 10/11：** 解压后双击 `SETUP-WINDOWS.cmd`，也可以打开 PowerShell 运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\SETUP-WINDOWS.ps1
# 无交互安装（路径可有空格）
powershell -NoProfile -ExecutionPolicy Bypass -File .\SETUP-WINDOWS.ps1 -InstallRoot "D:\AI Media Studio" -KnowledgeRoot "D:\Company Knowledge" -NonInteractive
```

**macOS / Linux（glibc，x64/arm64）：**

```bash
bash ./SETUP-UNIX.sh
# 无交互安装
bash ./SETUP-UNIX.sh --install-root "$HOME/AI Media Studio" --knowledge-root "$HOME/Company Knowledge" --non-interactive
```

首次输入两个独立目录：① 安装根目录（工具、独立 Python 3.12、uv、Git/FFmpeg、缓存、日志）；② 企业知识库目录（品牌、用户画像、审核标准、素材等）。**无需提前安装 Python、uv 或 Git**；脚本只需要系统自带 PowerShell/Bash、HTTPS 下载能力和基本解压/校验命令。它不会创建系统级 Python，也不会修改全局 PATH。macOS/Linux 用系统已有 Git，若无 Git 则第三方仓库的安装器可以改走固定 SHA 的 GitHub ZIP 归档。

启动器默认联网下载 **校验过的 uv 0.12.19**、uv 管理的 **Python 3.12**；Windows 再安装便携式 MinGit 2.56.0.2；所有支持的平台尝试本地下载 FFmpeg/FFprobe 8.1.2。Windows ARM64 暂无自动 FFmpeg 构建，需要按提示手动导入；Linux Alpine/musl 也不在这版自动安装范围。

> 初次下载需要能够访问 Astral 的镜像服务及 GitHub 等分发地址，可能有数百 MB 的下载量；网络不通、证书或代理限制时会报告失败，不会伪装成功。少量系统安全日志与软件自身临时数据无法保证完全不落在系统盘。下载校验以固定 SHA256 为主，部分 FFprobe 按官方发布说明使用 MD5 校验，正式高安全环境可自行补充更强校验。

## 安装成功后怎么运行（无需系统 Python）

Windows：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "D:\AI Media Studio\RUN-STUDIO-WINDOWS.ps1" -Task doctor --scope core --strict
powershell -NoProfile -ExecutionPolicy Bypass -File "D:\AI Media Studio\RUN-STUDIO-WINDOWS.ps1" -Task studio new --id demo-001 --title "我的第一条视频"
```

macOS/Linux：

```bash
bash "$HOME/AI Media Studio/run-studio.sh" doctor --scope core --strict
bash "$HOME/AI Media Studio/run-studio.sh" studio new --id demo-001 --title "我的第一条视频"
```

如已有已登录的 Codex CLI，可在工作区运行 `start-codex.cmd` / `start-codex.sh`；也可直接用 Codex 桌面/IDE 打开安装根目录，输入：

> 使用 `ai-media-studio` Skill，检查本地环境和知识库，帮我策划 10 条短视频选题。不要自动发布，不要启用收费 API。

源仓库以 `SKILL.md` 为入口；独立工作区中以 `AGENTS.md` 和 `.agents/skills/ai-media-studio/SKILL.md` 编排。默认无模型 API Key 要求，但 Codex 本身的使用仍需正常登录和额度；其他视频/素材/配音服务的收费 API 独立计费。

## 额外的现成 Skills、视频工具、发布 CLI

自举安装器负责准备基础环境（Python / uv / Git / FFmpeg）；不会未经同意运行陌生仓库的安装脚本。需要内容生产第三方 Skills、MoneyPrinterTurbo 或平台发布 CLI 时，先预览计划，再授权：

```bash
# Linux/macOS，用套件自己的 Python 和 uv
bash ./run-studio.sh installer --profile core            # 预览
bash ./run-studio.sh installer --profile core --install  # 输入 INSTALL 授权
bash ./run-studio.sh installer --component mpt --install
bash ./run-studio.sh installer --component social --install
```

Windows 用 `RUN-STUDIO-WINDOWS.ps1 -Task installer` 替换上面的 `bash ./run-studio.sh installer`。依赖安装器会把上游仓库固定到 Git commit SHA，子 Skill 拷入项目级 `.agents/skills/`。平台账号登录、Cookie、MCP 授权与真实发布都必须由用户在受控环境中另行操作；所有发布默认 dry-run，不能把“生成发布包”当成“成功发帖”。

## 关键文件

| 路径 | 作用 |
|---|---|
| `SETUP-WINDOWS.ps1` / `SETUP-UNIX.sh` | 不依赖 Python 的第一次引导安装 |
| `RUN-STUDIO-WINDOWS.ps1` / `run-studio.sh` | 固定调用套件内的 Python、uv、Git、FFmpeg |
| `config/bootstrap-assets.json` | 基础可执行程序固定版本、URL 和文件哈希 |
| `scripts/bootstrap_assets.py` | 在指定目录安装受校验的 MinGit、FFmpeg/FFprobe |
| `scripts/installer.py` | 第三方 Skills / CLI / MCP 按需安装并锁定 Commit |
| `scripts/studio.py` | 内容、审核、视频成片、七平台发布包及人审闸门 |
| `scripts/doctor.py` | 分层检查，不把“工具存在”等同“已业务验收” |
| `knowledge-templates/` | 独立知识库模板，首装复制，重跑不覆盖 |

详见 `docs/START_HERE.md`、`docs/ACCEPTANCE_V3.md` 和 `docs/TOOLCHAIN.md`。

## 真实性说明

V3 的安装脚本逻辑、离线自检、原有核心状态机可在当前测试环境执行，但**当前云端无 GitHub 网络，也没有 Windows/macOS 本机**，所以不能声称这些平台已完成在线下载/真实账号发布验收。需在目标用户设备实际运行并检查 `doctor` 的结果后，才可判断整套依赖可用。
