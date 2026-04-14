# 上下文管理模块设计

> 所属层：`Core/ContextManager/`
> 依赖：Core/Database（MessageRecord, ConversationRecord）, Core/Networking（APIClient）

## 1. 功能范围

- 控制发送给模型的上下文长度在 40% 以内
- 提供两种上下文缩减策略：对话剔除（Truncation）与对话压缩（Compression）
- 策略可按会话独立配置
- 与 PromptEngine 协作，在拼装前预处理历史消息

## 2. 文件清单与职责

| 文件 | 职责 |
|---|---|
| `ContextManager.swift` | 主调度器，根据会话配置选择策略，返回处理后的历史消息 |
| `ContextStrategy.swift` | 策略协议定义 + 枚举 |
| `TruncationStrategy.swift` | 对话剔除策略实现 |
| `CompressionStrategy.swift` | 对话压缩策略实现 |

## 3. 核心设计

### 3.1 策略协议

```swift
protocol ContextStrategyProtocol {
    /// 处理历史消息，使其适配 token 预算
    /// - allMessages: 会话中的全部历史消息（按 sortOrder 升序）
    /// - tokenBudget: 历史消息可用的 token 预算
    /// - returns: 处理后的消息数组（可能被截断或包含压缩摘要）
    func process(
        allMessages: [MessageRecord],
        tokenBudget: Int
    ) async throws -> [MessageRecord]
}
```

### 3.2 策略枚举

```swift
enum ContextStrategy: String, Codable {
    case truncation    // 对话剔除
    case compression   // 对话压缩
}
```

用户在每个会话中选择策略，存储在 `conversation.contextStrategy` 字段。

### 3.3 ContextManager 主接口

```swift
struct ContextManager {
    private let db: DatabaseManager
    private let apiClient: APIClient

    /// 获取处理后的历史消息
    /// - conversation: 当前会话
    /// - endpoint: API 端点配置
    /// - fixedTokens: 已被固定段（system prompt、角色描述等）占用的 token 数
    /// - returns: 处理后的历史消息数组
    func prepareHistory(
        conversation: ConversationRecord,
        endpoint: APIEndpointConfig,
        fixedTokens: Int
    ) async throws -> [MessageRecord]
}
```

## 4. 对话剔除策略 (Truncation)

### 4.1 适用场景

- 内容不适合发送给公开 API 模型
- 本地部署模型，KVCache 单例，不希望额外推理开销
- 用户对旧消息丢失可以接受

### 4.2 算法

```
function truncate(allMessages, tokenBudget):
    result = []
    remainingTokens = tokenBudget

    // 从最新消息向最旧遍历
    for msg in allMessages.reversed():
        tokens = TokenCounter.count(msg.content)
        if remainingTokens - tokens < 0:
            break   // 预算耗尽，更早的消息全部丢弃
        result.insert(msg, at: 0)
        remainingTokens -= tokens

    return result
```

### 4.3 特殊处理

- **始终保留最后一轮完整对话**：如果最新的 user + assistant 消息对超出预算，仍然保留（允许小幅超预算），但触发警告
- **压缩消息标记**：被剔除的消息仍保留在数据库中，不会被物理删除。仅在发送给 API 时不包含

## 5. 对话压缩策略 (Compression)

### 5.1 适用场景

- 内容适合发送给公开 API 模型（如 OpenAI API）
- 用户希望保留更多上下文语义信息
- 可以接受稍慢的响应速度（需要额外一次 API 调用）

### 5.2 算法

```
function compress(allMessages, tokenBudget):
    totalTokens = sum(TokenCounter.count(msg) for msg in allMessages)

    if totalTokens <= tokenBudget:
        return allMessages  // 未超预算，无需处理

    // 将消息分为两部分
    recentMessages = []
    olderMessages = []
    recentTokens = 0

    // 从最新开始，保留尽量多的最近消息（占预算的 70%）
    recentBudget = tokenBudget * 0.70
    for msg in allMessages.reversed():
        tokens = TokenCounter.count(msg.content)
        if recentTokens + tokens > recentBudget:
            break
        recentMessages.insert(msg, at: 0)
        recentTokens += tokens

    // 剩余消息为需要压缩的旧消息
    olderMessages = allMessages[0 ..< allMessages.count - recentMessages.count]

    if olderMessages.isEmpty:
        return recentMessages

    // 调用外部 API 压缩旧消息
    compressionBudget = tokenBudget - recentTokens
    summary = await compressViaAPI(olderMessages, compressionBudget)

    // 构建压缩消息
    summaryMessage = MessageRecord(
        role: "system",
        content: "[Previously: \(summary)]",
        isCompressed: true,
        originalContent: olderMessages.map { $0.content }.joined(separator: "\n")
    )

    return [summaryMessage] + recentMessages
```

### 5.3 压缩 API 调用

```swift
struct CompressionStrategy: ContextStrategyProtocol {
    let apiClient: APIClient
    let compressionEndpoint: APIEndpointConfig  // 用于压缩的 API 端点（可与聊天端点不同）

    /// 调用外部 API 压缩旧消息
    private func compressViaAPI(
        messages: [MessageRecord],
        maxTokens: Int
    ) async throws -> String
}
```

**压缩用的 system prompt**：

```
Summarize the following conversation concisely, preserving key facts, character actions,
emotional states, and plot developments. Keep the summary under {{maxTokens}} tokens.
Focus on information that would be important for continuing the conversation.
Do not add any commentary or analysis.
```

### 5.4 压缩端点选择

- 默认使用会话绑定的 `apiEndpoint`
- 若用户在设置中配置了专用的"压缩用端点"，则优先使用
- 设计意图：用户可以将聊天指向本地模型，压缩指向云端模型（速度更快、质量更好）

### 5.5 压缩结果持久化

压缩完成后：
1. 将压缩摘要存为一条新的 `MessageRecord`（`role: "system"`, `isCompressed: true`）
2. 被压缩的原始消息设置 `originalContent` 保留原文
3. 数据库中保留完整历史，UI 中可展开查看原始内容

## 6. 与 PromptEngine 的协作流程

```
┌───────────────────────────────────────────────────────┐
│  ChatViewModel: 用户发送消息                           │
└──────────┬────────────────────────────────────────────┘
           │
           ▼
┌───────────────────────────────────────────────────────┐
│  ContextManager.prepareHistory()                       │
│  1. 从 DB 加载会话全部消息                              │
│  2. 计算固定段 token（由调用方传入 fixedTokens）        │
│  3. 计算历史预算 = totalBudget - fixedTokens            │
│  4. 根据 conversation.contextStrategy 选择策略          │
│  5. 执行策略，返回处理后的 [MessageRecord]               │
└──────────┬────────────────────────────────────────────┘
           │
           ▼
┌───────────────────────────────────────────────────────┐
│  PromptAssembler.assemble()                            │
│  接收处理后的历史消息，与角色卡/世界书/用户输入拼装      │
│  → 最终的 [ChatMessage]                                │
└──────────┬────────────────────────────────────────────┘
           │
           ▼
┌───────────────────────────────────────────────────────┐
│  APIClient.streamMessage()                             │
│  发送给模型                                            │
└───────────────────────────────────────────────────────┘
```

### 调用时序细节

1. ChatViewModel 先计算固定段 token（system prompt、角色描述、场景、世界书、用户输入）
2. 将 fixedTokens 传给 ContextManager
3. ContextManager 计算 `historyBudget = endpoint.maxContextTokens * 0.40 - fixedTokens`
4. 执行选定策略，返回适配预算的历史消息
5. PromptAssembler 接收历史消息进行最终拼装

> 注意：步骤 1 中需要先做一次世界书关键词匹配来确定触发的条目，才能计算固定段 token。因此实际实现中，PromptAssembler 和 ContextManager 需要一个两阶段调用：
> - 阶段 1：PromptAssembler 计算固定段 + 世界书 token → 得到 fixedTokens
> - 阶段 2：ContextManager 用 fixedTokens 处理历史 → 得到 processedHistory
> - 阶段 3：PromptAssembler 用 processedHistory 完成最终拼装

## 7. 用户选择界面

在 `ChatSettingsSheet` 中（聊天界面的设置面板）：

```
┌─────────────────────────────────────────┐
│ 上下文管理策略                           │
│                                         │
│ (●) 对话剔除                            │
│     直接丢弃最早的消息                   │
│     适用于：本地模型 / 隐私内容          │
│                                         │
│ ( ) 对话压缩                            │
│     调用 API 将旧消息压缩为摘要          │
│     适用于：可使用云端 API / 需保留语义  │
│     ⓘ 压缩时会短暂增加响应时间          │
│                                         │
│ [使用默认策略]                           │
└─────────────────────────────────────────┘
```

## 8. 设计决策

1. **40% 上下文比例**：这是一个保守策略，确保模型有足够的"生成空间"和"注意力专注度"。特别是小模型（7B-13B），过长上下文会显著降低生成质量
2. **两阶段调用**：虽然略增复杂度，但保证世界书动态注入与历史预算计算的准确性
3. **压缩结果持久化**：避免反复调用压缩 API，同一段旧消息只压缩一次
4. **保留原始内容**：用户可以随时查看被压缩的原始对话，保证透明性
5. **独立压缩端点**：允许用户为压缩使用不同的（通常更便宜/更快的）API 端点

## 实现证据（2026-04-14）

- 代码位置：
  - `OpenChat/Core/ContextManager/ContextManager.swift`
  - `OpenChat/Core/ContextManager/TruncationStrategy.swift`
  - `OpenChat/Core/ContextManager/CompressionStrategy.swift`
  - `OpenChat/Core/ContextManager/ContextStrategy.swift`
- 已验证测试：
  - `OpenChatTests/Core/ContextManagerTests/TruncationStrategyTests.swift`
  - `OpenChatTests/Core/ContextManagerTests/CompressionStrategyTests.swift`
- 当前实现已对齐两阶段调用链：`PromptAssembler.preview(...)` 先计算固定段，再由 `ContextManager.prepareHistory(...)` 处理历史消息，最后完成最终拼装
