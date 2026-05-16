# 01. Target Architecture

## 模块边界

新增 `Core/WorldBook/`，放在 Core 层，供 Features/Chat 与 Features/WorldBook 的 ViewModel 通过依赖注入调用。2026-05-16 Phase A/B/C 已落地 `WorldBookError.swift`、`WorldBookRecallModels.swift`、`WorldBookVectorStore.swift`、`WorldBookEmbeddingTextBuilder.swift`、`WorldBookEntryHasher.swift`、`WorldBookEmbeddingIndexer.swift` 与 `WorldBookSource.swift`。

```text
OpenChat/Core/WorldBook/
  WorldBookRecallModels.swift
  WorldBookEmbeddingTextBuilder.swift
  WorldBookEntryHasher.swift
  WorldBookVectorStore.swift
  WorldBookEmbeddingIndexer.swift
  WorldBookSource.swift
  WorldBookError.swift
```

建议职责：

| 文件 | 职责 |
|---|---|
| `WorldBookRecallModels.swift` | `WorldBookEmbeddingStatus`、`WorldBookRecallResult`、candidate、trace、reason、omission DTO |
| `WorldBookEmbeddingTextBuilder.swift` | 稳定拼接 title / keywords / content，供 hash 和 embedding 使用 |
| `WorldBookEntryHasher.swift` | 对 embedding text + model id 生成稳定 hash |
| `WorldBookVectorStore.swift` | `world_book_entry_embedding` CRUD 与 KNN 查询 |
| `WorldBookEmbeddingIndexer.swift` | 单条、批量、missing/stale、all scope rebuild |
| `WorldBookSource.swift` | keyword candidates + semantic candidates 融合 |
| `WorldBookError.swift` | typed `LocalizedError`，避免抛泛 `Error` |

## Schema

追加 migration，不修改 v1-v14。Phase A 已实现 v15/v16。

```text
v15_create_world_book_entry_embedding
  CREATE VIRTUAL TABLE world_book_entry_embedding USING vec0(
    entry_id TEXT PRIMARY KEY,
    embedding float[384]
  )

v16_create_world_book_entry_embedding_meta
  entryId TEXT PRIMARY KEY
  contentHash TEXT NOT NULL
  embeddingModel TEXT NOT NULL
  embeddingDimension INTEGER NOT NULL
  status TEXT NOT NULL           -- indexed / needs_rebuild / failed
  embeddedAt DATETIME            -- status=indexed 时写入
  lastAttemptAt DATETIME
  lastError TEXT
  updatedAt DATETIME NOT NULL
```

约束：

- migration 内使用 migration-local historical constants，不引用 runtime Record / enum / `EmbeddingService.embeddingDimension`。
- `world_book_entry_embedding` 是 sqlite-vec virtual table，必要 SQL 沿用 `VectorStore` 的例外做法。
- `world_book_entry_embedding_meta` 使用 GRDB Record：`WorldBookEntryEmbeddingMetaRecord`。
- meta 的 `entryId` 应 references `world_book_entry(id) ON DELETE CASCADE`，但不能依赖它清理 virtual table；源码 delete path 仍必须显式删 embedding。

## Embedding Text

该部分已在 Phase B 实现。

世界书条目 embedding 不是只 embed `content`，而是稳定拼接：

```text
Title: {title}
Keywords: {keywords joined by ", "}
Content:
{content}
```

规范：

- title / keywords / content trim whitespace。
- keywords 从 `world_book_entry.keywords` JSON decode；decode 失败时 indexer 标记 failed，不吞错误。
- hash 使用上述 normalized text + `embeddingModel` + dimension。
- priority、isEnabled、position 不进入 content hash；它们影响召回过滤/排序，不代表 embedding 文本变化。

## Indexer Scope

该部分已在 Phase B 实现。

`WorldBookEmbeddingIndexer` 至少提供：

```swift
struct WorldBookEmbeddingIndexer: Sendable {
    func index(entry: WorldBookEntryRecord) async throws -> WorldBookIndexingResult
    func index(entries: [WorldBookEntryRecord]) async throws -> WorldBookIndexingBatchResult
    func markNeedsRebuild(entryId: String, reason: WorldBookIndexRebuildReason) async throws
    func rebuildMissingOrStale(worldBookId: String, limit: Int?) async throws -> WorldBookIndexingBatchResult
    func rebuildAllMissingOrStale(limit: Int?) async throws -> WorldBookIndexingBatchResult
}
```

已有世界书兼容：

- migration 后，旧 `world_book_entry` 没有 meta；它们自然属于 missing。
- `rebuildAllMissingOrStale(limit: nil)` 可以把当前数据库所有世界书条目向量化。
- 当前聊天使用的 worldBook 可在 recall 前做 bounded lazy rebuild，例如只处理该 worldBook 的 missing/stale 前 N 条，避免阻塞过久。
- 显式全量重建入口可放到 Settings / Data Management；这是用户手动把现有世界书向量化的可靠路径。

## Recall Source

该部分已在 Phase C 实现。

`WorldBookSource` 输入当前 worldBook、条目范围、最近历史和当前输入，输出 keyword + semantic 融合结果：

```swift
struct WorldBookRecallResult: Sendable {
    let entries: [WorldBookRecallEntry]
    let trace: WorldBookRecallTrace
}

struct WorldBookRecallEntry: Sendable {
    let entry: WorldBookEntryRecord
    let finalRank: Int
    let keywordRank: Int?
    let semanticRank: Int?
    let semanticDistance: Float?
    let keywordHits: [String]
    let reasons: [WorldBookRecallReason]
}
```

融合原则：

- `worldBook.isEnabled == false` 时返回空。
- `entry.isEnabled == false` 时 hard filter。
- keyword hit 是强 boost，但 semantic-only entry 可以进入候选池。
- `priority` 是排序信号，不是唯一入口。
- 同一 entry 同时被 keyword 和 semantic 命中时去重，合并 reasons 和 trace。
- KNN 必须限定当前 worldBook 的 entries，不能跨世界书。
- embedding/vector 失败时 fallback 到 keyword-only，不影响当前 prompt 基本可用性。

## Prompt 兼容

第一阶段不改变输出文本形态：

```text
[World Book Entries]
[World Book: ...]
...
[/World Book Entries]
```

实现策略：

- `ChatViewModel.generateResponse(...)` 从 `WorldBookSource` 获取 recall result。
- `PromptAssembler.preview(...)` / `assemble(...)` 接收已经预选和排序过的 worldBook entries，或新增兼容参数保存 trace。
- `PromptAssembler` 保持纯函数，不访问 DB、不调用 embedding、不做 KNN。
- 为兼容现有测试和调用方，可以保留 keyword-only fallback path；但 Chat 主链路应使用 `WorldBookSource`。

当前 Phase C 源码已执行上述 prompt 接入；`PromptAssembler` 保留旧 keyword fallback，但 Chat 主链路使用 preselected path，semantic-only world book entry 可以进入 prompt。

## 与未来 Background 的关系

本计划输出的 DTO 应尽量接近后续 `BackgroundCandidate`，但不引入 `Core/Background` 源码依赖。

后续 Background 接入时，`WorldBookRecallEntry` 可包装为：

```text
BackgroundCandidate(
  sourceType: worldBook,
  sourceId: entry.id,
  content: PromptAssembler.makeWorldBookMessageContent(entry),
  basePriority: entry.priority,
  relevance: semanticDistance / normalized score,
  metadata: keywordHits, semanticRank, contentHash
)
```

当前阶段验收只看 `[World Book Entries]` block，不看 `[Background]` block。
