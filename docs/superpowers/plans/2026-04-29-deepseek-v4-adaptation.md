# DeepSeek V4 Adaptation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 OpenChat 增加 DeepSeek V4 的独立适配，使 `deepseek-v4-flash` / `deepseek-v4-pro` 能正确调用 Chat Completions、显式控制思考模式，并保留角色扮演场景中的角色视角思考链。

**Architecture:** 保持现有 `APIMode` 只负责 API 路径分发：`chatCompletions` / `responses`。新增模型级 `APIProviderDialect` 负责供应商方言：默认 OpenAI-compatible，DeepSeek V4 使用独立请求编码规则。DeepSeek V4 仍走 `POST {baseURL}/chat/completions`，但请求体使用 `thinking` 与 `reasoning_effort`，并把 `reasoning_content` 作为角色回复的可保存、可展示输出处理。

**Tech Stack:** Swift 6, SwiftUI, Swift Concurrency, GRDB.swift, URLSession AsyncBytes, Swift Testing, Xcode iOS Simulator.

---

## 约束与依据

- DeepSeek 官方 OpenAI-format base URL 是 `https://api.deepseek.com`，Chat Completions 路径是 `/chat/completions`，模型名为 `deepseek-v4-flash` 和 `deepseek-v4-pro`；`deepseek-chat` / `deepseek-reasoner` 将在 2026-07-24 弃用。
- DeepSeek V4 思考模式通过 `thinking: {"type": "enabled" | "disabled"}` 控制，默认是 `enabled`；思考强度通过 `reasoning_effort: "high" | "max"` 控制。
- DeepSeek V4 思考模式返回 `reasoning_content`，非流式位于 `choices[].message.reasoning_content`，流式位于 `choices[].delta.reasoning_content`。
- DeepSeek V4 思考模式下 `temperature`、`top_p`、`presence_penalty`、`frequency_penalty` 不生效；适配层应在 thinking enabled 时不发送这些字段，避免 UI 表达和实际行为不一致。
- DeepSeek V4 的思考链在角色扮演中会受角色设定影响；OpenChat 应将其视为角色回复的一部分进行展示和持久化，但正常无工具调用的下一轮请求不主动回传历史 `reasoning_content`，保持当前角色对话上下文简洁。
- 当前 OpenChat 没有原生 Tool Calls 执行器。本计划不打开 `tools` 请求字段；仅把 DeepSeek 文档中的工具调用约束写进架构边界，防止未来加工具时丢失 `reasoning_content` 回传要求。

参考文档：
- DeepSeek 快速开始：https://api-docs.deepseek.com/zh-cn/
- DeepSeek 思考模式：https://api-docs.deepseek.com/zh-cn/guides/thinking_mode
- DeepSeek Chat Completions API：https://api-docs.deepseek.com/zh-cn/api/create-chat-completion
- DeepSeek 模型与价格：https://api-docs.deepseek.com/zh-cn/quick_start/pricing

## 文件结构

- Create: `OpenChat/Core/Networking/APIProviderDialect.swift`
  - 定义供应商方言枚举、显示文案、DeepSeek 模型识别、默认上下文窗口、DeepSeek thinking effort 映射。
- Modify: `OpenChat/Core/Database/Migrations.swift`
  - 追加 `v10_add_provider_dialect_to_endpoint_model`，给 `endpoint_model` 增加 `providerDialect`。
- Modify: `OpenChat/Core/Database/Records/EndpointModelRecord.swift`
  - 增加 `providerDialect` 字段与 `providerDialectValue` computed property。
- Modify: `OpenChat/Core/Networking/APIEndpointConfig.swift`
  - 将模型方言带入运行时请求配置。
- Modify: `OpenChat/Core/Database/DatabaseManager+EndpointModels.swift`
  - 拉取模型时按 baseURL + modelId 推断默认方言；DeepSeek V4 默认 1,000,000 context tokens。
- Modify: `OpenChat/Core/Networking/ModelParameters.swift`
  - 增加 DeepSeek V4 的思考强度 `reasoningEffort`，保留现有 `thinkingBudget` 作为 thinking 开关和非 DeepSeek 预算。
- Modify: `OpenChat/Core/Networking/APIRequest.swift`
  - DeepSeek V4 方言下编码 `thinking` / `reasoning_effort`，thinking enabled 时不发送无效采样参数，不发送 `max_completion_tokens`。
- Modify: `OpenChat/Core/Networking/ChatMessage.swift`
  - 允许解码响应中的 `reasoning_content`，但默认请求历史仍不携带。
- Modify: `OpenChat/Core/Networking/APIResponse.swift`
  - 确认非流式 `message.reasoning_content` 进入 `ChatMessage.reasoningContent`。
- Modify: `OpenChat/Features/Chat/ViewModels/ChatViewModel.swift`
  - 读取/保存 `reasoningEffort`；按选中模型方言决定聊天设置展示。
- Modify: `OpenChat/Features/Chat/Views/ChatSettingsSheet.swift`
  - DeepSeek V4 thinking enabled 时显示 `Reasoning Effort` picker；非 DeepSeek 保持 numeric budget。
- Modify: `OpenChat/Features/Chat/Views/MessageBubbleView.swift`
  - 把 reasoning 区域文案调整为角色思考，不把它描述成“系统推理”或“如何扮演角色”。
- Modify: `OpenChat/Features/Settings/ViewModels/APIEndpointEditorViewModel.swift`
  - 手动新增/编辑模型时支持 `providerDialect`；DeepSeek V4 自动设置 Chat Completions 和 1M context。
- Modify: `OpenChat/Features/Settings/Views/APIEndpointEditorView.swift`
  - Add/Edit model sheet 增加 Provider picker，并在模型列表展示方言。
- Modify: `OpenChat/Resources/Localizable.xcstrings`
  - 增加 Provider、DeepSeek V4、Reasoning Effort、High、Max、Character Thinking 等本地化。
- Modify: `arch/modules/api-client.md`
  - 记录 DeepSeek V4 方言、thinking 调用规则、reasoning_content 处理边界。
- Modify: `arch/data-model.md`
  - 记录 `endpoint_model.providerDialect` 字段和迁移。
- Test: `OpenChatTests/Core/NetworkingTests/DeepSeekV4RequestTests.swift`
  - 新增 DeepSeek V4 请求编码、非流式 reasoning 解码、流式 reasoning 行为测试。
- Test: `OpenChatTests/Core/DatabaseTests/MigrationTests.swift`
  - 覆盖 `providerDialect` migration。
- Test: `OpenChatTests/Core/DatabaseTests/EndpointModelTests.swift`
  - 覆盖 DeepSeek V4 模型导入、手动编辑、默认 context 和方言持久化。
- Test: `OpenChatTests/Core/TestHelpers.swift`
  - 给 `makeEndpoint` 增加 `providerDialect` 参数，默认 `.openAICompatible`。

## Task 1: Provider Dialect 与持久化字段

**Files:**
- Create: `OpenChat/Core/Networking/APIProviderDialect.swift`
- Modify: `OpenChat/Core/Database/Migrations.swift`
- Modify: `OpenChat/Core/Database/Records/EndpointModelRecord.swift`
- Modify: `OpenChat/Core/Networking/APIEndpointConfig.swift`
- Modify: `OpenChatTests/Core/DatabaseTests/MigrationTests.swift`
- Modify: `OpenChatTests/Core/TestHelpers.swift`

- [ ] **Step 1: 写 migration 与 record 的失败测试**

在 `OpenChatTests/Core/DatabaseTests/MigrationTests.swift` 的 v9 测试后追加：

```swift
// MARK: - v10 provider dialect

@Test func test_v10_endpoint_model_has_providerDialect_column() async throws {
    let manager = try TestHelpers.makeDatabaseManager()
    let columns = try await manager.read { db in
        try db.columns(in: "endpoint_model").map(\.name)
    }

    #expect(columns.contains("providerDialect"))
}

@Test func test_v10_providerDialect_defaults_to_openAICompatible() async throws {
    let manager = try TestHelpers.makeDatabaseManager()
    let now = Date()
    let endpoint = APIEndpointRecord(
        id: "ep-provider-default",
        name: "Local",
        baseURL: "http://localhost:8080/v1",
        apiKey: nil,
        isDefault: true,
        createdAt: now,
        updatedAt: now
    )
    try await manager.saveEndpoint(endpoint)
    try await manager.ensureDefaultModel(endpointId: endpoint.id)

    let model = try await manager.fetchDefaultModel(endpointId: endpoint.id)
    #expect(model?.providerDialect == "openAICompatible")
}

@Test func test_v10_backfills_existing_deepseek_v4_models() throws {
    let dbQueue = try DatabaseQueue()
    var migrator = Migrations.makeMigrator()
    try migrator.migrate(dbQueue, upTo: "v9_add_is_title_generated")

    try dbQueue.write { db in
        try db.execute(sql: """
            INSERT INTO api_endpoint (id, name, baseURL, apiKey, isDefault, createdAt, updatedAt)
            VALUES ('ep-deepseek', 'DeepSeek', 'https://api.deepseek.com', NULL, 1, ?, ?)
            """, arguments: [Date(), Date()])
        try db.execute(sql: """
            INSERT INTO endpoint_model (id, endpointId, modelId, maxContextTokens, apiMode, isDefault, isManual, createdAt)
            VALUES ('model-deepseek-pro', 'ep-deepseek', 'deepseek-v4-pro', 4096, 'chatCompletions', 1, 1, ?)
            """, arguments: [Date()])
    }

    try migrator.migrate(dbQueue)

    let row = try dbQueue.read { db in
        try Row.fetchOne(db, sql: """
            SELECT providerDialect, maxContextTokens
            FROM endpoint_model
            WHERE id = 'model-deepseek-pro'
            """)
    }

    #expect(row?["providerDialect"] as String? == "deepSeekV4")
    #expect(row?["maxContextTokens"] as Int? == 1_000_000)
}
```

在 `OpenChatTests/Core/TestHelpers.swift` 修改 helper 签名：

```swift
static func makeEndpoint(
    baseURL: String = "http://localhost:8080/v1",
    apiKey: String? = "test-key",
    modelName: String = "gpt-4o-mini",
    maxContextTokens: Int = 4096,
    apiMode: APIMode = .chatCompletions,
    providerDialect: APIProviderDialect = .openAICompatible
) -> APIEndpointConfig {
    APIEndpointConfig(
        baseURL: URL(string: baseURL)!,
        apiKey: apiKey,
        modelName: modelName,
        maxContextTokens: maxContextTokens,
        apiMode: apiMode,
        providerDialect: providerDialect
    )
}
```

- [ ] **Step 2: 运行失败测试**

Run:

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:OpenChatTests/MigrationTests/test_v10_endpoint_model_has_providerDialect_column -only-testing:OpenChatTests/MigrationTests/test_v10_providerDialect_defaults_to_openAICompatible -only-testing:OpenChatTests/MigrationTests/test_v10_backfills_existing_deepseek_v4_models
```

Expected: FAIL，错误包含 `Value of type 'EndpointModelRecord' has no member 'providerDialect'` 或 migration column 缺失。

- [ ] **Step 3: 创建 provider dialect 类型**

Create `OpenChat/Core/Networking/APIProviderDialect.swift`:

```swift
import Foundation

enum APIProviderDialect: String, Codable, Sendable, CaseIterable, Identifiable {
    case openAICompatible
    case deepSeekV4

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAICompatible:
            String(localized: "OpenAI Compatible")
        case .deepSeekV4:
            String(localized: "DeepSeek V4")
        }
    }

    static func inferred(baseURL: URL, modelId: String) -> APIProviderDialect {
        let host = baseURL.host?.lowercased() ?? ""
        let normalizedModel = modelId.lowercased()
        if normalizedModel == "deepseek-v4-flash" || normalizedModel == "deepseek-v4-pro" {
            return .deepSeekV4
        }
        if host.contains("deepseek.com"), normalizedModel.hasPrefix("deepseek-v4-") {
            return .deepSeekV4
        }
        return .openAICompatible
    }

    static func defaultContextTokens(baseURL: URL, modelId: String, reportedContextLength: Int?) -> Int {
        if let reportedContextLength {
            return reportedContextLength
        }
        return inferred(baseURL: baseURL, modelId: modelId) == .deepSeekV4 ? 1_000_000 : 4096
    }
}

enum ReasoningEffort: String, Codable, Sendable, CaseIterable, Identifiable {
    case high
    case max

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .high:
            String(localized: "High")
        case .max:
            String(localized: "Max")
        }
    }
}
```

- [ ] **Step 4: 添加 v10 migration**

Modify `OpenChat/Core/Database/Migrations.swift`:

```swift
private enum Historical {
    static let apiEndpointTable = "api_endpoint"
    static let characterCardTable = "character_card"
    static let worldBookTable = "world_book"
    static let worldBookEntryTable = "world_book_entry"
    static let conversationTable = "conversation"
    static let messageTable = "message"
    static let memoryEntryTable = "memory_entry"
    static let memoryEmbeddingTable = "memory_embedding"
    static let endpointModelTable = "endpoint_model"

    static let apiModeChatCompletions = "chatCompletions"
    static let providerDialectOpenAICompatible = "openAICompatible"
    static let providerDialectDeepSeekV4 = "deepSeekV4"
    static let worldBookEntryBeforeHistory = "before_history"
    static let contextStrategyTruncation = "truncation"
}
```

在 `v9_add_is_title_generated` 后追加：

```swift
migrator.registerMigration("v10_add_provider_dialect_to_endpoint_model") { db in
    try db.alter(table: Historical.endpointModelTable) { t in
        t.add(column: "providerDialect", .text)
            .notNull()
            .defaults(to: Historical.providerDialectOpenAICompatible)
    }
    try db.execute(sql: """
        UPDATE endpoint_model
        SET providerDialect = ?, maxContextTokens = CASE
            WHEN maxContextTokens = 4096 THEN 1000000
            ELSE maxContextTokens
        END
        WHERE lower(modelId) IN ('deepseek-v4-flash', 'deepseek-v4-pro')
           OR lower(modelId) LIKE 'deepseek-v4-%'
        """, arguments: [Historical.providerDialectDeepSeekV4])
}
```

- [ ] **Step 5: 更新 EndpointModelRecord 与 APIEndpointConfig**

Modify `OpenChat/Core/Database/Records/EndpointModelRecord.swift`:

```swift
struct EndpointModelRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    static let databaseTableName = "endpoint_model"

    var id: String
    var endpointId: String
    var modelId: String
    var maxContextTokens: Int
    var apiMode: String
    var providerDialect: String
    var isDefault: Bool
    var isManual: Bool
    var createdAt: Date

    var apiModeValue: APIMode {
        get { APIMode(rawValue: apiMode) ?? .chatCompletions }
        set { apiMode = newValue.rawValue }
    }

    var providerDialectValue: APIProviderDialect {
        get { APIProviderDialect(rawValue: providerDialect) ?? .openAICompatible }
        set { providerDialect = newValue.rawValue }
    }

    static let endpoint = belongsTo(APIEndpointRecord.self)
}
```

Modify `OpenChat/Core/Networking/APIEndpointConfig.swift`:

```swift
struct APIEndpointConfig: Equatable, Sendable {
    let baseURL: URL
    let apiKey: String?
    let modelName: String
    let maxContextTokens: Int
    let apiMode: APIMode
    let providerDialect: APIProviderDialect

    init(
        baseURL: URL,
        apiKey: String?,
        modelName: String,
        maxContextTokens: Int,
        apiMode: APIMode = .chatCompletions,
        providerDialect: APIProviderDialect = .openAICompatible
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.modelName = modelName
        self.maxContextTokens = maxContextTokens
        self.apiMode = apiMode
        self.providerDialect = providerDialect
    }

    init(from endpoint: APIEndpointRecord, model: EndpointModelRecord) throws {
        guard let baseURL = URL(string: endpoint.baseURL) else {
            throw APIError.invalidURL(endpoint.baseURL)
        }
        self.init(
            baseURL: baseURL,
            apiKey: endpoint.apiKey,
            modelName: model.modelId,
            maxContextTokens: model.maxContextTokens,
            apiMode: model.apiModeValue,
            providerDialect: model.providerDialectValue
        )
    }
}
```

- [ ] **Step 6: 更新所有 EndpointModelRecord 构造点**

所有 `EndpointModelRecord(...)` 构造都增加：

```swift
providerDialect: APIProviderDialect.openAICompatible.rawValue,
```

DeepSeek V4 相关测试或默认模型使用：

```swift
providerDialect: APIProviderDialect.deepSeekV4.rawValue,
```

必须更新这些路径：
- `OpenChat/Core/Database/Migrations.swift`
- `OpenChat/Core/Database/DatabaseManager+EndpointModels.swift`
- `OpenChat/Features/Chat/ViewModels/ChatViewModel+Support.swift`
- `OpenChat/Features/Settings/ViewModels/APIEndpointEditorViewModel.swift`
- `OpenChat/Core/Memory/MemoryManager.swift`
- `OpenChatTests/Core/DatabaseTests/EndpointModelTests.swift`
- `OpenChatTests/Core/DatabaseTests/MigrationTests.swift`
- `OpenChatTests/Core/NetworkingTests/ModelObjectTests.swift`
- `OpenChatTests/Features/ChatTests/ChatViewModelPromptAssemblyTests.swift`

- [ ] **Step 7: 运行测试确认通过**

Run:

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:OpenChatTests/MigrationTests/test_v10_endpoint_model_has_providerDialect_column -only-testing:OpenChatTests/MigrationTests/test_v10_providerDialect_defaults_to_openAICompatible -only-testing:OpenChatTests/MigrationTests/test_v10_backfills_existing_deepseek_v4_models
```

Expected: PASS。

- [ ] **Step 8: Commit**

```bash
git add OpenChat/Core/Networking/APIProviderDialect.swift OpenChat/Core/Database/Migrations.swift OpenChat/Core/Database/Records/EndpointModelRecord.swift OpenChat/Core/Networking/APIEndpointConfig.swift OpenChat/Core/Database/DatabaseManager+EndpointModels.swift OpenChat/Features/Chat/ViewModels/ChatViewModel+Support.swift OpenChat/Features/Settings/ViewModels/APIEndpointEditorViewModel.swift OpenChat/Core/Memory/MemoryManager.swift OpenChatTests/Core/DatabaseTests/MigrationTests.swift OpenChatTests/Core/TestHelpers.swift OpenChatTests/Core/DatabaseTests/EndpointModelTests.swift OpenChatTests/Core/NetworkingTests/ModelObjectTests.swift OpenChatTests/Features/ChatTests/ChatViewModelPromptAssemblyTests.swift
git commit -m "feat: add provider dialect for endpoint models"
```

## Task 2: DeepSeek V4 Chat Completions 请求编码

**Files:**
- Modify: `OpenChat/Core/Networking/ModelParameters.swift`
- Modify: `OpenChat/Core/Networking/APIRequest.swift`
- Test: `OpenChatTests/Core/NetworkingTests/DeepSeekV4RequestTests.swift`

- [ ] **Step 1: 写 DeepSeek V4 请求体失败测试**

Create `OpenChatTests/Core/NetworkingTests/DeepSeekV4RequestTests.swift`:

```swift
import Foundation
import Testing

@testable import OpenChat

@Suite("DeepSeek V4 request encoding")
struct DeepSeekV4RequestTests {
    @Test func test_deepseek_v4_thinking_enabled_uses_thinking_and_reasoning_effort() throws {
        let endpoint = TestHelpers.makeEndpoint(
            baseURL: "https://api.deepseek.com",
            modelName: "deepseek-v4-pro",
            maxContextTokens: 1_000_000,
            providerDialect: .deepSeekV4
        )
        let params = ModelParameters(
            temperature: 0.2,
            topP: 0.5,
            maxTokens: 2048,
            frequencyPenalty: 0.4,
            presencePenalty: 0.7,
            thinkingBudget: 8192,
            reasoningEffort: .max
        )

        let request = APIRequest(messages: [.init(role: "user", content: "Hi")], endpoint: endpoint, parameters: params, stream: false)
        let data = try JSONEncoder().encode(request)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["model"] as? String == "deepseek-v4-pro")
        let thinking = try #require(json["thinking"] as? [String: Any])
        #expect(thinking["type"] as? String == "enabled")
        #expect(json["reasoning_effort"] as? String == "max")
        #expect(json["max_tokens"] as? Int == 2048)
        #expect(json["max_completion_tokens"] == nil)
        #expect(json["temperature"] == nil)
        #expect(json["top_p"] == nil)
        #expect(json["frequency_penalty"] == nil)
        #expect(json["presence_penalty"] == nil)
    }

    @Test func test_deepseek_v4_thinking_disabled_is_explicit() throws {
        let endpoint = TestHelpers.makeEndpoint(
            baseURL: "https://api.deepseek.com",
            modelName: "deepseek-v4-flash",
            maxContextTokens: 1_000_000,
            providerDialect: .deepSeekV4
        )
        let params = ModelParameters(
            temperature: 0.7,
            topP: 0.9,
            maxTokens: 1024,
            thinkingBudget: nil,
            reasoningEffort: .high
        )

        let request = APIRequest(messages: [.init(role: "user", content: "Hi")], endpoint: endpoint, parameters: params, stream: false)
        let data = try JSONEncoder().encode(request)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        let thinking = try #require(json["thinking"] as? [String: Any])
        #expect(thinking["type"] as? String == "disabled")
        #expect(json["reasoning_effort"] == nil)
        #expect(json["max_tokens"] as? Int == 1024)
        #expect(json["max_completion_tokens"] == nil)
        #expect(json["temperature"] as? Double == 0.7)
        #expect(json["top_p"] as? Double == 0.9)
    }

    @Test func test_openai_compatible_thinking_keeps_existing_max_completion_tokens_behavior() throws {
        let endpoint = TestHelpers.makeEndpoint(
            modelName: "gpt-4o-mini",
            providerDialect: .openAICompatible
        )
        let params = ModelParameters(maxTokens: 2048, thinkingBudget: 4096, reasoningEffort: .max)

        let request = APIRequest(messages: [], endpoint: endpoint, parameters: params, stream: false)
        let data = try JSONEncoder().encode(request)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["thinking"] == nil)
        #expect(json["reasoning_effort"] == nil)
        #expect(json["max_completion_tokens"] as? Int == 6144)
        #expect(json["max_tokens"] == nil)
    }
}
```

- [ ] **Step 2: 运行失败测试**

Run:

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:OpenChatTests/DeepSeekV4RequestTests
```

Expected: FAIL，错误包含 `Extra argument 'reasoningEffort' in call` 或 `json["thinking"] == nil`。

- [ ] **Step 3: 扩展 ModelParameters**

Modify `OpenChat/Core/Networking/ModelParameters.swift`:

```swift
struct ModelParameters: Codable, Equatable, Sendable {
    var temperature: Double
    var topP: Double
    var maxTokens: Int?
    var frequencyPenalty: Double
    var presencePenalty: Double
    var stop: [String]?
    var thinkingBudget: Int?
    var reasoningEffort: ReasoningEffort

    init(
        temperature: Double = 0.8,
        topP: Double = 1.0,
        maxTokens: Int? = nil,
        frequencyPenalty: Double = 0.0,
        presencePenalty: Double = 0.0,
        stop: [String]? = nil,
        thinkingBudget: Int? = nil,
        reasoningEffort: ReasoningEffort = .high
    ) {
        self.temperature = temperature
        self.topP = topP
        self.maxTokens = maxTokens
        self.frequencyPenalty = frequencyPenalty
        self.presencePenalty = presencePenalty
        self.stop = stop
        self.thinkingBudget = thinkingBudget
        self.reasoningEffort = reasoningEffort
    }

    var isThinkingEnabled: Bool { thinkingBudget != nil }

    func forAPIMode(_ mode: APIMode) -> ModelParameters {
        switch mode {
        case .chatCompletions:
            return self
        case .responses:
            return ModelParameters(
                temperature: temperature,
                topP: topP,
                maxTokens: maxTokens,
                frequencyPenalty: 0.0,
                presencePenalty: 0.0,
                stop: nil,
                thinkingBudget: thinkingBudget,
                reasoningEffort: reasoningEffort
            )
        }
    }
}
```

- [ ] **Step 4: 扩展 APIRequest DeepSeek 编码**

Modify `OpenChat/Core/Networking/APIRequest.swift`:

```swift
struct APIRequest: Codable, Sendable {
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

    let thinkingEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case model, messages, stream, temperature, stop, thinking
        case streamOptions = "stream_options"
        case topP = "top_p"
        case maxTokens = "max_tokens"
        case maxCompletionTokens = "max_completion_tokens"
        case frequencyPenalty = "frequency_penalty"
        case presencePenalty = "presence_penalty"
        case reasoningEffort = "reasoning_effort"
    }

    init(messages: [ChatMessage], endpoint: APIEndpointConfig, parameters: ModelParameters, stream: Bool) {
        model = endpoint.modelName
        self.messages = messages
        self.stream = stream
        streamOptions = stream ? StreamOptions(includeUsage: true) : nil
        stop = parameters.stop
        thinkingEnabled = parameters.isThinkingEnabled

        switch endpoint.providerDialect {
        case .deepSeekV4:
            thinking = DeepSeekThinkingConfig(type: parameters.isThinkingEnabled ? "enabled" : "disabled")
            reasoningEffort = parameters.isThinkingEnabled ? parameters.reasoningEffort.rawValue : nil
            maxTokens = parameters.maxTokens
            maxCompletionTokens = nil
            if parameters.isThinkingEnabled {
                temperature = nil
                topP = nil
                frequencyPenalty = nil
                presencePenalty = nil
            } else {
                temperature = parameters.temperature
                topP = parameters.topP
                frequencyPenalty = parameters.frequencyPenalty
                presencePenalty = parameters.presencePenalty
            }
        case .openAICompatible:
            thinking = nil
            reasoningEffort = nil
            topP = parameters.topP
            frequencyPenalty = parameters.frequencyPenalty
            presencePenalty = parameters.presencePenalty

            if parameters.isThinkingEnabled {
                temperature = 1.0
                maxTokens = nil
                maxCompletionTokens = parameters.maxTokens.map { $0 + (parameters.thinkingBudget ?? 0) }
                    ?? parameters.thinkingBudget
            } else {
                temperature = parameters.temperature
                maxTokens = parameters.maxTokens
                maxCompletionTokens = nil
            }
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        model = try container.decode(String.self, forKey: .model)
        messages = try container.decode([ChatMessage].self, forKey: .messages)
        stream = try container.decode(Bool.self, forKey: .stream)
        streamOptions = try container.decodeIfPresent(StreamOptions.self, forKey: .streamOptions)
        temperature = try container.decodeIfPresent(Double.self, forKey: .temperature)
        topP = try container.decodeIfPresent(Double.self, forKey: .topP)
        maxTokens = try container.decodeIfPresent(Int.self, forKey: .maxTokens)
        maxCompletionTokens = try container.decodeIfPresent(Int.self, forKey: .maxCompletionTokens)
        frequencyPenalty = try container.decodeIfPresent(Double.self, forKey: .frequencyPenalty)
        presencePenalty = try container.decodeIfPresent(Double.self, forKey: .presencePenalty)
        stop = try container.decodeIfPresent([String].self, forKey: .stop)
        thinking = try container.decodeIfPresent(DeepSeekThinkingConfig.self, forKey: .thinking)
        reasoningEffort = try container.decodeIfPresent(String.self, forKey: .reasoningEffort)
        thinkingEnabled = maxCompletionTokens != nil || thinking?.type == "enabled"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(messages, forKey: .messages)
        try container.encode(stream, forKey: .stream)
        try container.encodeIfPresent(streamOptions, forKey: .streamOptions)
        try container.encodeIfPresent(temperature, forKey: .temperature)
        try container.encodeIfPresent(topP, forKey: .topP)
        try container.encodeIfPresent(frequencyPenalty, forKey: .frequencyPenalty)
        try container.encodeIfPresent(presencePenalty, forKey: .presencePenalty)
        try container.encodeIfPresent(stop, forKey: .stop)
        try container.encodeIfPresent(thinking, forKey: .thinking)
        try container.encodeIfPresent(reasoningEffort, forKey: .reasoningEffort)

        if thinking != nil {
            try container.encodeIfPresent(maxTokens, forKey: .maxTokens)
        } else if thinkingEnabled {
            try container.encodeIfPresent(maxCompletionTokens, forKey: .maxCompletionTokens)
        } else {
            try container.encodeIfPresent(maxTokens, forKey: .maxTokens)
        }
    }
}

struct DeepSeekThinkingConfig: Codable, Sendable, Equatable {
    let type: String
}
```

- [ ] **Step 5: 运行 DeepSeek 请求测试**

Run:

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:OpenChatTests/DeepSeekV4RequestTests
```

Expected: PASS。

- [ ] **Step 6: 运行现有 thinking 测试防回归**

Run:

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:OpenChatTests/APIRequestThinkingTests -only-testing:OpenChatTests/ModelParametersThinkingTests
```

Expected: PASS。

- [ ] **Step 7: Commit**

```bash
git add OpenChat/Core/Networking/ModelParameters.swift OpenChat/Core/Networking/APIRequest.swift OpenChatTests/Core/NetworkingTests/DeepSeekV4RequestTests.swift
git commit -m "feat: encode deepseek v4 thinking requests"
```

## Task 3: Reasoning Content 的非流式解析与角色思考保留

**Files:**
- Modify: `OpenChat/Core/Networking/ChatMessage.swift`
- Modify: `OpenChat/Core/Networking/APIResponse.swift`
- Modify: `OpenChat/Features/Chat/Views/MessageBubbleView.swift`
- Test: `OpenChatTests/Core/NetworkingTests/DeepSeekV4RequestTests.swift`

- [ ] **Step 1: 写非流式 reasoning 解码失败测试**

Append to `DeepSeekV4RequestTests`:

```swift
@Suite("DeepSeek V4 reasoning content")
struct DeepSeekV4ReasoningContentTests {
    @Test func test_non_streaming_response_decodes_reasoning_content() throws {
        let json = """
        {
          "id": "chatcmpl-deepseek",
          "choices": [
            {
              "index": 0,
              "message": {
                "role": "assistant",
                "reasoning_content": "I should answer from the character's point of view.",
                "content": "I remember the old gate clearly."
              },
              "finish_reason": "stop"
            }
          ],
          "usage": {
            "prompt_tokens": 10,
            "completion_tokens": 20,
            "total_tokens": 30,
            "completion_tokens_details": {
              "reasoning_tokens": 8
            }
          }
        }
        """

        let response = try JSONDecoder().decode(ChatCompletionResponse.self, from: Data(json.utf8))

        #expect(response.choices[0].message.reasoningContent == "I should answer from the character's point of view.")
        #expect(response.choices[0].message.content == "I remember the old gate clearly.")
        #expect(response.usage?.completionTokensDetails?.reasoningTokens == 8)
    }

    @Test func test_request_message_omits_reasoning_content_by_default() throws {
        let message = ChatMessage(
            role: "assistant",
            content: "Visible character reply.",
            reasoningContent: "Private role-perspective thinking."
        )

        let data = try JSONEncoder().encode(message.requestMessage())
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["role"] as? String == "assistant")
        #expect(json["content"] as? String == "Visible character reply.")
        #expect(json["reasoning_content"] == nil)
    }
}
```

- [ ] **Step 2: 运行失败测试**

Run:

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:OpenChatTests/DeepSeekV4ReasoningContentTests
```

Expected: FAIL，错误包含 `Value of type 'ChatMessage' has no member 'reasoningContent'`。

- [ ] **Step 3: 扩展 ChatMessage**

Modify `OpenChat/Core/Networking/ChatMessage.swift`:

```swift
import Foundation

struct ChatMessage: Codable, Equatable, Sendable {
    var role: String
    var content: String
    var reasoningContent: String?

    init(role: String, content: String, reasoningContent: String? = nil) {
        self.role = role
        self.content = content
        self.reasoningContent = reasoningContent
    }

    enum CodingKeys: String, CodingKey {
        case role, content
        case reasoningContent = "reasoning_content"
    }

    func requestMessage(includeReasoningContent: Bool = false) -> ChatMessage {
        guard includeReasoningContent else {
            return ChatMessage(role: role, content: content)
        }
        return self
    }
}
```

Modify `OpenChat/Core/Database/Records/MessageRecord.swift` so normal history does not include reasoning content:

```swift
var chatMessage: ChatMessage {
    ChatMessage(role: role, content: content)
}
```

This property already has this shape; keep it unchanged after adding `ChatMessage.reasoningContent`.

Modify `OpenChat/Core/Networking/APIRequest.swift` in its initializer so request payloads do not accidentally include saved role-thinking content:

```swift
self.messages = messages.map { $0.requestMessage() }
```

- [ ] **Step 4: 调整角色思考展示文案**

Modify `OpenChat/Features/Chat/Views/MessageBubbleView.swift`:

```swift
Label {
    Text(String(localized: "Character Thinking"))
    if isStreaming && item.content.isEmpty {
        ProgressView()
            .controlSize(.mini)
            .padding(.leading, 4)
    }
} icon: {
    Image(systemName: "brain")
}
```

And for the streaming placeholder:

```swift
Text(String(localized: "Character thinking…"))
```

- [ ] **Step 5: 运行 reasoning 测试**

Run:

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:OpenChatTests/DeepSeekV4ReasoningContentTests -only-testing:OpenChatTests/ChunkReasoningTests -only-testing:OpenChatTests/StreamingReasoningIntegrationTests
```

Expected: PASS。

- [ ] **Step 6: Commit**

```bash
git add OpenChat/Core/Networking/ChatMessage.swift OpenChat/Core/Networking/APIResponse.swift OpenChat/Features/Chat/Views/MessageBubbleView.swift OpenChatTests/Core/NetworkingTests/DeepSeekV4RequestTests.swift
git commit -m "feat: preserve deepseek reasoning content"
```

## Task 4: DeepSeek V4 模型导入、默认值与设置 UI

**Files:**
- Modify: `OpenChat/Core/Database/DatabaseManager+EndpointModels.swift`
- Modify: `OpenChat/Features/Settings/ViewModels/APIEndpointEditorViewModel.swift`
- Modify: `OpenChat/Features/Settings/Views/APIEndpointEditorView.swift`
- Modify: `OpenChatTests/Core/DatabaseTests/EndpointModelTests.swift`
- Modify: `OpenChat/Resources/Localizable.xcstrings`

- [ ] **Step 1: 写模型导入和编辑失败测试**

Append the first test to the `DatabaseManager+EndpointModels` suite in `OpenChatTests/Core/DatabaseTests/EndpointModelTests.swift`, and append the second test to the `APIEndpointEditorViewModelTests` suite in the same file:

```swift
@Test func test_upsert_deepseek_v4_models_sets_provider_and_context() async throws {
    let manager = try TestHelpers.makeDatabaseManager()
    let now = Date()
    let endpoint = APIEndpointRecord(
        id: UUID().uuidString,
        name: "DeepSeek",
        baseURL: "https://api.deepseek.com",
        apiKey: nil,
        isDefault: true,
        createdAt: now,
        updatedAt: now
    )
    try await manager.saveEndpoint(endpoint)

    try await manager.upsertFetchedModels(
        endpointId: endpoint.id,
        models: [
            ModelObject(id: "deepseek-v4-pro", object: "model", ownedBy: "deepseek", contextLength: nil),
            ModelObject(id: "deepseek-v4-flash", object: "model", ownedBy: "deepseek", contextLength: nil),
        ]
    )

    let pro = try await manager.fetchEndpointModel(endpointId: endpoint.id, modelId: "deepseek-v4-pro")
    let flash = try await manager.fetchEndpointModel(endpointId: endpoint.id, modelId: "deepseek-v4-flash")

    #expect(pro?.providerDialectValue == .deepSeekV4)
    #expect(pro?.apiModeValue == .chatCompletions)
    #expect(pro?.maxContextTokens == 1_000_000)
    #expect(flash?.providerDialectValue == .deepSeekV4)
    #expect(flash?.maxContextTokens == 1_000_000)
}

@MainActor
@Test func test_save_edited_model_updates_provider_dialect() async throws {
    let (manager, endpoint, model) = try await makeEndpointAndModel()
    let viewModel = APIEndpointEditorViewModel(
        databaseManager: manager,
        apiClient: APIClient(),
        editingEndpoint: endpoint
    )

    viewModel.beginEditingModel(model)
    viewModel.editModelProviderDialect = .deepSeekV4
    viewModel.editModelApiMode = .chatCompletions
    viewModel.editModelMaxContext = 1_000_000

    await viewModel.saveEditedModel()

    let updated = try await manager.fetchEndpointModel(endpointId: endpoint.id, modelId: model.modelId)
    #expect(updated?.providerDialectValue == .deepSeekV4)
    #expect(updated?.apiModeValue == .chatCompletions)
    #expect(updated?.maxContextTokens == 1_000_000)
    #expect(updated?.isManual == true)
}
```

- [ ] **Step 2: 运行失败测试**

Run:

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:OpenChatTests/DatabaseManager+EndpointModels/test_upsert_deepseek_v4_models_sets_provider_and_context -only-testing:OpenChatTests/APIEndpointEditorViewModel/test_save_edited_model_updates_provider_dialect
```

Expected: FAIL，DeepSeek 模型仍是 `.openAICompatible` 或 ViewModel 缺少 `editModelProviderDialect`。

- [ ] **Step 3: 修改模型导入默认值**

Modify `OpenChat/Core/Database/DatabaseManager+EndpointModels.swift`:

```swift
func upsertFetchedModels(endpointId: String, models: [ModelObject]) async throws {
    try await write { db in
        guard let endpoint = try APIEndpointRecord.fetchOne(db, key: endpointId),
              let endpointBaseURL = URL(string: endpoint.baseURL) else {
            return
        }
        let existing = try EndpointModelRecord
            .filter(Column("endpointId") == endpointId)
            .fetchAll(db)
        let existingIds = Set(existing.map(\.modelId))
        let fetchedIds = Set(models.map(\.id))

        for record in existing where !record.isManual && !fetchedIds.contains(record.modelId) {
            _ = try EndpointModelRecord.deleteOne(db, key: record.id)
        }

        let hasDefault = existing.contains(where: { $0.isDefault && (fetchedIds.contains($0.modelId) || $0.isManual) })
        var isFirst = !hasDefault

        for model in models where !existingIds.contains(model.id) {
            let providerDialect = APIProviderDialect.inferred(baseURL: endpointBaseURL, modelId: model.id)
            let record = EndpointModelRecord(
                id: UUID().uuidString,
                endpointId: endpointId,
                modelId: model.id,
                maxContextTokens: APIProviderDialect.defaultContextTokens(
                    baseURL: endpointBaseURL,
                    modelId: model.id,
                    reportedContextLength: model.contextLength
                ),
                apiMode: APIMode.chatCompletions.rawValue,
                providerDialect: providerDialect.rawValue,
                isDefault: isFirst,
                isManual: false,
                createdAt: Date()
            )
            try record.insert(db)
            if isFirst { isFirst = false }
        }

        for model in models {
            if var existing = try EndpointModelRecord
                .filter(Column("endpointId") == endpointId && Column("modelId") == model.id)
                .fetchOne(db),
               !existing.isManual {
                existing.maxContextTokens = APIProviderDialect.defaultContextTokens(
                    baseURL: endpointBaseURL,
                    modelId: model.id,
                    reportedContextLength: model.contextLength
                )
                existing.providerDialectValue = APIProviderDialect.inferred(baseURL: endpointBaseURL, modelId: model.id)
                if existing.providerDialectValue == .deepSeekV4 {
                    existing.apiModeValue = .chatCompletions
                }
                try existing.update(db)
            }
        }
    }
}
```

- [ ] **Step 4: 扩展 Settings ViewModel 状态**

Modify `OpenChat/Features/Settings/ViewModels/APIEndpointEditorViewModel.swift`:

```swift
var newModelProviderDialect: APIProviderDialect = .openAICompatible
var editModelProviderDialect: APIProviderDialect = .openAICompatible
```

In `addManualModel()` before record creation:

```swift
let resolvedApiMode: APIMode = newModelProviderDialect == .deepSeekV4 ? .chatCompletions : newModelApiMode
let resolvedContext = newModelProviderDialect == .deepSeekV4 && newModelMaxContext == AppConstants.defaultMaxContextTokens
    ? 1_000_000
    : newModelMaxContext
```

Then create:

```swift
let record = EndpointModelRecord(
    id: UUID().uuidString,
    endpointId: endpointId,
    modelId: newModelId.trimmingCharacters(in: .whitespacesAndNewlines),
    maxContextTokens: resolvedContext,
    apiMode: resolvedApiMode.rawValue,
    providerDialect: newModelProviderDialect.rawValue,
    isDefault: models.isEmpty,
    isManual: true,
    createdAt: Date()
)
```

In `beginEditingModel(_:)`:

```swift
editModelProviderDialect = model.providerDialectValue
```

In `saveEditedModel()`:

```swift
model.providerDialectValue = editModelProviderDialect
if editModelProviderDialect == .deepSeekV4 {
    model.apiModeValue = .chatCompletions
    model.maxContextTokens = max(editModelMaxContext, 1_000_000)
} else {
    model.apiModeValue = editModelApiMode
    model.maxContextTokens = editModelMaxContext
}
model.isManual = true
```

In reset methods:

```swift
newModelProviderDialect = .openAICompatible
editModelProviderDialect = .openAICompatible
```

- [ ] **Step 5: 更新 Settings View**

Modify `OpenChat/Features/Settings/Views/APIEndpointEditorView.swift` add provider pickers in both add and edit sheets before API Mode picker:

```swift
Picker(String(localized: "Provider"), selection: bind(\.newModelProviderDialect)) {
    ForEach(APIProviderDialect.allCases) { dialect in
        Text(dialect.displayName).tag(dialect)
    }
}

Picker(String(localized: "API Mode"), selection: bind(\.newModelApiMode)) {
    Text("Chat Completions").tag(APIMode.chatCompletions)
    Text("Responses").tag(APIMode.responses)
}
.disabled(viewModel.newModelProviderDialect == .deepSeekV4)
```

Edit sheet variant:

```swift
Picker(String(localized: "Provider"), selection: bind(\.editModelProviderDialect)) {
    ForEach(APIProviderDialect.allCases) { dialect in
        Text(dialect.displayName).tag(dialect)
    }
}

Picker(String(localized: "API Mode"), selection: bind(\.editModelApiMode)) {
    Text("Chat Completions").tag(APIMode.chatCompletions)
    Text("Responses").tag(APIMode.responses)
}
.disabled(viewModel.editModelProviderDialect == .deepSeekV4)
```

Update model row detail text:

```swift
Text("\(model.maxContextTokens) tokens · \(model.apiModeValue == .responses ? "Responses" : "Chat Completions") · \(model.providerDialectValue.displayName)")
```

- [ ] **Step 6: 添加本地化键**

Modify `OpenChat/Resources/Localizable.xcstrings` by adding these keys under `"strings"`:

```json
"Provider" : {
  "localizations" : {
    "zh-Hans" : {
      "stringUnit" : {
        "state" : "translated",
        "value" : "供应商"
      }
    }
  }
},
"OpenAI Compatible" : {
  "localizations" : {
    "zh-Hans" : {
      "stringUnit" : {
        "state" : "translated",
        "value" : "OpenAI 兼容"
      }
    }
  }
},
"DeepSeek V4" : {
  "localizations" : {
    "zh-Hans" : {
      "stringUnit" : {
        "state" : "translated",
        "value" : "DeepSeek V4"
      }
    }
  }
}
```

- [ ] **Step 7: 运行模型与设置测试**

Run:

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:OpenChatTests/DatabaseManager+EndpointModels -only-testing:OpenChatTests/APIEndpointEditorViewModel
```

Expected: PASS。

- [ ] **Step 8: Commit**

```bash
git add OpenChat/Core/Database/DatabaseManager+EndpointModels.swift OpenChat/Features/Settings/ViewModels/APIEndpointEditorViewModel.swift OpenChat/Features/Settings/Views/APIEndpointEditorView.swift OpenChatTests/Core/DatabaseTests/EndpointModelTests.swift OpenChat/Resources/Localizable.xcstrings
git commit -m "feat: configure deepseek v4 models"
```

## Task 5: Chat 设置中的 DeepSeek 思考强度与角色视角 UX

**Files:**
- Modify: `OpenChat/Features/Chat/ViewModels/ChatViewModel.swift`
- Modify: `OpenChat/Features/Chat/Views/ChatSettingsSheet.swift`
- Modify: `OpenChat/Resources/Localizable.xcstrings`
- Test: `OpenChatTests/Features/ChatTests/ChatViewModelPromptAssemblyTests.swift`

- [ ] **Step 1: 写参数保存失败测试**

Append to `OpenChatTests/Features/ChatTests/ChatViewModelPromptAssemblyTests.swift`:

```swift
@MainActor
@Test func test_current_parameters_preserve_reasoning_effort() async throws {
    let database = try TestHelpers.makeDatabaseManager()
    let conversation = TestHelpers.makeConversation()
    let viewModel = ChatViewModel(
        conversation: conversation,
        databaseManager: database,
        apiClient: APIClient(),
        contextManager: ContextManager(databaseManager: database, apiClient: APIClient()),
        memoryManager: MemoryManager(databaseManager: database, apiClient: APIClient()),
        titleGenerator: TitleGenerator(apiClient: APIClient()),
        appState: AppState()
    )

    viewModel.thinkingEnabled = true
    viewModel.thinkingBudget = 8192
    viewModel.reasoningEffort = .max

    let parameters = viewModel.currentParameters

    #expect(parameters.isThinkingEnabled == true)
    #expect(parameters.reasoningEffort == .max)
}
```

- [ ] **Step 2: 运行失败测试**

Run:

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests/test_current_parameters_preserve_reasoning_effort
```

Expected: FAIL，错误包含 `Value of type 'ChatViewModel' has no member 'reasoningEffort'`。

- [ ] **Step 3: 扩展 ChatViewModel 参数状态**

Modify `OpenChat/Features/Chat/ViewModels/ChatViewModel.swift`:

```swift
var thinkingEnabled = false
var thinkingBudget = 8192
var reasoningEffort: ReasoningEffort = .high
```

In init parameter restore:

```swift
if let parameters = conversation.decodedModelParameters {
    modelTemperature = parameters.temperature
    modelTopP = parameters.topP
    modelMaxTokens = parameters.maxTokens ?? 1024
    thinkingEnabled = parameters.isThinkingEnabled
    thinkingBudget = parameters.thinkingBudget ?? 8192
    reasoningEffort = parameters.reasoningEffort
}
```

Add helper:

```swift
var selectedProviderDialect: APIProviderDialect {
    guard let selectedModelName else {
        return availableModelsForEndpoint.first(where: \.isDefault)?.providerDialectValue ?? .openAICompatible
    }
    return availableModelsForEndpoint.first(where: { $0.modelId == selectedModelName })?.providerDialectValue ?? .openAICompatible
}
```

Update `currentParameters`:

```swift
var currentParameters: ModelParameters {
    ModelParameters(
        temperature: modelTemperature,
        topP: modelTopP,
        maxTokens: modelMaxTokens,
        frequencyPenalty: 0,
        presencePenalty: 0,
        stop: nil,
        thinkingBudget: thinkingEnabled ? thinkingBudget : nil,
        reasoningEffort: reasoningEffort
    )
}
```

- [ ] **Step 4: 更新 ChatSettingsSheet**

Modify `OpenChat/Features/Chat/Views/ChatSettingsSheet.swift` inside thinking section:

```swift
Toggle(String(localized: "Enable Thinking"), isOn: thinkingEnabledBinding)

if viewModel.thinkingEnabled {
    if viewModel.selectedProviderDialect == .deepSeekV4 {
        Picker(String(localized: "Reasoning Effort"), selection: reasoningEffortBinding) {
            ForEach(ReasoningEffort.allCases) { effort in
                Text(effort.displayName).tag(effort)
            }
        }
    } else {
        Stepper(value: thinkingBudgetBinding, in: 1024...65_536, step: 1024) {
            Text("\(String(localized: "Thinking Budget")): \(viewModel.thinkingBudget)")
        }
    }
}
```

Add binding:

```swift
private var reasoningEffortBinding: Binding<ReasoningEffort> {
    @Bindable var viewModel = viewModel
    return $viewModel.reasoningEffort
}
```

- [ ] **Step 5: 添加 UX 本地化**

Modify `OpenChat/Resources/Localizable.xcstrings`:

```json
"Reasoning Effort" : {
  "localizations" : {
    "zh-Hans" : {
      "stringUnit" : {
        "state" : "translated",
        "value" : "思考强度"
      }
    }
  }
},
"High" : {
  "localizations" : {
    "zh-Hans" : {
      "stringUnit" : {
        "state" : "translated",
        "value" : "高"
      }
    }
  }
},
"Max" : {
  "localizations" : {
    "zh-Hans" : {
      "stringUnit" : {
        "state" : "translated",
        "value" : "最大"
      }
    }
  }
},
"Character Thinking" : {
  "localizations" : {
    "zh-Hans" : {
      "stringUnit" : {
        "state" : "translated",
        "value" : "角色思考"
      }
    }
  }
},
"Character thinking…" : {
  "localizations" : {
    "zh-Hans" : {
      "stringUnit" : {
        "state" : "translated",
        "value" : "角色正在思考…"
      }
    }
  }
}
```

- [ ] **Step 6: 运行 Chat 参数测试**

Run:

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests/test_current_parameters_preserve_reasoning_effort
```

Expected: PASS。

- [ ] **Step 7: Commit**

```bash
git add OpenChat/Features/Chat/ViewModels/ChatViewModel.swift OpenChat/Features/Chat/Views/ChatSettingsSheet.swift OpenChat/Resources/Localizable.xcstrings OpenChatTests/Features/ChatTests/ChatViewModelPromptAssemblyTests.swift
git commit -m "feat: expose deepseek reasoning effort in chat settings"
```

## Task 6: API Client 文档与数据模型文档同步

**Files:**
- Modify: `arch/modules/api-client.md`
- Modify: `arch/data-model.md`
- Modify: `arch/source-tree.md`

- [ ] **Step 1: 更新 API client 文档**

Modify `arch/modules/api-client.md` by adding a DeepSeek V4 subsection under OpenAI compatibility:

```markdown
### DeepSeek V4 方言

DeepSeek V4 使用 OpenAI-compatible Chat Completions 路由，但请求体不是当前 OpenAI reasoning 分支的 `max_completion_tokens` 语义。模型级 `providerDialect = deepSeekV4` 时：

- 路由仍为 `POST {baseURL}/chat/completions`。
- 官方 baseURL 为 `https://api.deepseek.com`。
- 模型为 `deepseek-v4-flash` / `deepseek-v4-pro`。
- thinking enabled 时发送：
  - `thinking: { "type": "enabled" }`
  - `reasoning_effort: "high" | "max"`
  - `max_tokens` 作为可见输出上限
  - 不发送 `temperature`、`top_p`、`presence_penalty`、`frequency_penalty`
- thinking disabled 时发送：
  - `thinking: { "type": "disabled" }`
  - 常规采样参数按 UI 配置发送
- DeepSeek V4 返回的 `reasoning_content` 作为角色思考链保存和展示。当前 OpenChat 没有 Tool Calls 执行器，因此正常角色对话历史不会回传历史 `reasoning_content`；未来接入工具调用时，发生 tool call 的 assistant 消息必须完整回传 `reasoning_content`、`tool_calls` 与后续 `role: tool` 消息。
```

- [ ] **Step 2: 更新数据模型文档**

Modify `arch/data-model.md` endpoint_model section:

```markdown
| providerDialect | TEXT | NOT NULL, DEFAULT 'openAICompatible' | 供应商方言：`openAICompatible` / `deepSeekV4` |
```

Update Swift Record snippet:

```swift
struct EndpointModelRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "endpoint_model"
    var id: String
    var endpointId: String
    var modelId: String
    var maxContextTokens: Int
    var apiMode: String          // "chatCompletions" | "responses"
    var providerDialect: String  // "openAICompatible" | "deepSeekV4"
    var isDefault: Bool
    var isManual: Bool
    var createdAt: Date

    static let endpoint = belongsTo(APIEndpointRecord.self)
}
```

Add migration section:

```markdown
### v10_add_provider_dialect_to_endpoint_model

为 `endpoint_model` 添加 `providerDialect`，使 API 路由模式和供应商请求方言分离。历史记录默认 `openAICompatible`；`deepseek-v4-flash` / `deepseek-v4-pro` / `deepseek-v4-*` 自动标记为 `deepSeekV4`。当历史 DeepSeek V4 模型仍使用 4096 默认 context 时，迁移提升为 1,000,000，以符合 DeepSeek V4 1M 上下文能力。
```

- [ ] **Step 3: 更新 source tree 文档**

Modify `arch/source-tree.md` networking section:

```markdown
│   │   ├── APIProviderDialect.swift        # 供应商请求方言（OpenAI-compatible / DeepSeek V4）
```

- [ ] **Step 4: 文档 grep 验证**

Run:

```bash
rg -n "providerDialect|DeepSeek V4|deepSeekV4|reasoning_effort|thinking" arch/modules/api-client.md arch/data-model.md arch/source-tree.md
```

Expected: output includes all edited docs and no missing term.

- [ ] **Step 5: Commit**

```bash
git add arch/modules/api-client.md arch/data-model.md arch/source-tree.md
git commit -m "docs: document deepseek v4 provider dialect"
```

## Task 7: Focused 与全量验证

**Files:**
- No code changes.

- [ ] **Step 1: 运行 DeepSeek 相关 focused tests**

Run:

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:OpenChatTests/DeepSeekV4RequestTests -only-testing:OpenChatTests/DeepSeekV4ReasoningContentTests -only-testing:OpenChatTests/DatabaseManager+EndpointModels -only-testing:OpenChatTests/APIEndpointEditorViewModel
```

Expected: PASS。

- [ ] **Step 2: 运行 networking 回归测试**

Run:

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:OpenChatTests/APIClientTests -only-testing:OpenChatTests/APIRequestThinkingTests -only-testing:OpenChatTests/ResponsesAPIRequestTests -only-testing:OpenChatTests/StreamingReasoningIntegrationTests
```

Expected: PASS。

- [ ] **Step 3: 运行全量测试**

Run:

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17'
```

Expected: all Swift Testing tests PASS。若 simulator 名称不存在，先运行：

```bash
xcrun simctl list devices available | rg "iPhone"
```

然后把 destination 中的 `name=iPhone 17` 替换为本机可用的 iOS 17+ simulator。

- [ ] **Step 4: 检查签名配置未被修改**

Run:

```bash
git diff -- scripts/generate_xcodeproj.rb OpenChat.xcodeproj/project.pbxproj | rg -n "PRODUCT_BUNDLE_IDENTIFIER|DEVELOPMENT_TEAM|CODE_SIGN_STYLE" || true
```

Expected: no output。

- [ ] **Step 5: 检查工作区差异**

Run:

```bash
git status --short
git diff --check
```

Expected: only planned files modified; `git diff --check` prints no whitespace errors。

- [ ] **Step 6: Final verification commit**

```bash
git add OpenChat OpenChatTests arch
git commit -m "test: verify deepseek v4 adaptation"
```

## Completion Criteria

- `deepseek-v4-flash` / `deepseek-v4-pro` 可配置为 `providerDialect = deepSeekV4`，并强制使用 `chatCompletions` 路由。
- DeepSeek V4 thinking enabled 请求包含 `thinking.enabled` 与 `reasoning_effort`，不包含 `max_completion_tokens` 和无效采样参数。
- DeepSeek V4 thinking disabled 请求显式包含 `thinking.disabled`，避免 DeepSeek 默认开启思考。
- 流式与非流式 `reasoning_content` 都能解析；流式角色思考继续保存到 `MessageRecord.reasoningContent`。
- 普通无工具角色对话历史不回传历史 `reasoning_content`；文档明确未来 Tool Calls 接入时的回传约束。
- DeepSeek V4 模型导入时默认 context 为 1,000,000；用户手动配置可保存 provider dialect。
- Chat 设置页对 DeepSeek V4 展示 `Reasoning Effort`，对其他 provider 保留现有 budget 行为。
- `arch/modules/api-client.md`、`arch/data-model.md`、`arch/source-tree.md` 与源码同步。
- Focused tests、networking tests、全量 `xcodebuild test` 通过。

## Self-Review

- Spec coverage: DeepSeek V4 API 调用、thinking 开关、reasoning_effort、角色视角思考链展示/保存、模型配置、文档同步均有对应任务。
- Placeholder scan: 本计划没有占位步骤；每个实现步骤都给出具体代码或命令。
- Type consistency: `APIProviderDialect.deepSeekV4`、`ReasoningEffort.high/max`、`providerDialect`、`providerDialectValue`、`reasoningEffort` 在计划内命名一致。
