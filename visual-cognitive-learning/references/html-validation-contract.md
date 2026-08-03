# HTML 校验协议

## 一、适配器与顺序

三个适配器必须遵守相同命令、检查顺序、JSON 结构和退出码：

1. Windows：`scripts/validate_html.ps1`，PowerShell 5.1 及以上。
2. Linux、macOS：`scripts/validate_html.sh`，POSIX `sh` 和系统基础工具。
3. 后备：`scripts/validate_html.py`，Python 3.8 及以上。

PowerShell 和 Shell 适配器必须独立实现，不得调用 Python、Node.js 或其他额外运行时。所有文本按 UTF-8 读取和输出，路径可以包含中文和空格。

## 二、命令

```text
check --path <html-file>
self-test
```

`check` 只接受现有普通文件。`self-test` 只在新建的隔离临时目录内写入测试数据，不读写用户产物。

## 三、违规代码

检查顺序固定如下；同一代码只输出一次：

| 代码 | 确定性条件 |
|---|---|
| `missing-doctype` | 没有 HTML5 doctype |
| `missing-html` | 没有完整 `html` 开始与结束标签 |
| `missing-head` | 没有完整 `head` 区域 |
| `missing-body` | 没有完整 `body` 区域 |
| `missing-lang` | `html` 没有非空 `lang` |
| `missing-title` | 没有非空 `title` |
| `missing-viewport` | 没有 `name="viewport"` 的 meta |
| `external-resource` | 资源标签的 `src` 或 `href` 指向非 `data:`、非纯锚点目标 |
| `css-external-url` | CSS `url(...)` 指向非 `data:`、非纯锚点目标 |
| `network-api` | 脚本出现网络 API |
| `dynamic-code` | 脚本出现 `eval` 或 `new Function` |
| `module-import` | 使用 module script 或 JavaScript 模块导入 |
| `duplicate-id` | 两个或更多元素使用同一非空 `id` |
| `unlabeled-control` | 非 hidden 的 `input`、`select` 或 `textarea` 没有 `aria-label`、`aria-labelledby` 或对应 `label[for]` |
| `missing-reduced-motion` | 没有 `prefers-reduced-motion` 声明 |
| `missing-inline-style` | 没有内联 `style` 区域 |
| `missing-static-content` | 移除脚本、样式和标签后，`body` 可见文本少于 40 个非空白字符 |

这些检查是保守的字面护栏，不是完整 HTML 解析器。如果字面结果与实际 DOM 不一致，以浏览器检查为准，并修正产物或协议。

## 四、输出与退出码

`check` 的标准输出是一行 UTF-8 JSON：

```json
{"ok":true,"command":"check","path":"<resolved path>","violations":[]}
```

发现违规时：

```json
{"ok":false,"command":"check","path":"<resolved path>","violations":["missing-lang","external-resource"]}
```

调用错误时：

```json
{"ok":false,"command":"check","error":"<actionable message>"}
```

`self-test` 成功输出：

```json
{"ok":true,"command":"self-test","tests":3}
```

| 退出码 | 含义 |
|---:|---|
| `0` | 检查通过或自测通过 |
| `1` | `check` 发现一个或多个确定性违规 |
| `2` | 参数、路径、读取或运行失败 |

## 五、共享测试向量

每个适配器的 `self-test` 至少覆盖：

1. 包含中文和空格路径的通过样本。
2. 同时触发全部违规代码的失败样本，并核对固定顺序。
3. 不存在的路径，应返回调用错误语义。

开发时使用同一批候选 HTML 分别运行三个适配器，对比 `ok`、`violations` 和退出码。未实际运行的平台必须明确记录。
