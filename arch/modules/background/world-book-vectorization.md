# 世界书向量化

> 状态：Phase A schema + vector store 已实现；Phase B embedding text/hash/indexer/backfill 已实现；Phase C `WorldBookSource` keyword + semantic recall 和 Chat prompt 兼容接入已实现；Phase D CRUD/import/delete/eraseAllData 与手动 rebuild 入口已实现。2026-05-17 Phase 5/6 已实现 BackgroundWorker / BackgroundPacket 统一调度与 Chat/Prompt compatible switch；统一 `[Background]` block 尚未启用。

## 1. 为什么需要向量化

当前世界书靠关键词触发，Memory 靠语义检索。两套召回方式分离时，BackgroundWorker 很难公平地比较“一个语义相关的记忆”和“一个关键词命中的世界书条目”。

世界书向量化后，WorldBook 与 Memory 都能作为 semantic candidates 进入同一调度层：

```text
currentInput -> query embedding
  -> Memory KNN
  -> WorldBook KNN
  -> keyword trigger
  -> BackgroundWorker fusion
```

## 2. 当前表

当前已追加 migration：

```sql
CREATE VIRTUAL TABLE world_book_entry_embedding USING vec0(
    entry_id TEXT PRIMARY KEY,
    embedding float[384]
);
```

可审计增量重建使用普通表：

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

当前实现证据：

- `OpenChat/Core/Database/Migrations.swift`：`v15_create_world_book_entry_embedding`、`v16_create_world_book_entry_embedding_meta`。
- `OpenChat/Core/Database/Records/WorldBookEntryEmbeddingMetaRecord.swift`：meta Record。
- `OpenChat/Core/WorldBook/WorldBookEmbeddingTextBuilder.swift`：stable title/keywords/content embedding text。
- `OpenChat/Core/WorldBook/WorldBookEntryHasher.swift`：embedding text + model id + dimension 的 content hash。
- `OpenChat/Core/WorldBook/WorldBookEmbeddingIndexer.swift`：single/batch index、missing/stale rebuild、failed meta、needs-rebuild 标记。
- `OpenChat/Core/WorldBook/WorldBookVectorStore.swift`：upsert/search/delete/deleteAll。
- `OpenChat/Features/WorldBook/ViewModels/WorldBookEditorViewModel.swift`：save/import 后调用 indexer，index 失败保留 entry 并展示 warning。
- `OpenChat/Core/Database/DatabaseManager+Content.swift` / `DatabaseManager.swift`：delete entry、delete worldBook、eraseAllData 显式清理 vector/meta。
- `OpenChat/Features/Settings/ViewModels/SettingsViewModel.swift` / `DataManagementView.swift`：Data Management 手动 rebuild 世界书语义索引。
- `OpenChat/App/DependencyContainer.swift`：Memory 与 WorldBook 共用同一 `EmbeddingService` 实例。
- `OpenChatTests/Core/DatabaseTests/MigrationTests.swift`：v15/v16 schema、索引、cascade 和 migration 源码约束。
- `OpenChatTests/Core/WorldBookTests/WorldBookEmbeddingTextBuilderTests.swift`、`WorldBookEntryHasherTests.swift`、`WorldBookEmbeddingIndexerTests.swift`：Phase B text/hash/indexer/backfill 行为。
- `OpenChatTests/Core/WorldBookTests/WorldBookVectorStoreTests.swift`：KNN 限定 worldBook、disabled entry 过滤、delete、invalid dimension。

## 3. 索引内容

Phase B 当前已实现 embedding text builder。embedding 文本不是单纯 `content`，而是稳定拼接：

```text
Title: {trimmed title}
Keywords: {trimmed keywords joined by ", "}
Content:
{trimmed content}
```

原因：

- title 通常是高价值实体名。
- keywords 是用户显式触发意图。
- content 提供语义细节。

约束：

- `world_book_entry.keywords` JSON decode 失败时抛 `WorldBookError.invalidKeywords(...)`，indexer 会写 `failed` meta，不把坏 JSON 静默当空数组索引。
- content hash 输入包含 embedding text、`EmbeddingService.embeddingModelId`（当前 `multilingual-e5-small-384:v1`）和维度 384。
- `priority`、`isEnabled`、`position`、`updatedAt` 不进入 hash；它们影响召回过滤/排序或数据兼容，不代表语义向量文本变化。

## 4. 更新时机

Phase B 已实现 Core rebuild/backfill indexer；Phase C 在 Chat 召回前做 bounded lazy rebuild；Phase D 已把 CRUD/import/delete/eraseAllData 和手动 rebuild 接入当前产品路径。

需要在以下场景重建或删除 embedding：

- 创建 world book entry。
- 修改 title / keywords / content。
- 删除 entry。
- 批量导入 world book。
- embedding 模型版本变更。

当前可用 Core entrypoints：

- `WorldBookEmbeddingIndexer.index(entry:)`：单条 index，fresh meta 时跳过。
- `WorldBookEmbeddingIndexer.index(entries:)`：批量 index，单条失败后继续并汇总 failed entries。
- `WorldBookEmbeddingIndexer.rebuildAllMissingOrStale(limit:)`：扫描所有 existing world-book entries，向量化 missing/stale/failed。
- `WorldBookEmbeddingIndexer.rebuildMissingOrStale(worldBookId:limit:)`：限定当前 worldBook，可用于后续 bounded lazy rebuild。
- `WorldBookEmbeddingIndexer.markNeedsRebuild(entryId:reason:)`：可用于后续更细粒度 stale 标记；当前 Phase D save/import 采用 simple first pass，由 indexer 自行 skip fresh。

当前产品路径：

- `WorldBookEditorViewModel.saveEntry(_:)`：先保存 entry，再调用 `index(entry:)`；index 失败只写 warning / failed meta，不回滚用户内容。
- `WorldBookEditorViewModel.importEntries(_:)`：先保存 worldBook 和批量 entries，再调用 `index(entries:)`，最后统一 reload entries。
- `DatabaseManager.deleteWorldBookEntry(id:)` / `deleteWorldBook(id:)`：删除业务 record 前显式清理 `world_book_entry_embedding` 和 meta。
- `DatabaseManager.eraseAllData(...)`：清理 `memory_embedding` 后同步清理 world book vector/meta，再删除 message/conversation/worldBookEntry/worldBook/character。
- `SettingsViewModel.rebuildWorldBookSemanticIndex()`：Data Management 手动调用 `rebuildAllMissingOrStale(limit: nil)`，显示 running 和结果状态。

实现边界：

- embedding 计算不在 DB transaction 内。
- vector upsert + indexed meta 写入在同一个 `DatabaseManager.write` 内。
- 失败时保存 `failed` meta 和 `lastError`，不删除 `world_book_entry`。
- 当前 Chat 召回前会调用 `WorldBookEmbeddingIndexer.rebuildMissingOrStale(worldBookId:limit:)` 做 bounded lazy rebuild；失败只记录 warning，随后仍允许 keyword-only fallback。

## 5. 召回融合

Phase C 已实现 Chat prompt 主链路的最小召回融合；2026-05-17 Phase 5/6 已让 `WorldBookBackgroundSource` candidates 进入 `BackgroundWorker` 统一调度。当前输出仍是同一个 `[World Book Entries]` block，semantic-only 世界书条目可以进入 prompt。

当前 `WorldBookSource` 候选来自两路：

1. keyword trigger
2. semantic KNN

融合规则建议：

- keyword 命中是强 boost，但不是唯一入口。
- semantic 相关但未 keyword 命中的条目可以进入候选池。
- `priority` 是 source 自带权重，不能单独决定是否注入。
- 已禁用 world book 或 entry 不应进入候选池。
- semantic embedding/vector 失败时 trace 记录 `semanticUnavailable`，返回 keyword-only 结果，不阻断当前回复。

## 6. 与现有字段兼容

- `position` 保留为旧数据字段，不再决定最终 prompt 位置。
- `priority` 继续作为排序信号。
- `keywords` 继续用于 trigger 和 embedding text。
- `isEnabled` 继续作为 hard filter。

## 7. 测试建议

- 已实现：migration 创建 `world_book_entry_embedding`。
- 已实现：migration 创建 `world_book_entry_embedding_meta`、status/model 索引和 cascade。
- 已实现：KNN 只返回当前 world book 范围内且 enabled 的 entry。
- 已实现：disabled entry 不返回。
- 已实现：embedding text 包含 title、keywords、content，bad keywords JSON 写 failed meta。
- 已实现：content hash 只随 title/keywords/content/model/dimension 变化；priority/isEnabled/position/updatedAt 不影响 hash。
- 已实现：migration 后 existing `world_book_entry` 可通过 `rebuildAllMissingOrStale` 向量化。
- 已实现：fresh meta 跳过，hash mismatch 重新 index，单条 embedding 失败不删除 entry，batch rebuild 继续后续条目。
- 已实现：keyword-only、semantic-only、keyword+semantic 三类候选融合顺序稳定。
- 已实现：semantic unavailable fallback 到 keyword-only。
- 已实现：semantic-only 世界书条目通过 Chat 主链路进入 `[World Book Entries]` block。
- 已实现：entry 创建/修改后 simple-first-pass index，index 失败保留 entry 并写 warning / failed meta。
- 已实现：import 批量保存后批量 index，单条失败不回滚导入。
- 已实现：delete entry / delete worldBook / eraseAllData 不留下 vector/meta 残留。
- 已实现：Data Management 手动 rebuild 可 backfill existing entries。
- 已实现：BackgroundWorker / BackgroundPacket / BackgroundManager 统一调度；输出仍保持兼容 `[World Book Entries]` block。
- 已实现：Character/ConversationState sources、LibMan offline draft runtime、idle reflect draft worker。
- 未实现：统一 `[Background]` block、Exa ToolBroker、LibMan apply UI、自动 synthesis 写入和 duplicate/conflict review。
