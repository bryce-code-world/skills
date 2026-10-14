# V3 安装与验收矩阵

| 编号 | 检查点 | 预期 |
| --- | --- | --- |
| A01 | Windows 10/11 无预装 Python，双击 SETUP-WINDOWS.cmd | uv 固定版本下载并校验，Python 3.12 在指定根目录 |
| A02 | macOS/Linux 无 Python/uv/Git，运行 SETUP-UNIX.sh | 本地 uv 和 Python；子 Skill 获取无 Git 可走 GitHub API ZIP |
| A03 | 路径含空格/中文 | 参数安全传递，初始化有效，不修改全局 PATH |
| A04 | 运行第二次初始化 | 不重复下载已验证 uv/FFmpeg/Git；已有知识文件不覆盖 |
| A05 | 安装目录和知识库互相嵌套 | 拒绝，且不创建第二套业务资产 |
| A06 | uv 安装文件校验失败、网络异常 | 显式报错停止，不标记成功 |
| A07 | FFmpeg 安装并运行版本检测 | `tools/ffmpeg/bin/ffmpeg`,`ffprobe` 可启动 |
| A08 | 断网缺失依赖 | 不触发其它未知安装/收费服务，返回失败 |
| A09 | 从运行入口 `doctor --scope core --strict` | 本地 Python/uv 与自有 Skill/知识库结构正常 |
| A10 | 内容生成/脚本审查、人工批准、视频合成 | AI 审核不能代替人工批准；成功合成有效 MP4 |
| A11 | 七平台内容导出/真实发布 | 导出包正常、未授权严禁自动发布；逐平台单独实测 |
| A12 | 导出/升级 | 用户资产不丢失、可重复运行、有日志和回滚基础 |
| A13 | 初始化企业素材源和重复初始化 | `material-sources.json` 指向 `knowledge_root/materials`；用户修改不被覆盖 |
| A14 | 本地/NAS 素材库索引与真实镜头核对 | 可扫描、按文件名/人工标签查找、产出预览帧；不把文本检索误报为视觉识别 |
| A15 | 素材许可/版本安全 | 未登记授权、路径已变更或文件被替换时拒绝通过素材 ID 成片；已许可来源可追溯 |
| A16 | 网络素材 MPT 补充 | 默认只预览计划，实际获取由用户确认；仅停在素材阶段，需另行检查素材授权与 API 费用 |
| A17 | 首次安装后的工作区定位 | 成功初始化后主 Skill 私有 `config/local-install.json` 记录工具/知识库绝对路径且 Git 忽略，不复制进工作区 |
| A18 | 跨项目/新会话和路径失效 | 全新进程可以只读定位并核对 `workspace.json`；目录丢失/错配立即报错，不修改 PATH 或猜测安装目录 |
| A19 | 重复初始化及显式切换 | 相同路径幂等不覆盖资料；显式初始化另一有效工作区后可更新默认索引；失败时不会改变旧索引 |

## 实测状态说明

- **在当前 Linux 容器实际测试：** Python 回归、Shell 脚本语法、Linux Shell 的离线模拟 uv/Python 安装流程、路径与幂等、ffmpeg 合成等（详见 `docs/VALIDATION_REPORT_V3.md`）。
- **当前环境未实测：** Windows PowerShell 5.1、macOS、在线下载 uv/Python/MinGit/FFmpeg、真实 MoneyPrinterTurbo/发布 CLI 安装、七个媒体账号真实投稿；必须在目标环境验收。
- **2026-10-14 本机新增验证：** Python 23 项回归中 21 项通过、2 项跳过（Linux 专用与缺少 FFmpeg）；新增多来源素材目录、索引、授权、在线获取 dry-run、资产导出和视频素材 ID 预检通过。
- **尚未实测：** 真实 MPT Pexels/Pixabay/Coverr 下载、基于新增素材 ID 的真实 FFmpeg 成片，以及国内媒体账号真实发布；不能把计划/测试替代线上验收。
- `doctor` 只验证本地依赖存在与结构，不能代替跨平台真实业务验收。
