# API 客户端模块设计

> 所属层：`Core/Networking/`
> 依赖：Foundation (URLSession), Shared/Extensions

## 1. 功能范围

- 封装 OpenAI-compatible Chat Completion API（`/v1/chat/completions`）
- 封装 OpenAI Responses API（`/v1/responses`）
- 通过端点级 `APIMode` 配置在两种 API 模式间切换
- 支持普通请求和 SSE 流式响应（`stream: true`）
- 多 API 端点配置切换
- 统一错误处理与基础重试
- 请求取消（Task cancellation）

## 2. 文件清单与职责

| 文件 | 职责 |
|---|---|
| `APIClient.swift` | 主客户端，暴露 `sendMessage()` 和 `streamMessage()`，根据 `endpoint.apiMode` 分发到 Chat Completions 或 Responses 实现 |
| `SSEStreamParser.swift` | 将 `URLSession.AsyncBytes` 逐行解析为 SSE 事件流，支持 `event:` 类型行 |
| `APIMode.swift` | API 模式枚举：`chatCompletions` / `responses` |
| `APIEndpointConfig.swift` | 端点配置值对象（含 `apiMode`，从 `APIEndpointRecord` 转换） |
| `APIRequest.swift` | Chat Completion 请求体构建 |
| `APIResponse.swift` | Chat Completion 响应模型：完整响应 + 流式 Delta |
| `ResponsesAPIRequest.swift` | Responses API 请求体构建（自动提取 system → `instructions`） |
| `ResponsesAPIResponse.swift` | Responses API 响应模型 + 到 `ChatCompletionResponse` 的转换 |
| `APIError.swift` | 统一错误枚举 |

## 3. 核心接口定义

### 3.1 APIClient

```swift
final class APIClient: Sendable {
    private let session: URLSession

    init(session: URLSession = .shared)

    /// 非流式请求：发送消息，返回完整响应
    func sendMessage(
        messages: [ChatMessage],
        endpoint: APIEndpointConfig,
        parameters: ModelParameters
    ) async throws -> ChatCompletionResponse

    /// 流式请求：发送消息，返回 AsyncThrowingStream 逐 token 输出
    func streamMessage(
        messages: [ChatMessage],
        endpoint: APIEndpointConfig,
        parameters: ModelParameters
    ) -> AsyncThrowingStream<StreamDelta, Error>
}
```

### 3.2 SSEStreamParser

```swift
struct SSEStreamParser {
    /// 从 URLSession AsyncBytes 解析 SSE 事件
    /// 处理 `data:` 行，忽略注释行（`:` 开头），遇到 `[DONE]` 终止
    static func parse(
        bytes: URLSession.AsyncBytes
    ) -> AsyncThrowingStream<SSEEvent, Error>
}

struct SSEEvent {
    let eventType: String?  // Responses API 使用 typed events (如 "response.output_text.delta")
    let data: String        // JSON 字符串
}
```

### 3.3 API 模式

```swift
enum APIMode: String, Codable, Sendable, CaseIterable {
    case chatCompletions    // POST /v1/chat/completions（默认）
    case responses          // POST /v1/responses
}
```

APIClient 根据 `endpoint.apiMode` 在内部分发：
- `chatCompletions`：现有 Chat Completions 逻辑
- `responses`：Responses API 适配器（自动从 messages 提取 system → instructions，不支持的参数静默忽略）

上层代码（ChatViewModel、ContextManager）完全不感知 API 模式差异。

### 3.4 请求/响应模型

```swift
// --- 请求 ---
struct ChatMessage: Codable {
    let role: String       // "system" | "user" | "assistant"
    let content: String
}

struct ChatCompletionRequest: Codable {
    let model: String
    let messages: [ChatMessage]
    let stream: Bool
    let temperature: Double?
    let topP: Double?
    let maxTokens: Int?
    let frequencyPenalty: Double?
    let presencePenalty: Double?
    let stop: [String]?

    enum CodingKeys: String, CodingKey {
        case model, messages, stream, temperature, stop
        case topP = "top_p"
        case maxTokens = "max_tokens"
        case frequencyPenalty = "frequency_penalty"
        case presencePenalty = "presence_penalty"
    }
}

struct ModelParameters {
    var temperature: Double = 0.8
    var topP: Double = 1.0
    var maxTokens: Int? = nil        // nil = 模型默认
    var frequencyPenalty: Double = 0.0
    var presencePenalty: Double = 0.0
    var stop: [String]? = nil
}

// --- 响应（非流式） ---
struct ChatCompletionResponse: Codable {
    let id: String
    let choices: [Choice]
    let usage: Usage?

    struct Choice: Codable {
        let index: Int
        let message: ChatMessage
        let finishReason: String?
        enum CodingKeys: String, CodingKey {
            case index, message
            case finishReason = "finish_reason"
        }
    }
    struct Usage: Codable {
        let promptTokens: Int
        let completionTokens: Int
        let totalTokens: Int
        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
        }
    }
}

// --- 响应（流式 chunk） ---
struct ChatCompletionChunk: Codable {
    let id: String
    let choices: [ChunkChoice]

    struct ChunkChoice: Codable {
        let index: Int
        let delta: Delta
        let finishReason: String?
        enum CodingKeys: String, CodingKey {
            case index, delta
            case finishReason = "finish_reason"
        }
    }
    struct Delta: Codable {
        let role: String?
        let content: String?
    }
}

/// 流式输出的单个增量
struct StreamDelta {
    let content: String         // 增量文本片段
    let finishReason: String?   // nil 表示未结束
}
```

### 3.5 APIEndpointConfig

```swift
struct APIEndpointConfig {
    let baseURL: URL
    let apiKey: String?
    let modelName: String
    let maxContextTokens: Int
    let apiMode: APIMode           // 默认 .chatCompletions

    init(from record: APIEndpointRecord) throws
}
```

### 3.5 APIError

```swift
enum APIError: LocalizedError {
    case invalidURL(String)
    case httpError(statusCode: Int, body: String?)
    case decodingError(underlying: Error)
    case streamParsingError(String)
    case networkError(underlying: Error)
    case cancelled
    case noEndpointConfigured

    var errorDescription: String? { ... }
}
```

## 4. 流式请求处理流程

```
┌──────────────────────────────────────────────────────────────┐
│  ChatViewModel                                               │
│    调用 apiClient.streamMessage(messages, endpoint, params)  │
└──────────────────┬───────────────────────────────────────────┘
                   │
                   ▼
┌──────────────────────────────────────────────────────────┐
│  APIClient.streamMessage()                               │
│  1. 构建 ChatCompletionRequest (stream: true)            │
│  2. 构建 URLRequest (POST, JSON body, Bearer token)      │
│  3. 调用 session.bytes(for: request)                     │
│  4. 将 AsyncBytes 传入 SSEStreamParser.parse()           │
│  5. 将 SSEEvent → ChatCompletionChunk → StreamDelta      │
│  6. 通过 AsyncThrowingStream yield 每个 delta            │
└──────────────────┬───────────────────────────────────────┘
                   │
                   ▼
┌──────────────────────────────────────────────────────────┐
│  SSEStreamParser.parse(bytes:)                           │
│  逐行读取 AsyncBytes:                                    │
│  - 空行 → 事件边界，发出累积的 data                       │
│  - "data: [DONE]" → 流结束                               │
│  - "data: {...}" → 累积 JSON 数据                        │
│  - ": " 开头 → 忽略（SSE 注释 / keep-alive）            │
└──────────────────────────────────────────────────────────┘
```

## 5. 请求构建细节

### URL 拼接

```
baseURL + "/chat/completions"
例: http://localhost:8080/v1 → http://localhost:8080/v1/chat/completions
```

### 请求头

```
Content-Type: application/json
Authorization: Bearer {apiKey}     // 仅当 apiKey 非空时设置
Accept: text/event-stream           // 仅流式请求
```

### 编码

- 请求体使用 `JSONEncoder`，`keyEncodingStrategy` 保持默认（CodingKeys 已处理 snake_case）
- 忽略 nil 字段（使用 `encodeIfPresent`）

## 6. 错误处理策略

| 场景 | 处理方式 |
|---|---|
| HTTP 4xx | 解析 body 中的 error message，抛出 `httpError` |
| HTTP 5xx | 抛出 `httpError`，由上层决定是否重试 |
| 网络不可达 | 抛出 `networkError` |
| JSON 解码失败 | 抛出 `decodingError`，附带原始错误信息 |
| SSE 格式异常 | 抛出 `streamParsingError`，附带异常行内容 |
| Task 被取消 | 抛出 `cancelled`（Swift 自动通过 `CancellationError` 传播） |

### 重试策略

- **不内置自动重试**。重试逻辑由 `ChatViewModel` 在 UI 层控制（用户点击"重试"按钮）
- APIClient 只负责单次请求的 send/receive

## 7. 取消支持

- `streamMessage()` 返回的 `AsyncThrowingStream` 天然支持 Swift Concurrency 取消
- 调用方持有 `Task` 引用，调用 `task.cancel()` 即可中断流式传输
- `URLSession` 底层在 Task 取消时自动中断网络请求

## 8. 线程安全

- `APIClient` 标记 `Sendable`，无可变状态
- `URLSession.shared` 本身线程安全
- 所有方法均为 `async`，通过 Swift Concurrency 保证安全

## 9. 对外依赖

| 模块 | 依赖内容 |
|---|---|
| `Core/Database` | `APIEndpointRecord`（用于 `APIEndpointConfig` 初始化） |
| 被依赖方 | `Features/Chat/ChatViewModel`、`Core/ContextManager/CompressionStrategy` |

## 实现证据（2026-04-16）

- 代码位置：
  - `OpenChat/Core/Networking/APIClient.swift` — 根据 apiMode 分发到 Chat Completions / Responses 实现
  - `OpenChat/Core/Networking/SSEStreamParser.swift` — 支持 `event:` 类型行
  - `OpenChat/Core/Networking/APIMode.swift` — API 模式枚举
  - `OpenChat/Core/Networking/APIRequest.swift` — Chat Completions 请求体
  - `OpenChat/Core/Networking/APIResponse.swift` — Chat Completions 响应体
  - `OpenChat/Core/Networking/ResponsesAPIRequest.swift` — Responses API 请求体（system → instructions 提取）
  - `OpenChat/Core/Networking/ResponsesAPIResponse.swift` — Responses API 响应体 + 转换
  - `OpenChat/Core/Networking/APIEndpointConfig.swift` — 含 apiMode 属性
  - `OpenChat/Core/Networking/APIError.swift`
- 已验证测试：
  - `OpenChatTests/Core/NetworkingTests/APIClientTests.swift` — Chat Completions 模式测试
  - `OpenChatTests/Core/NetworkingTests/SSEStreamParserTests.swift` — SSE 解析测试
  - `OpenChatTests/Core/NetworkingTests/ResponsesAPITests.swift` — Responses API 请求/响应/流式/参数过滤测试
- 全量 60 个测试通过（2026-04-16）
