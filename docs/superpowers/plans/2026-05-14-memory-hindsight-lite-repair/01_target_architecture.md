# 01. 目标架构

## 最小目标

Hindsight-lite 的本轮目标是把 Memory 改成“排序可靠、来源可追踪、召回可解释”的本地轻量系统，而不是引入远端 daemon 或每轮 reflect。

本计划包的架构边界是 Memory service。世界书向量化与 BackgroundWorker 统一调度属于后续独立计划包；本包只保证 Memory 的 retain / recall 输出将来能被包装成 Background source/tool。

```text
Retain v2
  messages + character summary + existing memory hints
  -> extraction prompt v2
  -> content/type/importance + source/dedupe metadata
  -> memory_entry + memory_entry_provenance + memory_embedding

Recall v2
  current input
  -> semantic candidates
  -> keyword candidates
  -> recent high-value candidates
  -> rank fusion
  -> MemoryRecallResult(entries, trace)
  -> current [Memories] compatibility output
  -> future MemoryBackgroundSource adapter boundary

Reflect v1
  selected memory cluster
  -> explicit user/debug action or low-frequency background task
  -> observation with basedOn ids
  -> no silent deletion / no per-turn call
```

## 非目标

- 不改变 API Key / settings / compression checkpoint 主线。
- 不把 Background 架构文档写成当前实现。
- 不让 reflect 每轮参与聊天生成。
- 不让 `PromptAssembler` 理解 semantic distance 或 fallback 细节。
- 不自动删除旧 memory 或静默覆盖冲突条目。
- 不伪造 provider 没返回的模型置信分数；`confidence` 只表示 extraction output 自报字段。
- 不实现世界书向量化。
- 不实现 `Core/Background`、`BackgroundWorker`、`BackgroundPacket` 或 PromptAssembler-to-BackgroundPacket 切换。

## 关键 contract

### Recall ordering

Memory recall 输出顺序就是当前 Memory 相关性顺序。兼容旧链路时，`MemoryManager.retrieveMemories(...)` 返回该顺序，`PromptAssembler.trim(memories:)` 只能按输入顺序裁剪，不能按 `importance` 重排。未来 Background 接入时，`MemoryBackgroundSource` 应复用同一有序结果。

### Recall trace

新增内部 DTO，先不要求 UI 全展示：

```swift
struct MemoryRecallResult: Sendable {
    let entries: [MemoryRecallEntry]
    let trace: MemoryRecallTrace
}

struct MemoryRecallEntry: Sendable {
    let memory: MemoryEntryRecord
    let finalRank: Int
    let semanticRank: Int?
    let semanticDistance: Float?
    let keywordRank: Int?
    let recencyRank: Int?
    let reasons: [MemoryRecallReason]
}

struct MemoryRecallTrace: Sendable {
    let query: String
    let semanticCandidateCount: Int
    let keywordCandidateCount: Int
    let recentCandidateCount: Int
    let selectedIds: [String]
    let omitted: [MemoryRecallOmission]
    let fallback: MemoryRecallFallback?
}
```

兼容要求：`retrieveMemories(...) -> [MemoryEntryRecord]` 可以保留，内部调用 `recallMemories(...)` 后返回 `entries.map(\.memory)`。

### Fallback tiers

| 场景 | 行为 |
|---|---|
| semantic available + hits | semantic 为主，keyword / recent high-value 只补充 |
| semantic unavailable | keyword + recent high-value，trace 标记 `semanticUnavailable` |
| semantic no hit | keyword 优先；没有 keyword 时只返回少量 relationship / summary / high importance |
| empty index | 返回空，不伪造 recent |
| budget dropped | 不补 recent；trace 记录 omitted |

### Retain provenance

第一批使用 companion table：

```text
memory_entry_provenance
  memoryEntryId TEXT PRIMARY KEY
  sourceStartSortOrder INTEGER
  sourceEndSortOrder INTEGER
  sourceMessageIds TEXT
  extractionModel TEXT
  extractionPromptVersion TEXT
  confidence REAL
  dedupeKey TEXT
  tags TEXT
  createdAt DATETIME
  updatedAt DATETIME
```

旧 `memory_entry` 没有 provenance 时仍能检索、展示和删除。

### Background Adapter Boundary / Responses

本轮不实现 BackgroundWorker，只建立 Memory 可包装边界：

- `MemoryRecallResult` 后续能包装成 `BackgroundCandidate(sourceType: .memory)`。
- Memory 不引入对 `Core/Background` 的源码依赖；adapter 类型最多作为 doc-level sketch 或后续计划输入。
- Responses API request shape 需要测试确认当前 `[Memories]` 不丢失。
- `arch/modules/api-client.md` 或 memory docs 必须说明 system folding 的实际影响。
