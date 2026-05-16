# API 客户端模块设计

> 所属层：`Core/Networking/`
> 依赖：Foundation (URLSession), Shared/Extensions

## 1. 功能范围

- 封装 OpenAI-compatible Chat Completions API（相对路径 `chat/completions`）
- 封装 OpenAI Responses API（相对路径 `responses`）
- 通过端点级 `APIMode` 配置在两种 API 模式间切换
- 支持普通请求和 SSE 流式响应（`stream: true`）
- 多 API 端点配置切换
- 统一错误处理；不内置自动重试
- 请求取消（Task cancellation）

> URL 约束：`APIClient` 只在用户配置的 `endpoint.baseURL` 后追加相对资源路径，不在请求代码中硬编码 `/v1`。OpenAI 官方端点的 `v1` 属于 OpenAI provider 的 baseURL（例如 `https://api.openai.com/v1`）；DeepSeek 官方 OpenAI-format baseURL 为 `https://api.deepseek.com`，请求路径为 `/chat/completions`。

## 2. 文件清单与职责

| 文件 | 职责 |
|---|---|
| `APIClient.swift` | 主客户端，暴露 `sendMessage()` 和 `streamMessage()`，根据 `endpoint.apiMode` 分发到 Chat Completions 或 Responses 实现 |
| `SSEStreamParser.swift` | 将 `URLSession.AsyncBytes` 逐行解析为 SSE 事件流，支持 `event:` 类型行 |
| `APIMode.swift` | API 模式枚举：`chatCompletions` / `responses` |
| `APIProviderDialect.swift` | 模型级供应商请求方言：`openAICompatible` / `deepSeekV4`，以及 DeepSeek V4 默认上下文与 reasoning effort |
| `APIEndpointConfig.swift` | 端点配置值对象（含 `apiMode` 与 `providerDialect`，从 `APIEndpointRecord` + `EndpointModelRecord` 转换） |
| `ModelParameters.swift` | 模型采样参数、thinking budget、DeepSeek V4 `reasoningEffort` |
| `ChatMessage.swift` | Chat 消息结构体，支持响应侧 `reasoning_content`，请求侧默认剥离 reasoning 内容 |
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
    case chatCompletions    // POST {baseURL}/chat/completions（默认）
    case responses          // POST {baseURL}/responses
}
```

APIClient 根据 `endpoint.apiMode` 在内部分发：
- `chatCompletions`：构建 OpenAI Chat Completions 兼容请求体并解析 `choices`
- `responses`：Responses API 文本适配器（自动从 messages 提取 system → `instructions`，将其余消息放入 `input`）

上层代码（ChatViewModel、ContextManager）完全不感知 API 模式差异。

### 3.4 请求/响应模型

```swift
// --- 请求 ---
struct ChatMessage: Codable {
    let role: String       // "system" | "user" | "assistant"
    let content: String
    let reasoningContent: String? // DeepSeek V4 响应侧 reasoning_content

    // 普通请求历史默认不携带 reasoning_content。
    func requestMessage(includeReasoningContent: Bool = false) -> ChatMessage
}

struct APIRequest: Codable {
    let model: String
    let messages: [ChatMessage]
    let stream: Bool
    let streamOptions: StreamOptions?
    let temperature: Double?
    let topP: Double?
    let maxTokens: Int?
    let maxCompletionTokens: Int?
    let frequencyPenalty: Double?
    let presencePenalty: Double?
    let stop: [String]?
    let thinking: DeepSeekThinkingConfig?
    let reasoningEffort: String?

    enum CodingKeys: String, CodingKey {
        case model, messages, stream, temperature, stop
        case streamOptions = "stream_options"
        case topP = "top_p"
        case maxTokens = "max_tokens"
        case maxCompletionTokens = "max_completion_tokens"
        case frequencyPenalty = "frequency_penalty"
        case presencePenalty = "presence_penalty"
        case thinking
        case reasoningEffort = "reasoning_effort"
    }
}

struct DeepSeekThinkingConfig: Codable {
    let type: String // "enabled" | "disabled"
}

struct ResponsesAPIRequest: Codable {
    let model: String
    let input: [ChatMessage]
    let instructions: String?
    let stream: Bool
    let temperature: Double?
    let topP: Double?
    let maxOutputTokens: Int?
    let store: Bool      // 当前实现固定 false
    let reasoning: ReasoningConfig?

    enum CodingKeys: String, CodingKey {
        case model, input, instructions, stream, temperature, store, reasoning
        case topP = "top_p"
        case maxOutputTokens = "max_output_tokens"
    }
}

struct ModelParameters {
    var temperature: Double = 0.8
    var topP: Double = 1.0
    var maxTokens: Int? = nil        // nil = 模型默认
    var frequencyPenalty: Double = 0.0
    var presencePenalty: Double = 0.0
    var stop: [String]? = nil
    var thinkingBudget: Int? = nil
    var reasoningEffort: ReasoningEffort = .high
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
        let completionTokensDetails: CompletionTokensDetails?
        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
            case completionTokensDetails = "completion_tokens_details"
        }
    }
}

// --- 响应（流式 chunk） ---
struct ChatCompletionChunk: Codable {
    let id: String
    let choices: [ChunkChoice]
    let usage: ChatCompletionResponse.Usage?

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
        let reasoningContent: String?
    }
}

/// 流式输出的单个增量
struct StreamDelta {
    let content: String         // 增量文本片段
    let reasoningContent: String?
    let finishReason: String?   // nil 表示未结束
    let usage: StreamUsage?
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
    let providerDialect: APIProviderDialect // 默认 .openAICompatible

    init(baseURL: URL, apiKey: String?, modelName: String, maxContextTokens: Int, apiMode: APIMode = .chatCompletions, providerDialect: APIProviderDialect = .openAICompatible)
    init(from endpoint: APIEndpointRecord, model: EndpointModelRecord) throws
}
```

### 3.6 APIError

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
│  1. 根据 APIMode 构建 APIRequest 或 ResponsesAPIRequest  │
│  2. 构建 URLRequest (POST, JSON body, Bearer token)      │
│  3. 调用 session.bytes(for: request)                     │
│  4. 将 AsyncBytes 传入 SSEStreamParser.parse()           │
│  5. Chat: ChatCompletionChunk → StreamDelta              │
│     Responses: typed SSE event → StreamDelta             │
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
│  - "event: ..." → 记录 Responses API typed event         │
│  - ": " 开头 → 忽略（SSE 注释 / keep-alive）            │
└──────────────────────────────────────────────────────────┘
```

## 5. 请求构建细节

### URL 拼接

`baseURL` 是供应商 API root，由端点配置决定是否包含版本前缀。APIClient 只追加相对资源路径：

| 操作 | 请求 URL |
|---|---|
| Chat Completions | `POST {baseURL}/chat/completions` |
| Responses | `POST {baseURL}/responses` |
| 模型列表 | `GET {baseURL}/models` |

示例：

| Provider | baseURL | Chat Completions URL |
|---|---|---|
| OpenAI | `https://api.openai.com/v1` | `https://api.openai.com/v1/chat/completions` |
| DeepSeek | `https://api.deepseek.com` | `https://api.deepseek.com/chat/completions` |
| 本地 OpenAI-compatible 服务 | `http://localhost:8080/v1` | `http://localhost:8080/v1/chat/completions` |

禁止在客户端请求函数中额外拼接固定 `/v1`，否则会破坏 DeepSeek 这类不以 `/v1` 作为主 baseURL 的端点。

### 请求头

```
Content-Type: application/json
Authorization: Bearer {apiKey}     // 仅当 apiKey 非空时设置
Accept: text/event-stream           // 仅流式请求
```

### 编码

- 请求体使用 `JSONEncoder`，`keyEncodingStrategy` 保持默认（CodingKeys 已处理 snake_case）
- 忽略 nil 字段（使用 `encodeIfPresent`）

## 6. OpenAI 兼容性核对

本节基于 OpenAI API Reference / OpenAI OpenAPI spec 和 DeepSeek 官方文档核对当前实现边界。

### 6.1 Chat Completions

当前实现覆盖：

- 路由：`POST {baseURL}/chat/completions`
- 必要字段：`model`、`messages`
- 常用采样字段：`temperature`、`top_p`、`frequency_penalty`、`presence_penalty`、`stop`
- 流式字段：`stream`；流式时自动带 `stream_options: { "include_usage": true }`
- token 上限：
  - 标准模式使用 `max_tokens`
  - `openAICompatible` 方言的 thinking/reasoning 模式使用 `max_completion_tokens`，其值包含可见输出 token 和 reasoning token 预算
  - `deepSeekV4` 方言使用 `max_tokens` + `thinking` / `reasoning_effort`，见 6.2
- 响应解析：
  - 非流式读取 `choices[].message.content` 和 `usage`
  - 流式读取 `choices[].delta.content`
  - 兼容 `reasoning_content` 增量和 `completion_tokens_details.reasoning_tokens`
  - 兼容 `stream_options.include_usage` 带来的 usage-only chunk

当前未覆盖 OpenAI Chat Completions 全量字段，例如 `tools` / `tool_choice` / `parallel_tool_calls`、多模态 content array、`response_format`、`metadata`、`logprobs`、`web_search_options`、`store`、`n`、`seed` 等。后续新增这些字段时，应先扩展请求/响应模型和测试，不应把当前文本聊天适配器描述为全量兼容实现。

### 6.2 DeepSeek V4 方言

DeepSeek V4 使用 OpenAI-compatible Chat Completions 路由，但请求体不是当前 OpenAI reasoning 分支的 `max_completion_tokens` 语义。模型级 `providerDialect = deepSeekV4` 时：

- 路由仍为 `POST {baseURL}/chat/completions`。
- 官方 baseURL 为 `https://api.deepseek.com`。
- 模型为 `deepseek-v4-flash` / `deepseek-v4-pro`，本地推断也覆盖 `deepseek-v4-*`。
- thinking enabled 时发送：
  - `thinking: { "type": "enabled" }`
  - `reasoning_effort: "high" | "max"`
  - `max_tokens` 作为可见输出上限
  - 不发送 `temperature`、`top_p`、`presence_penalty`、`frequency_penalty`
- thinking disabled 时发送：
  - `thinking: { "type": "disabled" }`
  - 常规采样参数按 UI 配置发送
- DeepSeek V4 返回的 `reasoning_content` 作为角色思考链保存和展示。当前 OpenChat 没有 Tool Calls 执行器，因此正常角色对话历史不会回传历史 `reasoning_content`；未来接入工具调用时，发生 tool call 的 assistant 消息必须完整回传 `reasoning_content`、`tool_calls` 与后续 `role: tool` 消息。

实现证据：
- `OpenChat/Core/Networking/APIProviderDialect.swift`：DeepSeek V4 方言推断、1,000,000 默认上下文、`ReasoningEffort.high/max`。
- `OpenChat/Core/Networking/APIRequest.swift`：DeepSeek V4 下编码 `thinking` / `reasoning_effort`，thinking enabled 时使用 `max_tokens` 并剥离无效采样参数。
- `OpenChat/Core/Networking/ChatMessage.swift`、`OpenChat/Core/Networking/APIRequest.swift`、`OpenChat/Core/Networking/ResponsesAPIRequest.swift`：`reasoning_content` 可解码，但普通请求历史默认经 `requestMessage()` 剥离。
- `OpenChat/Features/Chat/ViewModels/ChatViewModel+Support.swift`、`OpenChat/Features/Chat/Views/MessageBubbleView.swift`：流式 reasoning delta 累积到 `MessageRecord.reasoningContent` 并以“角色思考”展示。

### 6.3 Responses API

当前实现覆盖：

- 路由：`POST {baseURL}/responses`
- `model`
- `stream`
- `temperature`、`top_p`
- `maxTokens` 映射为 `max_output_tokens`
- system 消息合并为顶层 `instructions`
- 非 system 消息放入 `input`
- `store` 固定为 `false`
- `thinkingBudget` 映射为 `reasoning.max_tokens`
- 非流式响应从 `output[].content[]` 中聚合 `output_text`
- 流式响应处理以下 typed events：
  - `response.output_text.delta`
  - `response.reasoning.delta`（当前实现兼容的 reasoning 增量事件）
  - `response.completed`
- `response.failed`
- `response.incomplete`

Request-shape 约束：

- Chat Completions 模式保持原始 `messages` 序列；`[Memories]` 是 Current-Turn Context 中的 system block，位于当前 turn user message 前。
- Responses 模式会把所有 system message 按原序 join 到 `instructions`，因此 `[Memories]` 作为 `instructions` 内的一段出现，而不会作为单独的 `input` message。
- Responses 模式的 `input` 只包含非 system messages；当前 turn user message 只出现一次，且 `[Memories]` 不会被拼进 user content。
- 这种 folding 是 provider adapter 行为，不等同于 Memory 丢失；未来 Background block 的 request-shape 需要在 Background 独立计划中重新验收。

实现证据：
- `OpenChat/Core/Networking/ResponsesAPIRequest.swift`：system → `instructions` folding，非 system → `input`。
- `OpenChatTests/Core/NetworkingTests/ResponsesAPITests.swift`：`ResponsesAPIRequestTests.test_memory_block_folds_to_instructions_without_user_duplication`。
- `OpenChatTests/Features/ChatTests/ChatViewModelPromptAssemblyTests.swift`：Chat Completions 四层顺序与 Responses 模式 `[Memories]` folding 端到端 request 捕获。

当前未覆盖 Responses API 全量能力，例如 `previous_response_id` / `conversation`、`tools` / `tool_choice` / `parallel_tool_calls`、`include`、多模态 input、文件输入、structured output / `text.format`、background、truncation、全部 streaming event 类型等。

## 7. 错误处理策略

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

## 8. 取消支持

- `streamMessage()` 返回的 `AsyncThrowingStream` 天然支持 Swift Concurrency 取消
- 调用方持有 `Task` 引用，调用 `task.cancel()` 即可中断流式传输
- `URLSession` 底层在 Task 取消时自动中断网络请求

## 9. 线程安全

- `APIClient` 标记 `Sendable`，无可变状态
- `URLSession.shared` 本身线程安全
- 所有方法均为 `async`，通过 Swift Concurrency 保证安全

## 10. 对外依赖

| 模块 | 依赖内容 |
|---|---|
| `Core/Database` | `APIEndpointRecord`（用于 `APIEndpointConfig` 初始化） |
| 被依赖方 | `Features/Chat/ChatViewModel`、`Core/ContextManager/CompressionStrategy` |

## 实现证据（2026-04-29 核对）

- 代码位置：
  - `OpenChat/Core/Networking/APIClient.swift` — 根据 apiMode 分发到 Chat Completions / Responses 实现，并以 `endpoint.baseURL` 追加相对路径 `models`、`chat/completions`、`responses`
  - `OpenChat/Core/Networking/SSEStreamParser.swift` — 支持 `event:` 类型行
  - `OpenChat/Core/Networking/APIMode.swift` — API 模式枚举
  - `OpenChat/Core/Networking/APIProviderDialect.swift` — 供应商方言、DeepSeek V4 推断、默认上下文与 `ReasoningEffort`
  - `OpenChat/Core/Networking/APIRequest.swift` — Chat Completions 请求体（`max_tokens` / `max_completion_tokens`、DeepSeek V4 `thinking` / `reasoning_effort`、`stream_options.include_usage`）
  - `OpenChat/Core/Networking/APIResponse.swift` — Chat Completions 响应体与流式 `reasoning_content`
  - `OpenChat/Core/Networking/ChatMessage.swift` — 响应侧 `reasoning_content` 解码，请求侧默认剥离历史 reasoning 内容
  - `OpenChat/Core/Networking/ResponsesAPIRequest.swift` — Responses API 请求体（system → instructions 提取）
  - `OpenChat/Core/Networking/ResponsesAPIResponse.swift` — Responses API 响应体 + 转换
  - `OpenChat/Core/Networking/APIEndpointConfig.swift` — 含 `init(from:model:)` 从端点+模型记录构造，并携带 `providerDialect`
  - `OpenChat/Core/Networking/APIError.swift`
- 已验证测试（2026-04-29）：
  - `OpenChatTests/Core/NetworkingTests/APIClientTests.swift` — Chat Completions 模式测试
  - `OpenChatTests/Core/NetworkingTests/SSEStreamParserTests.swift` — SSE 解析测试
  - `OpenChatTests/Core/NetworkingTests/ResponsesAPITests.swift` — Responses API 请求/响应/流式/参数过滤测试
  - `OpenChatTests/Core/NetworkingTests/ThinkingFeatureTests.swift` — thinking/reasoning 请求参数、流式 reasoning delta、usage reasoning tokens 测试
  - `OpenChatTests/Core/NetworkingTests/DeepSeekV4RequestTests.swift` — DeepSeek V4 `thinking` / `reasoning_effort` 请求编码、非流式 reasoning 解码、请求历史不回传 reasoning 内容
  - `OpenChatTests/Core/NetworkingTests/ModelObjectTests.swift` — ModelObject 解码 + EndpointModelRecord 测试
- 验证命令：
  - `xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17'` — 全量 152 个 Swift Testing 测试通过（2026-04-29）
