# 06. Phase D - CRUD / Import / Delete Wiring

## 目标

让世界书条目的生命周期与 embedding/meta 保持一致，同时不因 embedding 失败破坏用户保存世界书内容。

## D1. Save / Update Entry

当前 `WorldBookEditorViewModel.saveEntry(_:)` 只调用 `databaseManager.saveWorldBookEntry(entry)`。

目标：

1. 保存 entry record。
2. 判断 title / keywords / content 是否导致 hash stale。
3. 若可立即 index，则调用 `WorldBookEmbeddingIndexer.index(entry:)`。
4. 若 index 失败，保留 entry，meta 写 `failed` 或 `needs_rebuild`，UI 可展示 non-blocking warning。
5. 修改 priority / isEnabled / position 不强制重建 embedding。

实现可选策略：

- Simple first pass：保存后总是调用 `index(entry:)`，由 indexer 自行 skip fresh。
- 更省电策略：保存前读取旧 meta/entry 判断是否 stale，再决定是否 index。

验收优先选择 simple first pass，减少漏判。

## D2. Import Batch

当前 `WorldBookEditorView` import 逻辑逐条 `viewModel.saveEntry(entry)`。

目标：

- 添加 ViewModel 批量方法，例如 `importEntries(_ parsedEntries:)`。
- 先保存 worldBook，再批量插入 entries。
- 批量调用 `WorldBookEmbeddingIndexer.index(entries:)`。
- indexing 失败不回滚导入内容；结果以 error/warning 状态展示。
- 大批量 import 不应每条都刷新 `entries`；保存后统一 `loadEntries()`。

建议接口：

```swift
func importEntries(_ parsedEntries: [WorldBookImportFormat.ParsedEntry]) async throws -> WorldBookImportResult
```

`WorldBookImportResult` 至少包含：

- imported count。
- indexed count。
- failed indexing count。
- warnings。

## D3. Existing WorldBook Rebuild Entry

为了满足“兼容已经导入的世界书，可以把现在的世界书进行向量化”，必须提供明确入口。

推荐两层：

- Core method：`WorldBookEmbeddingIndexer.rebuildAllMissingOrStale(limit: nil)`。
- UI/operational entry：Settings / Data Management 中新增 “Rebuild World Book Semantic Index”。

UI 要求：

- 文案进入 `Localizable.xcstrings`。
- 显示 running 状态，避免重复点击。
- 完成后显示 indexed / skipped / failed counts。
- 失败时显示可理解错误，不使用 `try?`。

如果本轮不做 UI，也必须至少在 docs 和 tests 中证明 Core method 可把旧 entries backfill；但最终产品验收建议包含手动入口。

## D4. Delete Entry / WorldBook

当前：

```swift
func deleteWorldBook(id: String) async throws
func deleteWorldBookEntry(id: String) async throws
```

目标同事务显式清理：

```text
deleteWorldBookEntry(id):
  DELETE FROM world_book_entry_embedding WHERE entry_id = ?
  DELETE FROM world_book_entry_embedding_meta WHERE entryId = ?
  DELETE FROM world_book_entry WHERE id = ?

deleteWorldBook(id):
  DELETE FROM world_book_entry_embedding
    WHERE entry_id IN (SELECT id FROM world_book_entry WHERE worldBookId = ?)
  DELETE FROM world_book_entry_embedding_meta
    WHERE entryId IN (SELECT id FROM world_book_entry WHERE worldBookId = ?)
  DELETE FROM world_book WHERE id = ?
```

原因：

- `world_book_entry` FK cascade 会删除 entries。
- `world_book_entry_embedding_meta` 可以 FK cascade。
- sqlite-vec virtual table 不应依赖 FK cascade，必须显式清理。

## D5. eraseAllData

`DatabaseManager.eraseAllData(...)` 目标顺序：

```text
DELETE FROM memory_embedding
DELETE FROM world_book_entry_embedding
DELETE FROM world_book_entry_embedding_meta
MessageRecord.deleteAll
ConversationRecord.deleteAll
WorldBookEntryRecord.deleteAll
WorldBookRecord.deleteAll
CharacterCardRecord.deleteAll
...
```

如果 preserveEndpoints = false，endpoint 删除逻辑保持现状。

## D6. Error Policy

普通保存：

- entry 保存失败：阻止 dismiss，显示错误。
- embedding/index 失败：entry 保存成功；显示 warning 或记录 rebuild state；keyword fallback 仍可用。

显式 rebuild：

- rebuild 失败数必须反馈给用户。
- 单条失败不应终止整个 rebuild。
- full result 写入 harness evidence。

Chat 召回：

- semantic index unavailable：fallback keyword-only。
- keyword-only fallback 不应降低当前 prompt 兼容性。

## D7. Tests

新增/更新：

- `WorldBookEditorViewModelTests.test_save_entry_indexes_or_marks_rebuild`
- `WorldBookEditorViewModelTests.test_import_entries_batches_save_and_index`
- `DatabaseManagerWorldBookTests.test_delete_world_book_entry_removes_embedding_and_meta`
- `DatabaseManagerWorldBookTests.test_delete_world_book_removes_all_entry_embeddings_and_meta`
- `DatabaseManagerWorldBookTests.test_erase_all_data_removes_world_book_embeddings`
- `CriticalSaveFlowTests` 如涉及 editor dismiss，要保持可见错误策略不回退。

Phase D focused command：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/WorldBookEditorViewModelTests' '-only-testing:OpenChatTests/DatabaseManagerWorldBookTests' '-only-testing:OpenChatTests/CriticalSaveFlowTests'
```
