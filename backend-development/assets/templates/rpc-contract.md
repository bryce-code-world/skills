# <服务> RPC 协议

- 类型：依赖 RPC / 对外提供 RPC
- 调用方与提供方：
- Proto 权威路径：
- 文件按服务组织；每个业务作为独立章节。

## <业务名称>

### 基础定义

- 交互编号：
- 方法名：
- Request：
- Response：
- 业务场景与目的：
- 成熟度：
- 身份与权限上下文：
- 注意事项：

### Request

```proto
// 直接引用或维护与冻结 source Proto 一致的请求结构；注释和校验写在字段旁。
message <Request> {
  <type> <field> = <number> [(validate.rules) = ...];
}
```

### Response

```proto
message <Response> {
  <type> <field> = <number>;
}
```

公共 Request/Response 对象只在公共对象文档定义；这里通过类型名和链接复用，不重复展开字段。

## 调用语义

- 超时、重试和幂等：
- 并发和顺序：
- 依赖错误与调用方处理：
- 兼容与废弃：
- 示例与 Mock：
