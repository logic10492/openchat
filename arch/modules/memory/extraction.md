# 记忆提取流程

## 1. 当前结论

OpenChat 当前的记忆条目生成属于轻量 retain：

- **LLM 参与**：生成 `content/type/importance`。
- **本地模型参与**：生成 memory embedding。
- **没有实现**：实体抽取、时间线归一化、因果图、观点更新、reflection synthesis。

## 2. 触发时机

主触发点在 `ChatViewModel.generateResponse(...)`：

1. 用户输入先持久化为 `MessageRecord`。
2. `shouldExtractMemories(for:)` 从 DB 读取最新 conversation 和 messages。
3. 用 `conversation.lastExtractedSortOrder` 计算待处理消息数。
4. 当 `pendingCount >= ChatViewModel.minimumPendingMessagesForExtraction` 时，设置 `extractionPhase = .extracting`。
5. 同步 await `memoryManager.extractMemories(from:)`。
6. 提取成功后刷新本地 `conversation`，再继续检索记忆和组装 prompt。

当前阈值：

```swift
MemoryManager.minimumMessagesForExtraction == 4
ChatViewModel.minimumPendingMessagesForExtraction == MemoryManager.minimumMessagesForExtraction
```

兜底触发：

- `ChatView.onDisappear` 会调用 `triggerMemoryExtraction()`。
- 该路径是 fire-and-forget，适合作为视图离开时的补充，不是主确定性路径。

## 3. 增量 cutoff

`MemoryManager.extractMemories(from:)` 会重新读取 DB 中的 latest conversation：

```
cutoff = conversation.lastExtractedSortOrder
allMessages = fetchMessages(conversationId)
messages = cutoff == nil ? allMessages : allMessages where sortOrder > cutoff
```

规则：

- 新消息数少于 4 条时跳过，不调用 API。
- 成功写入 memory/vector 后，更新 `conversation.lastExtractedSortOrder = max(messages.sortOrder)`。
- 提取失败、embedding 失败、vector 写入失败或消息不足时不推进。

使用 `sortOrder` 而不是 `memory_entry.createdAt` 的原因：

- `sortOrder` 是 conversation 内的逻辑消息顺序，适合表达“处理到哪一条消息”。
- `createdAt` 是 memory entry 的生成时间，不等于消息时间；并发写入和提取延迟会让 cutoff 模糊。

## 4. LLM 提取请求

`callExtractionAPI(messages:endpoint:)` 把待处理消息格式化为：

```text
user: ...
assistant: ...
user: ...
```

系统 prompt 要求返回 JSON array：

```json
[
  {
    "content": "Brief description of the memory",
    "type": "event|fact|relationship|summary",
    "importance": 0
  }
]
```

参数：

```swift
ModelParameters(
    temperature: 0.3,
    topP: 0.9,
    maxTokens: 2048,
    frequencyPenalty: 0,
    presencePenalty: 0,
    stop: nil
)
```

端点解析：

- 优先使用 conversation 绑定的 endpoint/model。
- 否则使用默认 endpoint/model。
- API key 走 `APIKeyStore`；旧 `api_endpoint.apiKey` 会迁移保存到 Keychain 并清空 DB 字段。

## 5. 解析容错

`parseExtractedMemories(_:)` 当前容错：

- 移除 ```json / ``` markdown fence。
- 如果响应前后有解释文本，截取第一个 `[` 到最后一个 `]`。
- 使用 `JSONDecoder` 解析 `[ExtractedMemory]`。
- `type` 缺失时默认 `"event"`。
- `type` 解析时做 lowercased，未知值 fallback `.event`。
- `importance` 支持 Int 或 String；缺失默认 50；最终 clamp 到 0...100。

失败行为：

- JSON 无法解析：抛出 `MemoryError.extractionFailed`。
- response 没有 content：抛出 `MemoryError.invalidExtractionResponse`。

## 6. 写入步骤

每条 `ExtractedMemory` 转成：

```swift
MemoryEntryRecord(
    id: UUID().uuidString,
    characterCardId: characterCardId,
    sourceConversationId: current.id,
    content: extracted.content,
    memoryType: extracted.resolvedType.rawValue,
    importance: extracted.resolvedImportance,
    createdAt: now,
    updatedAt: now
)
```

随后：

1. `EmbeddingProvider.embed(entry.content, isQuery: false)`
2. 收集 `(entry, embedding)`。
3. `MemoryVectorStore.insert(entries:)` 原子保存。
4. 更新 `conversation.lastExtractedSortOrder`。
5. 返回已保存的 `[MemoryEntryRecord]` 给 Chat UI。

## 7. Chat UI 状态

提取期间由 `MemoryExtractionPhase` 表达状态：

```swift
case idle
case extracting
case completed(count: Int, summaries: [String])
case skipped
case failed(description: String)
```

Chat 中的处理：

- 成功且 result 非空：`.completed(count:summaries:)`
- 成功但 result 为空：`.skipped`
- 抛错：`.failed(description:)`

## 8. 当前缺口

- 提取 prompt 没有要求 evidence/source message range。
- 同一批或跨批重复记忆没有 dedupe。
- 失败重试没有专门队列。
- `triggerMemoryExtraction()` 兜底路径不会刷新 UI 状态。
- 没有把 LLM 提取耗时、提取候选、写入条数作为可审计 telemetry 暴露。

## 9. Hindsight-lite retain v2 规划

`hindsight-lite.md` 将当前提取流程定义为 retain v1。retain v2 的目标不是改变触发时机，而是让每条记忆可追踪、可去重、可审计。

建议变化：

- extraction input 带 message `id` / `sortOrder`，而不是纯 `role: content` 文本。
- extraction input 带少量角色卡摘要和 existing memory hints，帮助 LLM 判断重复、强化或跳过。
- extraction output 增加 `sourceStartSortOrder`、`sourceEndSortOrder`、`sourceMessageIds`、`confidence`、`tags`、`dedupeKey` 和 `action`。
- v2 字段落入 companion table，例如 `memory_entry_provenance`，避免一次性重写 `memory_entry` 主表。
- `action == reinforce` 或重复候选不应静默覆盖旧记忆；第一版可以记录 metadata 或跳过写入。

这些都是规划项，当前源码尚未实现。

## 10. 实现证据

- `OpenChat/Features/Chat/ViewModels/ChatViewModel+Support.swift`
- `OpenChat/Core/Memory/MemoryManager.swift`
- `OpenChat/Core/Database/Records/ConversationRecord.swift`
- `OpenChatTests/Core/MemoryTests/MemoryExtractionCutoffTests.swift`
- `OpenChatTests/Core/MemoryExtractionParsingTests.swift`
- `OpenChatTests/Features/ChatTests/ChatViewModelPromptAssemblyTests.swift`
