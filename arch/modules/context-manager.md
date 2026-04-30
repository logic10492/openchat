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
| `CompressionPolicy.swift` | 计算 OpenChat 40% 预算、Codex 风格 effective compact window 与自动压缩阈值 |
| `CompressionSourceHasher.swift` | 对 checkpoint 覆盖的消息范围生成 SHA256 source hash |
| `PreparedHistory.swift` | 表达 `compressed context + checkpoint 后 message history`，并提供旧 PromptAssembler 兼容出口 |
| `CompressionSummarizer.swift` | 包装 API 压缩提示词，不直接访问数据库 |
| `CheckpointCompactor.swift` | 复用有效 checkpoint，选择新压缩范围，保存 checkpoint |
| `CompressionStrategy.swift` | 历史兼容类型；当前主链路已迁移到 checkpoint compactor |

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

    /// 返回结构化 checkpoint 历史，供后续 PromptAssembler 结构化改造使用。
    func prepareContextHistory(
        messages allMessages: [MessageRecord],
        conversation: ConversationRecord,
        endpoint: APIEndpointConfig,
        fixedTokens: Int
    ) async throws -> PreparedHistory
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

## 5. Checkpoint Compression

### 5.1 适用场景

- 内容适合发送给公开 API 模型（如 OpenAI API）
- 用户希望保留更多上下文语义信息
- 可以接受在超过阈值时额外一次 API 调用
- 希望旧历史压缩结果可跨轮次持续复用

### 5.2 算法

当前实现采用 Codex 风格的压缩 checkpoint：

```
function prepareCheckpointHistory(allMessages, fixedTokens):
    policy = CompressionPolicy(endpoint)
    latest = latestValidCheckpoint(conversationId, allMessages)
    checkpointEnd = latest?.sourceEndSortOrder ?? 0
    afterCheckpoint = allMessages where sortOrder > checkpointEnd
    activeTokens = fixedTokens + latest.summaryTokenCount + tokenCount(afterCheckpoint)

    if activeTokens <= policy.autoCompactTokenLimit:
        return latest.summary + afterCheckpoint

    recentMessages = newest messages after checkpoint, up to 70% of history budget
    messagesToCompress = older messages after checkpoint and before recentMessages

    if messagesToCompress is too small:
        return truncation fallback without saving checkpoint

    summary = CompressionSummarizer(previousSummary: latest.summary, messagesToCompress)
    checkpoint = save conversation_compression_checkpoint
    return checkpoint.summary + messages after checkpoint.sourceEndSortOrder
```

### 5.3 阈值

- OpenChat 仍保持 `endpoint.maxContextTokens × 0.40` 硬上限。
- checkpoint 自动压缩阈值为 `min(promptTokenBudget, effectiveCompactWindowTokens × 0.90)`。
- `gpt-5.5` 系列模型虽然可配置为 1M 上下文，但压缩阈值按 Codex 事实窗口 `258_000 × 0.90 = 232_200` 计算，并继续受 OpenChat `maxContextTokens × 0.40` 硬上限约束。

### 5.4 压缩 API 调用

`CompressionSummarizer` 使用聊天端点调用 API。压缩提示词固定以 `CONTEXT CHECKPOINT COMPACTION` 标记，并要求生成 durable handoff summary，保留事实、角色决定、关系状态、情绪状态、剧情状态、未解决约定和用户偏好。

```
You are performing a CONTEXT CHECKPOINT COMPACTION for an ongoing roleplay conversation.
Produce a durable handoff summary that will replace older transcript items.
```

### 5.5 压缩结果持久化

压缩完成后：
1. 保存一条 `conversation_compression_checkpoint`，记录覆盖范围、source hash、摘要、模型和阈值参数。
2. 不删除、不替换原始 `message`。
3. 本轮 prompt 通过 `PreparedHistory.messagesForLegacyPrompt(conversationId:)` 临时生成 `role: "system"` / `isCompressed: true` 的 `[Previously]\n{summary}` 消息，拼接 checkpoint 后真实历史。
4. 编辑或删除被 checkpoint 覆盖的消息时，`ChatViewModel` 删除受影响 checkpoint，避免 stale summary。
5. 压缩失败时 fallback 到 `TruncationStrategy`，不写入半成品 checkpoint。

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
│  3. 通过 CompressionPolicy 计算历史预算与压缩阈值        │
│  4. compression 策略优先复用有效 checkpoint              │
│  5. 必要时生成新 checkpoint，返回兼容 [MessageRecord]    │
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
3. ContextManager 通过 `CompressionPolicy.historyBudget(fixedTokens:)` 计算历史预算
4. 执行选定策略，压缩策略返回 `compressed context + checkpoint 后 message history`
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
3. **checkpoint 持久化**：避免每轮重复压缩，同一段旧消息只压缩一次，并跨后续请求复用
4. **保留原始内容**：checkpoint 不删除原始消息，后续编辑/删除历史时通过 checkpoint invalidation 保证摘要不会过期
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
