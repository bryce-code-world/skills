# V3 首次使用与初始化

**推荐方式：** 在 Codex 中发送 `https://github.com/bryce-code-world/skills/tree/main/ai-multi-media-kit`，请 AI 按原生 Skill 安装方式获取完整目录并引导初始化。无需用户自己下载 ZIP、预装 Python 或手动执行下面的命令。首次使用由 AI 检查 Skill 是否可发现、询问工具/企业知识库路径、展示外部依赖计划，并经授权后调用安装器。安装过程与正常业务使用的区别见 [项目 README](../README.md)。

下面是 **Agent 无法自动安装或需要手动部署时的备用步骤**（下载安装运行时依赖仍可能需要联网）：

1. 解压 ZIP。Windows 双击 `SETUP-WINDOWS.cmd`（本体 `SETUP-WINDOWS.ps1`）；Linux/macOS 执行 `bash SETUP-UNIX.sh`。无需事先安装 Python / uv / Git。
2. 交互输入两个**不嵌套**的目录：工具工作区、企业知识库。Python 3.12/uv、Windows 便携 Git、FFmpeg/FFprobe、临时缓存优先集中放在工具工作区。网络下载失败会报错，可修复网络后原位置重跑；已经校验的安装会跳过。
3. 用系统内置启动器运行 `doctor`。Windows：`powershell -File RUN-STUDIO-WINDOWS.ps1 -Task doctor --scope core --strict`；macOS/Linux：`bash ./run-studio.sh doctor --scope core --strict`。
4. 改知识库目录下的 `brand.md`、`audience.md`、`review-rules.md`。在 Codex 中打开工具工作区，调用 `ai-media-studio` 生成选题/脚本。内容状态操作通过 `RUN-STUDIO-WINDOWS.ps1 -Task studio` 或 `run-studio.sh studio`，**不要假设全局 python 命令存在**。
5. 素材库默认是企业知识库 `materials/`。用 `materials add-source --name nas --path <共享盘已挂载路径>` 增加来源，之后 `materials scan`、`materials search --query <关键词>`；需要的话 `materials preview/annotate` 标注内容与授权，再 `studio render --material-ids`。见 `docs/MATERIAL_SOURCES.md`。缺素材时可先审查 `materials fetch-online` 计划。
6. 核心创作不强制任何第三方模型 Key；若希望安装第三方 Skills、MoneyPrinterTurbo、发布 CLI，先运行 `installer --profile core` 看计划，再 `installer --profile core --install` 明确批准联网获取未审计上游代码。实际平台发布还需账号登录和人工确认。

## 边界和风险

- Windows x64、Windows ARM64、Linux glibc x64/ARM64、macOS Intel/Apple Silicon 的 uv 启动程序有固定校验清单。FFmpeg 自动下载不覆盖 Windows ARM64；该平台先用自己的已审核媒体二进制。
- 系统基础命令（PowerShell、Bash、curl/wget、tar/解压、SHA256 命令）属于引导器的最小依赖。缺少则要由操作系统提供，不能由不存在的 Python 解决。
- macOS/Linux Git 不强制预装：安装器没找到 git 时走 GitHub ZIP Commit 包获取。Windows 尽量使用工作区内的 MinGit。
- 发布平台界面改版、验证码、Cookies 过期、实际许可和接口权限不能通过安装脚本保证。
- Windows 执行策略设置只限启动的 PowerShell 进程，不修改机器策略；Mac 可能会要求确认已下载的二进制。
- 密钥、Cookie、企业资料留在用户工作区或外部知识库，不写入 Git 或导出的安装套件。

## 运行命令举例

Windows (PowerShell，在工作区内)：

```powershell
.\RUN-STUDIO-WINDOWS.ps1 -Task doctor --scope video --strict
.\RUN-STUDIO-WINDOWS.ps1 -Task installer --component mpt
.\RUN-STUDIO-WINDOWS.ps1 -Task installer --component mpt --install
.\RUN-STUDIO-WINDOWS.ps1 -Task studio new --id sample-001 --title "一个短视频选题"
```

macOS/Linux：

```bash
bash ./run-studio.sh doctor --scope video --strict
bash ./run-studio.sh installer --component mpt
bash ./run-studio.sh installer --component mpt --install
bash ./run-studio.sh studio new --id sample-001 --title '一个短视频选题'
```

脚本生成和审核需要 Codex 读取企业知识库；参考 `docs/CONTENT_SCHEMA.md` 生成结构化数据，并经过人工明确授权才能剪辑和发布。

## 作为源码 Skill 存放在 bryce-skills 时

当前项目目录名为 `ai-multi-media-kit`。若由 Codex 发现并加载，入口为本目录的 `SKILL.md`；在 Skill 目录运行引导安装后，会将生产工作区及子 Skills 安装到用户选定的其他目录（不可与企业知识库目录嵌套）。对父仓库不会做全局环境变更。
