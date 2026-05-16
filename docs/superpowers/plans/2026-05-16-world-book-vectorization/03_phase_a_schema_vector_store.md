# 03. Phase A - Schema 与 Vector Store

> 状态：已实施。实现证据见本文末尾“Phase A 完成记录”。

## 目标

建立世界书向量表和最小 KNN 查询能力，但不改变 Chat prompt 链路。

## A1. Migration

在 `Migrations.makeMigrator()` 末尾追加：

```text
v15_create_world_book_entry_embedding
v16_create_world_book_entry_embedding_meta
```

`v15`：

```sql
CREATE VIRTUAL TABLE world_book_entry_embedding USING vec0(
    entry_id TEXT PRIMARY KEY,
    embedding float[384]
);
```

`v16`：

```text
world_book_entry_embedding_meta
  entryId TEXT PRIMARY KEY REFERENCES world_book_entry(id) ON DELETE CASCADE
  contentHash TEXT NOT NULL
  embeddingModel TEXT NOT NULL
  embeddingDimension INTEGER NOT NULL
  status TEXT NOT NULL
  embeddedAt DATETIME
  lastAttemptAt DATETIME
  lastError TEXT
  updatedAt DATETIME NOT NULL
```

建议 index：

- `idx_world_book_entry_embedding_meta_status`
- `idx_world_book_entry_embedding_meta_model`

实现要求：

- 使用 `Historical.worldBookEntryEmbeddingTable` / `Historical.worldBookEntryEmbeddingMetaTable` migration-local constants。
- 384 写成 migration-local historical constant，不能引用 `EmbeddingService.embeddingDimension`。
- 不在 migration 内 backfill embedding。

## A2. Meta Record

新增：

```text
OpenChat/Core/Database/Records/WorldBookEntryEmbeddingMetaRecord.swift
```

建议字段：

```swift
struct WorldBookEntryEmbeddingMetaRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "world_book_entry_embedding_meta"

    var entryId: String
    var contentHash: String
    var embeddingModel: String
    var embeddingDimension: Int
    var status: String
    var embeddedAt: Date?
    var lastAttemptAt: Date?
    var lastError: String?
    var updatedAt: Date
}
```

状态 enum 可放在 Core/WorldBook：

```swift
enum WorldBookEmbeddingStatus: String, Codable, Sendable {
    case indexed
    case needsRebuild = "needs_rebuild"
    case failed
}
```

## A3. WorldBookVectorStore

新增：

```text
OpenChat/Core/WorldBook/WorldBookVectorStore.swift
```

最小接口：

```swift
struct WorldBookVectorStore: Sendable {
    func upsert(entryId: String, embedding: [Float]) async throws
    func search(query: [Float], worldBookId: String, limit: Int) async throws -> [(entryId: String, distance: Float)]
    func delete(entryId: String) async throws
    func deleteAll(worldBookId: String) async throws
}
```

KNN 必须限定 worldBook：

```sql
SELECT wbe.entry_id, wbe.distance
FROM world_book_entry_embedding wbe
WHERE wbe.entry_id IN (
    SELECT id FROM world_book_entry
    WHERE worldBookId = ? AND isEnabled = 1
)
AND wbe.embedding MATCH ?
AND wbe.k = ?
ORDER BY wbe.distance
```

注意：

- `upsert` 可先 delete old vector 再 insert，避免 duplicate vector insert。
- validate dimension 必须在 DB transaction 前完成。
- virtual table 操作抛错包装为 `WorldBookError.vectorStoreError(underlying:)`。

## A4. Database Cleanup Hooks

Phase A 可以先只新增 helper，不接入 UI：

```swift
func deleteWorldBookEntryEmbedding(entryId: String, in db: Database) throws
func deleteWorldBookEntryEmbeddings(worldBookId: String, in db: Database) throws
```

真正 delete path wiring 放到 Phase D。

## A5. Tests

新增或扩展：

- `MigrationTests.test_v15_creates_world_book_entry_embedding_table`
- `MigrationTests.test_v16_creates_world_book_embedding_meta_columns`
- `MigrationTests.test_migrations_do_not_reference_runtime_record_or_enum_symbols` 增加世界书相关 forbidden references，如 `EmbeddingService.`
- `WorldBookVectorStoreTests.test_upsert_saves_vector_for_world_book_search`
- `WorldBookVectorStoreTests.test_search_limits_knn_to_requested_world_book_before_topK`
- `WorldBookVectorStoreTests.test_delete_removes_vector_row`
- `WorldBookVectorStoreTests.test_invalid_dimension_throws_before_partial_write`

Phase A focused command：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MigrationTests' '-only-testing:OpenChatTests/WorldBookVectorStoreTests'
```

## Phase A 完成记录

已实现：

- `OpenChat/Core/Database/Migrations.swift`：追加 `v15_create_world_book_entry_embedding`、`v16_create_world_book_entry_embedding_meta`，使用 migration-local historical constants 和 384 维 historical constant。
- `OpenChat/Core/Database/Records/WorldBookEntryEmbeddingMetaRecord.swift`：meta Record 与 `WorldBookEmbeddingStatus` 解析。
- `OpenChat/Core/WorldBook/WorldBookError.swift`、`WorldBookRecallModels.swift`、`WorldBookVectorStore.swift`：typed error、status enum、upsert/search/delete/deleteAll。
- `OpenChat/Core/Database/DatabaseManager+Content.swift`：新增 `deleteWorldBookEntryEmbedding(...)`、`deleteWorldBookEntryEmbeddings(...)` helper；正式 delete path wiring 仍留给 Phase D。
- `OpenChatTests/Core/DatabaseTests/MigrationTests.swift`：覆盖 v15/v16 schema、索引、cascade、forbidden runtime reference。
- `OpenChatTests/Core/WorldBookTests/WorldBookVectorStoreTests.swift`：覆盖 upsert、worldBook 限定、disabled entry 过滤、delete、invalid dimension。

验证：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MigrationTests' '-only-testing:OpenChatTests/WorldBookVectorStoreTests'
```

结果：39 tests / 2 suites passed，`** TEST SUCCEEDED **`。

追加防漂移验证：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MigrationTests' '-only-testing:OpenChatTests/VectorStoreTests' '-only-testing:OpenChatTests/WorldBookVectorStoreTests' '-only-testing:OpenChatTests/PromptAssemblerTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests'
```

结果：72 tests / 5 suites passed，`** TEST SUCCEEDED **`。

Full suite：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,id=2277CB75-AF36-4ABF-84EE-7444C1DD6759'
```

实际设备：iOS 26.5 `iPhone 17`。结果：261 tests / 47 suites passed，`** TEST SUCCEEDED **`。

未实施且不属于 Phase A：

- embedding text builder、content hash、indexer/backfill。
- `WorldBookSource` 和 Chat prompt semantic recall。
- CRUD/import/delete/eraseAllData 的正式维护 wiring。
