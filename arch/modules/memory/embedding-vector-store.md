# Embedding 与向量存储

## 1. EmbeddingService

当前 embedding 模型为 App Bundle 内的 MultilingualE5Small CoreML 模型，输出 384 维向量。

| 项目 | 当前实现 |
|---|---|
| 模型 | `OpenChat/Resources/Models/MultilingualE5Small.mlpackage` |
| tokenizer | `OpenChat/Resources/Models/tokenizer.json` |
| tokenizer 类型 | XLM-RoBERTa Unigram vocab |
| 输入长度 | 固定 256 tokens |
| 输出维度 | 384 |
| 加载方式 | 实例内 lazy load，`NSLock` 保护 |
| 查询/文档区分 | E5 prefix |

E5 prefix：

| 场景 | `isQuery` | 前缀 |
|---|---:|---|
| 保存记忆 | `false` | `passage: ` |
| 检索查询 | `true` | `query: ` |

接口：

```swift
protocol EmbeddingProvider: Sendable {
    func embed(_ text: String, isQuery: Bool) throws -> [Float]
}
```

## 2. VectorStore

`VectorStore` 封装 sqlite-vec 的 CRUD 和 KNN 查询。

接口：

```swift
protocol MemoryVectorStore: Sendable {
    func insert(entryId: String, embedding: [Float]) async throws
    func insert(entry: MemoryEntryRecord, embedding: [Float]) async throws
    func insert(entries: [(entry: MemoryEntryRecord, embedding: [Float])]) async throws
    func search(query: [Float], characterCardId: String, limit: Int) async throws -> [(entryId: String, distance: Float)]
    func delete(entryId: String) async throws
    func deleteAll(characterCardId: String) async throws
}
```

## 3. 写入一致性

自动提取链路必须使用 batch 写入：

```
for ExtractedMemory:
  MemoryEntryRecord(...)
  embedding = embed(content, isQuery: false)

VectorStore.insert(entries:)
  -> validate every embedding dimension
  -> convert every embedding to blob
  -> single GRDB write transaction
  -> save memory_entry
  -> insert memory_embedding
```

约束：

- 任一条 embedding 维度错误，整批不进入事务。
- 任一条 DB/vector 写入失败，整批回滚。
- 不允许自动提取留下只有 `memory_entry`、没有 `memory_embedding` 的半索引记忆。

## 4. 检索实现

KNN 查询限定角色卡范围：

```sql
SELECT me.entry_id, me.distance
FROM memory_embedding me
WHERE me.entry_id IN (
    SELECT id FROM memory_entry WHERE characterCardId = ?
)
AND me.embedding MATCH ?
AND me.k = ?
ORDER BY me.distance
```

返回值是 `(entryId, distance)`，由 `MemoryManager.retrieveMemories(...)` 再回表加载 `MemoryEntryRecord`。

## 5. 错误类型

```swift
enum MemoryError: LocalizedError, Sendable {
    case modelLoadFailed(underlying: Error)
    case embeddingFailed(underlying: Error)
    case vectorStoreError(underlying: Error)
    case extractionFailed(reason: String)
    case invalidExtractionResponse
}
```

错误策略：

- 提取阶段 embedding/vector 失败：整批失败，Chat 显示 extraction failed，不推进 cutoff。
- 检索阶段 embedding/vector 失败：`MemoryManager.retrieveMemories(...)` 通过 `recallMemories(...)` 标记 `semanticUnavailable`，fallback 到 keyword + recent high-value；fallback 查询也失败才向 Chat 抛出。

## 6. 实现证据

- `OpenChat/Core/Memory/EmbeddingService.swift`
- `OpenChat/Core/Memory/XLMRobertaTokenizer.swift`
- `OpenChat/Core/Memory/MemoryDependencies.swift`
- `OpenChat/Core/Memory/VectorStore.swift`
- `OpenChatTests/Core/MemoryTests/VectorStoreTests.swift`
- `OpenChatTests/Core/MemoryTests/EmbeddingServiceTests.swift`
- `OpenChatTests/Core/MemoryTests/MemoryManagerRetrievalTests.swift`
