---
description: "Use when working with API client, SSE streaming, network requests, or OpenAI-compatible API integration. Covers URLSession usage, SSE parsing, error handling, and request/response models."
applyTo: "**/Networking/**/*.swift"
---
# 网络层与 SSE 规范

## 设计原则

- 使用原生 `URLSession`，不引入 Alamofire 等第三方网络库
- 流式响应使用 `URLSession.AsyncBytes`
- SSE 解析自实现，不引入第三方 SSE 库
- `APIClient` 标记 `Sendable`，无可变状态

## APIClient 约束

- 只暴露两个核心方法: `sendMessage()` 和 `streamMessage()`
- 不内置自动重试逻辑（由 UI 层控制重试）
- 请求取消通过 Swift Concurrency 的 `Task.cancel()` 自然传播
- 不缓存请求或响应

```swift
final class APIClient: Sendable {
    func sendMessage(...) async throws -> ChatCompletionResponse
    func streamMessage(...) -> AsyncThrowingStream<StreamDelta, Error>
}
```

## 请求构建

- URL 拼接: `baseURL + "/chat/completions"`
- Content-Type: `application/json`
- Authorization: `Bearer {apiKey}`（仅 apiKey 非空时设置）
- Accept: `text/event-stream`（仅流式请求）
- body 编码使用 `JSONEncoder`，nil 字段使用 `encodeIfPresent` 跳过
- CodingKeys 处理 snake_case 映射 (`top_p`, `max_tokens` 等)

## SSE 解析规则

`SSEStreamParser` 逐行解析 `AsyncBytes`：

| 行内容 | 处理方式 |
|---|---|
| 空行 | 事件边界，发出累积的 data |
| `data: [DONE]` | 流结束，终止解析 |
| `data: {...}` | 累积为 JSON 数据 |
| `: ` 开头 | SSE 注释/keep-alive，忽略 |
| 其他 | 忽略未知字段 |

- 不将整个响应缓存在内存中
- 每个 SSE event 的 data 字段解码为 `ChatCompletionChunk`
- 从 chunk 中提取 `delta.content` 作为 `StreamDelta` yield

## 错误处理

统一使用 `APIError` 枚举：

| 场景 | 错误 case |
|---|---|
| URL 无效 | `.invalidURL(String)` |
| HTTP 4xx/5xx | `.httpError(statusCode:body:)` |
| JSON 解码失败 | `.decodingError(underlying:)` |
| SSE 格式异常 | `.streamParsingError(String)` |
| 网络不可达 | `.networkError(underlying:)` |
| 任务取消 | `.cancelled` |
| 未配置端点 | `.noEndpointConfigured` |

- HTTP 响应先检查 status code，非 2xx 时读取 body 中的 error message
- JSON 解码失败时附带原始 Error 信息便于调试
- 不将 `CancellationError` 显示给用户

## 请求/响应模型

- 所有模型为 `struct + Codable`
- 使用 `CodingKeys` 显式映射 snake_case 字段名
- 响应中的可选字段标记 `Optional`
- `ChatMessage` 作为通用消息类型，同时用于请求和响应

## 安全

- API Key 不打印到日志
- 不在 debug 日志中输出完整请求/响应体（仅输出字段摘要）
- 生产构建中禁用网络请求日志
