# 05. Phase C：Retain v2 与 Provenance

## 目标

让自动抽取出的 memory 具备来源、prompt 版本、dedupe 和基本可审计 metadata，关闭 AE 中“提取 prompt 缺 source / dedupe”的 P2。

## 状态：已完成

## C1：Migration 与 Record

追加 v14 migration，不修改旧 migration：

```text
v14_create_memory_entry_provenance
```

已创建表：

```text
memory_entry_provenance
  memoryEntryId TEXT PRIMARY KEY REFERENCES memory_entry(id) ON DELETE CASCADE
  sourceStartSortOrder INTEGER
  sourceEndSortOrder INTEGER
  sourceMessageIds TEXT
  extractionModel TEXT
  extractionPromptVersion TEXT NOT NULL DEFAULT 'v1'
  confidence REAL
  dedupeKey TEXT
  tags TEXT
  createdAt DATETIME NOT NULL
  updatedAt DATETIME NOT NULL
```

新增文件：

- `OpenChat/Core/Database/Records/MemoryEntryProvenanceRecord.swift`

实际实现把 provenance CRUD 放在现有 `OpenChat/Core/Database/DatabaseManager+Memory.swift` 中，而非新建 `DatabaseManager+MemoryProvenance.swift`。

约束：

- `sourceMessageIds`、`tags` 使用 JSON array 字符串，沿用现有 `RecordCoders` 风格。
- 旧 memory 没 provenance 时所有现有查询和 UI 继续可用。

## C2：Extraction prompt v2

修改 `MemoryManager.callExtractionAPI(...)`：

输入不再是纯文本拼接，而是 JSON-ish structured content：

```json
{
  "character": {
    "id": "...",
    "name": "...",
    "summary": "..."
  },
  "existingMemoryHints": [
    { "id": "...", "content": "...", "type": "relationship" }
  ],
  "messages": [
    { "id": "...", "sortOrder": 12, "role": "user", "content": "..." }
  ]
}
```

需要从 DB 读取：

- 当前 `CharacterCardRecord` 的名称和简短描述字段。
- 同角色少量 existing memory hints，优先 relationship / summary / high importance。

输出兼容 v1，但支持 v2 字段：

```json
[
  {
    "content": "Brief memory text",
    "type": "event|fact|relationship|summary",
    "importance": 80,
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

## C3：Parser 与 Validation

扩展 `ExtractedMemory`：

- v1 字段缺失仍按当前规则 fallback。
- `sourceStartSortOrder` / `sourceEndSortOrder` 必须在本批 message sortOrder 范围内；越界则不写 provenance 或丢弃该条，测试要明确。
- `sourceMessageIds` 必须是本批 ids 子集；否则过滤无效 id。
- `confidence` clamp 到 `0...1`。
- `tags` 去空、去重、限制数量。
- `action == skip` 不写 memory。
- `action == reinforce` 第一版不覆盖旧 memory，可记录 trace / provenance 或跳过插入。

## C4：同批 Dedupe

第一版只做低风险 dedupe：

- 同一 extraction response 中 `dedupeKey` 相同：保留 importance 更高；importance 相同保留 content 更短。
- 没有 `dedupeKey` 时可用 normalized content 作为临时 key。
- 不自动删除旧 memory。

跨批 dedupe 可先只通过 existing memory hints 让 LLM 返回 `skip/reinforce`，不做破坏性合并。

## C5：原子写入

当前 `MemoryVectorStore.insert(entries:)` 只接收 memory + embedding。引入 provenance 后有两种可行方案：

1. 新增 `MemoryManager` 内部 DB transaction，保存 entry、provenance、embedding。
2. 扩展 `MemoryVectorStore` 支持 provenance payload。

推荐方案 1 的变体：新增 `VectorStore.insert(entries:provenanceByEntryId:)` 或 `DatabaseManager` transaction helper，保证三者同事务。不要先写 memory/provenance 再异步写 embedding。

## 测试

全部已覆盖并验证通过：

- migration 新表列存在，外键 cascade 删除 provenance。
- 旧 `memory_entry` 无 provenance 仍能 fetch / search / delete。
- v1 extraction JSON 仍可解析。
- v2 extraction JSON 解析 source range、ids、confidence、tags、dedupeKey、action。
- 越界 source range 丢弃，不写入 provenance。
- 同批重复 dedupe 后只写一条。
- embedding/vector 失败时不留下 entry/provenance 半成品。

## 验收

Focused tests：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MemoryManagerRetrievalTests' '-only-testing:OpenChatTests/VectorStoreTests' '-only-testing:OpenChatTests/PromptAssemblerTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests' '-only-testing:OpenChatTests/MemoryExtractionParsingTests' '-only-testing:OpenChatTests/DatabaseManagerMemoryTests' '-only-testing:OpenChatTests/MigrationTests'
```

结果：107 tests / 7 suites passed，`** TEST SUCCEEDED **`。

Full suite：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

结果：244 tests / 45 suites passed，`** TEST SUCCEEDED **`。

## 实现证据

- `OpenChat/Core/Database/Records/MemoryEntryProvenanceRecord.swift`
- `OpenChat/Core/Database/Migrations.swift`：`v14_create_memory_entry_provenance`
- `OpenChat/Core/Database/DatabaseManager+Memory.swift`：provenance CRUD
- `OpenChat/Core/Memory/VectorStore.swift`：`insert(entries:provenances:)`
- `OpenChat/Core/Memory/MemoryDependencies.swift`：`MemoryVectorStore` 协议扩展
- `OpenChat/Core/Memory/MemoryManager.swift`：结构化提取、v2 解析、dedupe、validation、provenance 生成
- `OpenChatTests/Core/MemoryTests/MemoryManagerRetrievalTests.swift`
- `OpenChatTests/Core/MemoryExtractionParsingTests.swift`
- `OpenChatTests/Core/DatabaseTests/MigrationTests.swift`

已更新：

- `arch/modules/memory/data-model.md`
- `arch/modules/memory/extraction.md`
- `arch/modules/memory/hindsight-lite.md`
- `arch/modules/memory/index.md`
- `arch/modules/memory/testing.md`
- `arch/AntiEntropy/problem.md`
- `arch/AntiEntropy/triangle-consistency.md`
- `arch/AntiEntropy/propagation-audit.md`
- `harness/2026.05.14/memory-hindsight-lite-repair/index.md`
- `harness/2026.05.14/memory-hindsight-lite-repair/evidence.txt`
