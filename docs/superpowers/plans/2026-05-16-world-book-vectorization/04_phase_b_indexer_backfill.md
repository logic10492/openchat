# 04. Phase B - Indexer 与 Existing WorldBook Backfill

> 状态：已实施并通过 focused/broader focused tests（2026-05-16）。

## 目标

把当前已经存在的世界书条目向量化，并提供后续 CRUD/import 可复用的增量重建能力。

## B1. Embedding Text Builder

新增 `WorldBookEmbeddingTextBuilder`：

```swift
enum WorldBookEmbeddingTextBuilder {
    static func text(for entry: WorldBookEntryRecord) throws -> String
}
```

输出：

```text
Title: {trimmed title}
Keywords: {decoded keywords joined by ", "}
Content:
{trimmed content}
```

要求：

- keywords decode 失败必须抛 `WorldBookError.invalidKeywords(...)`，不要把坏 JSON 当空数组静默索引。
- 空 keywords 可以索引，文本中保留 `Keywords:` 空值；keyword trigger fallback 仍按现有规则处理。
- title/content trim 后参与 hash 与 embedding；原 record 不被 builder 修改。

## B2. Content Hash

新增 `WorldBookEntryHasher`：

```swift
enum WorldBookEntryHasher {
    static func hash(embeddingText: String, modelId: String, dimension: Int) -> String
}
```

实现建议复用 `CryptoKit.SHA256` 风格，与 `CompressionSourceHasher` 保持一致。

hash 输入必须包含：

- embedding text。
- embedding model id，例如 `multilingual-e5-small-384:v1`。
- dimension `384`。

不进入 hash：

- `priority`
- `isEnabled`
- `position`
- `updatedAt`

原因：这些字段影响召回过滤/排序或旧数据兼容，不代表语义向量文本变化。

## B3. WorldBookEmbeddingIndexer

新增 `WorldBookEmbeddingIndexer`：

```swift
struct WorldBookEmbeddingIndexer: Sendable {
    func index(entry: WorldBookEntryRecord) async throws -> WorldBookIndexingResult
    func index(entries: [WorldBookEntryRecord]) async throws -> WorldBookIndexingBatchResult
    func rebuildMissingOrStale(worldBookId: String, limit: Int?) async throws -> WorldBookIndexingBatchResult
    func rebuildAllMissingOrStale(limit: Int?) async throws -> WorldBookIndexingBatchResult
    func markNeedsRebuild(entryId: String, reason: WorldBookIndexRebuildReason) async throws
}
```

结果 DTO 建议：

```swift
struct WorldBookIndexingBatchResult: Sendable {
    let indexedCount: Int
    let skippedFreshCount: Int
    let failed: [WorldBookIndexingFailure]
}
```

执行流程：

1. 读取 entry。
2. 构造 embedding text。
3. 计算 content hash。
4. 如果 meta 是 `indexed` 且 hash/model/dimension 都一致，跳过。
5. 调 `embeddingProvider.embed(text, isQuery: false)`。
6. `WorldBookVectorStore.upsert(...)` 写 vector。
7. 保存 meta 为 `indexed`，记录 `embeddedAt` / `lastAttemptAt`。
8. 失败时保存 meta 为 `failed` 或 `needs_rebuild`，记录 `lastError`，但不删除用户的 `world_book_entry`。

事务边界：

- embedding 计算不放在 DB transaction 里。
- vector upsert + meta indexed 写入应尽量在同一 `databaseManager.write` 内完成。
- 批量 index 允许单条失败后继续处理下一条，结果中汇总失败；显式 rebuild UI 需要展示失败数。

## B4. Existing WorldBook Backfill

迁移后的旧数据兼容策略：

- 所有没有 meta 的 `world_book_entry` 视为 missing。
- `rebuildAllMissingOrStale(limit: nil)` 全量扫描现有世界书并向量化。
- `rebuildMissingOrStale(worldBookId:limit:)` 只处理当前世界书，可用于 Chat 召回前的 bounded lazy rebuild。
- 大批量导入后可以调用 `index(entries:)`，不用等下一轮 lazy rebuild。

不要在 migration 中直接 backfill，原因：

- migration 不能加载 CoreML / tokenizer。
- migration 必须快速、可重复、可测试。
- embedding model 失败不应阻塞数据库打开。

## B5. DependencyContainer

建议让 Memory 与 WorldBook 共享 embedding service：

```swift
let embeddingService = EmbeddingService()
memoryManager = MemoryManager(... embeddingService: embeddingService, ...)
worldBookEmbeddingIndexer = WorldBookEmbeddingIndexer(... embeddingProvider: embeddingService, ...)
```

测试注入 fixed/failing embedding provider，避免真实 CoreML。

## B6. Tests

新增：

- `WorldBookEmbeddingTextBuilderTests.test_text_includes_title_keywords_and_content`
- `WorldBookEntryHasherTests.test_hash_is_stable_for_same_text_model_dimension`
- `WorldBookEntryHasherTests.test_hash_changes_when_title_keywords_or_content_change`
- `WorldBookEntryHasherTests.test_hash_does_not_change_when_priority_or_position_change`
- `WorldBookEmbeddingIndexerTests.test_rebuild_indexes_existing_entries_without_meta`
- `WorldBookEmbeddingIndexerTests.test_rebuild_skips_fresh_meta`
- `WorldBookEmbeddingIndexerTests.test_rebuild_reindexes_hash_mismatch`
- `WorldBookEmbeddingIndexerTests.test_failed_embedding_records_failed_meta_without_deleting_entry`
- `WorldBookEmbeddingIndexerTests.test_invalid_keywords_records_failed_meta_without_embedding`
- `WorldBookEmbeddingIndexerTests.test_batch_rebuild_continues_after_single_entry_failure`

Phase B focused command：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/WorldBookEmbeddingTextBuilderTests' '-only-testing:OpenChatTests/WorldBookEntryHasherTests' '-only-testing:OpenChatTests/WorldBookEmbeddingIndexerTests'
```

验证结果：12 tests / 3 suites passed，`** TEST SUCCEEDED **`。

Broader focused command：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MigrationTests' '-only-testing:OpenChatTests/VectorStoreTests' '-only-testing:OpenChatTests/WorldBookVectorStoreTests' '-only-testing:OpenChatTests/WorldBookEmbeddingTextBuilderTests' '-only-testing:OpenChatTests/WorldBookEntryHasherTests' '-only-testing:OpenChatTests/WorldBookEmbeddingIndexerTests' '-only-testing:OpenChatTests/PromptAssemblerTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests'
```

验证结果：84 tests / 8 suites passed，`** TEST SUCCEEDED **`。

Full suite command：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,id=2277CB75-AF36-4ABF-84EE-7444C1DD6759'
```

验证结果：实际设备 iOS 26.5 `iPhone 17`，273 tests / 50 suites passed，`** TEST SUCCEEDED **`。同日一次 `iPhone 17 Pro` full-suite 尝试在测试体执行前被 Simulator 拒绝启动，错误为 `Busy ("Application failed preflight checks")`。
