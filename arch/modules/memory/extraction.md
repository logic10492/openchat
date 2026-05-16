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

## 4. LLM 提取请求（retain v2）

`callExtractionAPI(messages:characterCard:existingMemoryHints:endpoint:)` 把待处理消息格式化为结构化 JSON：

```json
{
  "character": {
    "id": "...",
    "name": "...",
    "summary": "personality backstory scenario"
  },
  "existingMemoryHints": [
    { "id": "...", "content": "...", "type": "relationship" }
  ],
  "messages": [
    { "id": "...", "sortOrder": 12, "role": "user", "content": "..." }
  ]
}
```

系统 prompt 要求返回 JSON array，兼容 v1 并支持 v2 字段：

```json
[
  {
    "content": "Brief description of the memory",
    "type": "event|fact|relationship|summary",
    "importance": 0,
    "sourceStartSortOrder": 12,
    "sourceEndSortOrder": 13,
    "sourceMessageIds": ["..."],
    "confidence": 0.8,
    "tags": ["relationship"],
    "dedupeKey": "normalized-short-key",
    "action": "insert|reinforce|skip"
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
- 编码失败时 fallback 到纯文本 `role: content` 拼接。

## 5. 解析容错与验证

`parseExtractedMemories(_:)` 当前容错：

- 移除 ```json / ``` markdown fence。
- 如果响应前后有解释文本，截取第一个 `[` 到最后一个 `]`。
- 使用 `JSONDecoder` 解析 `[ExtractedMemory]`。
- v1 字段：
  - `type` 缺失时默认 `"event"`。
  - `type` 解析时做 lowercased，未知值 fallback `.event`。
  - `importance` 支持 Int 或 String；缺失默认 50；最终 clamp 到 0...100。
- v2 字段：
  - `sourceStartSortOrder` / `sourceEndSortOrder` 必须在本批 message sortOrder 范围内；越界丢弃该条。
  - `sourceMessageIds` 必须是本批 ids 子集；无效 id 会从 provenance 中过滤。
  - `confidence` 在 provenance 中 clamp 到 `0...1`。
  - `tags` 去空、去重、限制数量（10 条）。
  - `action == skip` 不写 memory。
  - `action == reinforce` 第一版不覆盖旧 memory，也不新增重复记忆，直接跳过插入。

同批去重：

- 同一 extraction response 中 `dedupeKey` 相同：保留 importance 更高；importance 相同保留 content 更短。
- 没有 `dedupeKey` 时可用 normalized content 作为临时 key。
- 不自动删除旧 memory。

失败行为：

- JSON 无法解析：抛出 `MemoryError.extractionFailed`。
- response 没有 content：抛出 `MemoryError.invalidExtractionResponse`。

## 6. 写入步骤（retain v2）

每条经过 validation 和 dedupe 的 `ExtractedMemory` 转成：

```swift
MemoryEntryRecord(
    id: entryId,
    characterCardId: characterCardId,
    sourceConversationId: current.id,
    content: extracted.content,
    memoryType: extracted.resolvedType.rawValue,
    importance: extracted.resolvedImportance,
    createdAt: now,
    updatedAt: now
)
```

并生成对应 provenance：

```swift
MemoryEntryProvenanceRecord(
    memoryEntryId: entryId,
    sourceStartSortOrder: extracted.sourceStartSortOrder,
    sourceEndSortOrder: extracted.sourceEndSortOrder,
    sourceMessageIds: extracted.sourceMessageIds, // 已过滤为本批有效 message ids
    extractionModel: endpoint.modelName,
    extractionPromptVersion: "v2",
    confidence: extracted.confidence.clamped(to: 0...1),
    dedupeKey: extracted.normalizedDedupeKey,
    tags: extracted.tags.cleaned,
    createdAt: now,
    updatedAt: now
)
```

随后：

1. `EmbeddingProvider.embed(entry.content, isQuery: false)`
2. 收集 `(entry, embedding)` 和 `provenanceByEntryId`。
3. `MemoryVectorStore.insert(entries:provenances:)` 原子保存 `memory_entry + memory_embedding + memory_entry_provenance`。
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

- 跨批去重目前只通过 existing memory hints 让 LLM 返回 `skip/reinforce`，不做自动删除或合并。
- 失败重试没有专门队列。
- `triggerMemoryExtraction()` 兜底路径不会刷新 UI 状态。
- 没有把 LLM 提取耗时、提取候选、写入条数作为可审计 telemetry 暴露。

## 9. Hindsight-lite retain v2 实现证据

retain v2 已落地，关键源码位置：

- `OpenChat/Core/Memory/MemoryManager.swift`：`callExtractionAPI(...)` 结构化输入、`validateAndFilter(...)`、`dedupeWithinBatch(...)`、`makeProvenance(...)`。
- `OpenChat/Core/Memory/MemoryManager.swift`：`MemoryExtractionInput` 结构体、`JSONEncoder.encodeExtractionInput(...)`。
- `OpenChat/Core/Database/Records/MemoryEntryProvenanceRecord.swift`：GRDB Record 定义。
- `OpenChat/Core/Database/Migrations.swift`：`v14_create_memory_entry_provenance`。
- `OpenChat/Core/Database/DatabaseManager+Memory.swift`：provenance CRUD。
- `OpenChat/Core/Memory/VectorStore.swift`：`insert(entries:provenances:)` 原子写入。
- `OpenChat/Core/Memory/MemoryDependencies.swift`：`MemoryVectorStore` 协议扩展默认实现。
- `OpenChatTests/Core/MemoryTests/MemoryManagerRetrievalTests.swift`：dedupe、source validation、atomicity 测试。
- `OpenChatTests/Core/MemoryExtractionParsingTests.swift`：v2 parsing、provenance CRUD 测试。
- `OpenChatTests/Core/DatabaseTests/MigrationTests.swift`：v14 migration 测试。

## 10. 实现证据

- `OpenChat/Features/Chat/ViewModels/ChatViewModel+Support.swift`
- `OpenChat/Core/Memory/MemoryManager.swift`
- `OpenChat/Core/Database/Records/ConversationRecord.swift`
- `OpenChatTests/Core/MemoryTests/MemoryExtractionCutoffTests.swift`
- `OpenChatTests/Core/MemoryExtractionParsingTests.swift`
- `OpenChatTests/Features/ChatTests/ChatViewModelPromptAssemblyTests.swift`
