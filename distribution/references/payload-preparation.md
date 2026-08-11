# 平台投递载荷准备

把平台 Markdown 确定性转换为浏览器步骤可以直接消费的载荷。重复转换必须使用本 Skill 自带脚本，不得在单次任务中临时编写 DOCX、HTML、去 front matter 或图片替换脚本。

## 原生入口

Windows 优先使用兼容 Windows PowerShell 5.1 的脚本：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/prepare_article.ps1 `
  -Platform wechat `
  -InputPath <平台文章.md> `
  -OutputDirectory <任务临时目录>
```

macOS 和 Linux 优先使用 POSIX `sh` 与系统基础工具：

```sh
sh scripts/prepare_article.sh \
  --platform wechat \
  --input <平台文章.md> \
  --output <任务临时目录>
```

两个入口都不要求 Python、Node.js、WechatSync 或第三方包。Python 只能作为本地测试辅助，不能成为正式分发前提。

Windows 自测入口同样只依赖 Windows PowerShell 5.1：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test_prepare_article.ps1
```

macOS、Linux 或装有 POSIX `sh` 的环境运行：

```sh
sh scripts/test_prepare_article.sh
```

## 固定产物

脚本只在本次任务登记的 `.agent-tmp/<task-id>/` 或系统临时目录生成：

```text
manifest.json   # 标题、摘要、封面、正文文件和图片清单
body.md         # 去除 front matter 的平台 Markdown
body.html       # 用于富文本编辑器的标准 HTML
```

浏览器步骤上传图片后，用平台托管地址替换 `body.html` 中的 `__DISTRIBUTION_IMAGE_NNN__` 占位符，再填入编辑器。载荷使用完毕后按项目临时资源规则清理整个任务目录。

`manifest.json` 使用 `schema_version: 2`。每张正文图记录 `placeholder`、`relative_path`、`absolute_path`、`alt`、`caption` 和 `role`：

- `informative`：`alt` 非空，必须存在紧邻图片的非空 `图注：`；
- `decorative`：`alt` 为空，`caption` 必须为空；
- 兼容读取历史 `图：`，输出统一规范化为 `图注：`；
- 孤立图注、信息图缺少图注和装饰图带图注立即失败，不得作为普通正文继续转换。

## 微信富文本基线

- 正文：16px、1.85 行高、深灰、左对齐；
- 二级标题：19px、深色加粗、左对齐、充分留白和窄暖色边线；
- 三级标题：17px、深色加粗；
- 强调：只转换 Markdown 已有的语义加粗，不新增重点；
- 有序和无序列表：转换为正文级段落，保持 16px、1.85 行高，避免微信导入器压缩原生列表；
- 图片：正文宽度自适应，前后留白；
- 图注：紧邻信息图，13px、1.6 行高、灰色、居中，明显弱于正文；
- 禁止蓝底标题、大色块、卡片堆叠和整段高亮。

知乎的 `body.html` 使用关联的 `figure`/`figcaption` 语义。CSDN 和掘金的 `body.md` 把规范图注转换为紧邻图片的 Markdown 弱化样式。三个平台都优先使用原生标题、列表、代码和图片能力，不复制微信公众号富文本样式。

## 失败条件

- front matter 缺少 `platform` 或 `title`；
- 请求平台与文章 `platform` 不一致；
- 正文或封面不存在；
- 微信公众号或知乎正文包含平台契约禁止的代码块、引用块或 Markdown 表格；
- 正文图片不存在；
- 信息图缺少紧邻图注、存在孤立图注，或装饰图带有图注；
- 生成物不再是 UTF-8、LF 或存在未替换图片占位符；
- 真实编辑器回读后的语义、重点、标题层级、列表、图片或图注与载荷不一致。
