# 03. Phase 5A：`memory_entry_link` 持久化

## 目标

为 reflect observation 建立可审计的 basedOn 持久化，先解决“新 observation 必须能追溯到哪些原始记忆”的问题。

## Schema

追加新 migration，当前最新 migration 是 v16，因此建议：

```text
v17_create_memory_entry_link
```

表结构：

```text
memory_entry_link
  id TEXT PRIMARY KEY
  fromMemoryEntryId TEXT NOT NULL REFERENCES memory_entry(id) ON DELETE CASCADE
  toMemoryEntryId TEXT NOT NULL REFERENCES memory_entry(id) ON DELETE CASCADE
  relation TEXT NOT NULL
  createdAt DATETIME NOT NULL
```

建议索引：

- `idx_memory_entry_link_fromMemoryEntryId`
- `idx_memory_entry_link_toMemoryEntryId`
- `idx_memory_entry_link_relation`

## Record

新增：

```text
OpenChat/Core/Database/Records/MemoryEntryLinkRecord.swift
```

字段命名与 Swift 现有风格一致：

```swift
struct MemoryEntryLinkRecord: Codable, FetchableRecord, MutablePersistableRecord, Sendable, Equatable {
    static let databaseTableName = "memory_entry_link"

    var id: String
    var fromMemoryEntryId: String
    var toMemoryEntryId: String
    var relation: String
    var createdAt: Date
}
```

可提供 computed value：

```swift
var relationValue: MemoryEntryLinkRelation {
    MemoryEntryLinkRelation(rawValue: relation) ?? .summarizes
}
```

如果不希望 fallback 掩盖非法数据，可在 DB 写入 API 中先 validate relation。

## Database API

在 `DatabaseManager+Memory.swift` 增加最小 API：

```swift
func saveMemoryEntryLinks(_ links: [MemoryEntryLinkRecord]) async throws
func fetchMemoryEntryLinks(fromMemoryEntryId: String) async throws -> [MemoryEntryLinkRecord]
func fetchMemoryEntryLinks(toMemoryEntryId: String) async throws -> [MemoryEntryLinkRecord]
func fetchMemoryEntryLinks(memoryEntryIds: [String]) async throws -> [MemoryEntryLinkRecord]
```

如 5C 需要原子 apply，可以再加 transaction helper：

```swift
func saveMemoryWithEmbeddingAndLinks(
    entry: MemoryEntryRecord,
    embedding: [Float],
    links: [MemoryEntryLinkRecord]
) async throws
```

但该 helper 如果触碰 sqlite-vec embedding insert，应优先放在 `VectorStore` 或复用现有 vector write 风格，避免 `DatabaseManager` 重复 embedding blob 细节。

## Validation

写入前必须验证：

- `fromMemoryEntryId` 非空。
- `toMemoryEntryId` 非空。
- `fromMemoryEntryId != toMemoryEntryId`。
- `relation` 属于 `MemoryEntryLinkRelation.allCases`。
- link 数组去重，避免同一 from/to/relation 重复写入。

## Tests

新增 / 更新：

- `MigrationTests`
  - 验证 v17 后 table 和 indexes 存在。
  - 验证 FK cascade：删除 source / observation memory 后 link 被清理。
- `DatabaseManagerMemoryTests`
  - save / fetch by from。
  - fetch by to。
  - batch fetch。
  - invalid relation 不写入。
- `MemoryReflectModelsTests`
  - relation raw values 与 schema 文档一致。

## 红线

- 不改 v1-v16 migration。
- 不把 link relation 扩成未审计的大集合。
- 不让 link table 承担 conversation graph / character relationship graph。
- 不在 5A 写 LLM executor。
- 不改 Chat / Prompt / Background runtime。

## 验收命令

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MigrationTests' '-only-testing:OpenChatTests/DatabaseManagerMemoryTests' '-only-testing:OpenChatTests/MemoryReflectModelsTests'
```

## 写回要求

- `arch/modules/memory/data-model.md` 增加 `memory_entry_link` 当前实现证据。
- `arch/modules/memory/hindsight-lite.md` 将 link 从规划移入当前事实，前提是源码和测试已落地。
- Harness 记录 migration 名称、测试命令、结果和 schema diff。
