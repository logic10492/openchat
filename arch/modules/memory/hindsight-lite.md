# Hindsight-lite 完善设计

> 状态：Phase A recall ordering、Phase B recall trace / fallback tiers、Phase C retain provenance / dedupe、Phase D reflect contract / Responses request-shape 已实现；2026-05-17 Phase 4-6 已完成 `MemoryRecallTool`、`MemoryBackgroundSource`、`BackgroundWorker` / `BackgroundPacket` 和 Chat-Prompt compatible switch。reflect executor、`memory_entry_link` migration、统一 `[Background]` block 和 Background request-shape audit 仍为后续规划。
> 目标：用轻量 retain / recall / reflect 设计关闭 `arch/AntiEntropy/problem.md` 中剩余的记忆系统问题。

本页参考 Hindsight 论文的三段式操作：retain、recall、reflect。论文把 agent memory 视为可推理的结构化底座，并强调证据、推断和可追踪更新的区别。OpenChat 不需要完整复刻论文中的多网络记忆系统，当前目标是把已有 `memory_entry` / `memory_embedding` 演进成低延迟、可解释、可测试的本地轻量版本。

边界说明：本页只定义 Memory 层完善。世界书向量化与 Background runtime 是独立计划；当前 Memory 输出已可被 `MemoryRecallTool` / `MemoryBackgroundSource` 包装并进入 `BackgroundPacket` 兼容链路，但 reflect executor、`memory_entry_link` 和统一 `[Background]` block 不属于本页已实现范围。

参考：<https://arxiv.org/abs/2512.12818>

## 1. 设计目标

Hindsight-lite 的目标不是增加一个远端 memory daemon，而是在现有 iOS 本地架构上补齐四个缺口：

1. **排序可靠**：当前输入相关性必须优先于 `importance`；Phase A 已关闭 P1 prompt trim 重排问题。
2. **来源可追踪**：每条自动记忆应知道来自哪段消息，降低抽取幻觉和重复污染。
3. **召回可解释**：Phase B 已在 Memory 层记录 fallback、distance threshold、selected ids 和 omitted；debug UI 展示与 prompt budget omission 仍属于后续工作。
4. **整理低频化**：reflect 只用于记忆整理和 observation synthesis，不进入每轮主聊天链路。

## 2. 非目标

- 不在每次用户发送时额外调用 reflect LLM。
- 不让 reflect 生成给用户看的 assistant 回复。
- 不引入远端 Hindsight 服务作为必需运行时。
- 不把同会话 compression checkpoint 替换成长期记忆。
- 不让 `PromptAssembler` 承担 recall rerank。
- 不为 provider 没有返回的字段伪造“模型置信分数”。
- 不把统一 `[Background]` block、Character / ConversationState sources 或 synthesis worker 写成当前已实现能力。
- 不在 Memory 模块内实现世界书向量化、Background source orchestration 或 `BackgroundWorker`。

## 3. 与当前问题的对应关系

| problem.md 条目 | Hindsight-lite 设计动作 | 目标状态 |
|---|---|---|
| P1：Prompt 注入前被 importance 重排 | Phase A：order-preserving trim，排序权归 recall | 已关闭 |
| P2：fallback 和阈值缺少校准与可观测性 | Phase B：`MemoryRecallTrace` + fallback tier | 已实现，UI 展示未做 |
| P2：recent fallback 只按时间取最近 | Phase B：keyword + recent high-value fallback，不盲目注入噪声 | 已实现 |
| P2：提取 prompt 缺少角色卡、已有记忆、source 边界和去重 | Phase C：retain schema + extraction prompt v2 | 已实现 |
| P2：Responses API system folding | Phase D：当前 `[Memories]` request shape audit；统一 `[Background]` block audit 留给后续计划 | 已实现当前 request-shape 验收 |
| P3：检索可观测性不足 | Phase B/D：recall trace 已有内部 contract；debug UI 与 prompt budget omission 后续处理 | 部分实现 |

## 4. 总体架构

```text
Retain
  conversation messages
  -> extraction prompt v2
  -> extracted memory draft
  -> provenance / dedupe metadata
  -> memory_entry + memory_embedding

Recall
  current input
  -> semantic candidates
  -> keyword candidates
  -> recent high-value candidates
  -> rank fusion
  -> ordered MemoryRecallResult
  -> MemoryBackgroundSource BackgroundCandidate(.memory)
  -> BackgroundWorker selected BackgroundPacket entry
  -> current [Memories] compatibility output

Reflect
  selected memory cluster
  -> LLM structured synthesis
  -> observation draft with basedOn ids
  -> user-confirmed or audited write
```

当前 Chat 兼容链路是：

```text
MemoryManager.recallMemories
  -> MemoryRecallTool
  -> MemoryBackgroundSource
  -> BackgroundWorker
  -> BackgroundPacket
  -> PromptAssembler(... backgroundPacket:)
  -> [Memories] system block
```

旧 direct / rollback path 仍保留：

```text
MemoryManager.retrieveMemories
  -> [MemoryEntryRecord]
  -> PromptAssembler.trim(memories:)
  -> [Memories] system block
```

## 5. Phase A：Recall ordering 先行修复

这是最小、最高优先级改动，已于 2026-05-14 落地并关闭当前 P1。

### 5.1 排序所有权

规则：

- `MemoryManager` / `MemoryBackgroundSource` 输出的顺序就是 Memory 内部相关性顺序。
- `PromptAssembler.trim(memories:within:)` 只能按输入顺序裁剪。
- `importance` 只用于同等相关性时的 tie-breaker 或 UI 展示。
- 如果调用方想用不同排序，必须在进入 `PromptAssembler` 前完成。

### 5.2 裁剪行为

建议行为：

```swift
private static func trim(memories: [MemoryEntryRecord], within budget: Int) -> [MemoryEntryRecord] {
    var result: [MemoryEntryRecord] = []
    var used = 0
    for entry in memories {
        let tokens = TokenCounter.count(message: ChatMessage(role: "system", content: makeMemoryMessageContent(entry)))
        guard used + tokens <= budget || result.isEmpty else { break }
        result.append(entry)
        used += tokens
    }
    return result
}
```

测试必须覆盖：

- 输入顺序 `[A, B, C]`，importance 为 `C > B > A`，预算只能容纳两条时，prompt 保留 `[A, B]`。
- `MemoryManager.retrieveMemories(...)` 返回 KNN 顺序时，`PromptAssembler.preview(...)` 不改变该顺序。

实现证据：

- `OpenChat/Core/PromptEngine/PromptAssembler.swift`：`trim(memories:within:)` 对输入 `memories` 原序迭代。
- `OpenChatTests/Core/PromptEngineTests/PromptAssemblerTests.swift`：`test_memory_trim_preserves_retrieval_order_when_budget_drops_high_importance_memory`。
- 2026-05-14 Phase A verification：`PromptAssemblerTests` 14 tests passed；Memory/Vector/Prompt/Chat focused suite 35 tests passed；full suite 219 tests / 45 suites passed。
- 2026-05-15 Phase C verification：focused suite 107 tests / 7 suites passed；full suite 244 tests / 45 suites passed。

## 6. Phase C：Retain schema v2

retain v2 已追加 `memory_entry_provenance` companion table 和结构化提取输入/输出。当前保留 `content/type/importance` 作为主表稳定内容，provenance 元数据独立存储。

### 6.1 最小新增结构

Phase C 已追加 companion table，减少对 `MemoryEntryRecord` 主表和现有 UI 的冲击：

```text
memory_entry_provenance
  memoryEntryId TEXT PRIMARY KEY
  sourceStartSortOrder INTEGER
  sourceEndSortOrder INTEGER
  sourceMessageIds TEXT      // JSON array
  extractionModel TEXT
  extractionPromptVersion TEXT
  confidence REAL
  dedupeKey TEXT
  tags TEXT                  // JSON array
  createdAt DATETIME
  updatedAt DATETIME
```

可选后续表：

```text
memory_entry_link
  id TEXT PRIMARY KEY
  fromMemoryEntryId TEXT
  toMemoryEntryId TEXT
  relation TEXT              // reinforces | contradicts | supersedes | summarizes
  createdAt DATETIME
```

保守原因：

- `memory_entry` 继续保持当前 prompt 注入路径可用。
- Hindsight-lite 元数据可以独立迁移、独立测试（v14 migration）。
- Background 接管 prompt selection 后，主表仍能作为稳定内容表。

实现证据：

- `OpenChat/Core/Database/Records/MemoryEntryProvenanceRecord.swift`
- `OpenChat/Core/Database/Migrations.swift`：`v14_create_memory_entry_provenance`
- `OpenChat/Core/Database/DatabaseManager+Memory.swift`：provenance CRUD
- `OpenChat/Core/Memory/VectorStore.swift`：`insert(entries:provenances:)` 原子写入

### 6.2 Extraction prompt v2

输入已从纯文本：

```text
user: ...
assistant: ...
```

升级为带消息边界的结构：

```json
{
  "character": {
    "name": "...",
    "summary": "short character-card summary"
  },
  "existingMemoryHints": [
    { "id": "...", "content": "...", "type": "relationship" }
  ],
  "messages": [
    { "id": "...", "sortOrder": 12, "role": "user", "content": "..." },
    { "id": "...", "sortOrder": 13, "role": "assistant", "content": "..." }
  ]
}
```

LLM 输出建议：

```json
[
  {
    "content": "Brief memory text",
    "type": "event|fact|relationship|summary",
    "importance": 0,
    "sourceStartSortOrder": 12,
    "sourceEndSortOrder": 13,
    "sourceMessageIds": ["..."],
    "confidence": 0.0,
    "tags": ["relationship"],
    "dedupeKey": "normalized-short-key",
    "action": "insert|reinforce|skip"
  }
]
```

解析策略：

- v2 字段缺失时仍兼容 v1。
- `sourceStartSortOrder` / `sourceEndSortOrder` 必须落在本批消息范围内；否则丢弃该条。
- `sourceMessageIds` 必须是本批 ids 子集；无效 id 会从 provenance 中过滤。
- `confidence` 只表示抽取器自报置信，不参与最终 truth 判定；在 provenance 中 clamp 到 0...1。
- `action == skip` 不写入 DB，只计入 diagnostics。
- `action == reinforce` 第一版不覆盖旧 memory，也不新增重复记忆，直接跳过插入；后续 reflect 计划可扩展 `memory_entry_link`。

### 6.3 去重策略

第一阶段已落地两层去重：

1. **同批去重**：同一 extraction response 内 `dedupeKey` 相同只保留 importance 更高或更短的一条；没有 `dedupeKey` 时用 normalized content 作为临时 key。
2. **近邻去重**：抽取前给 LLM 最近/最相关的 existing memory hints（relationship / summary / high importance，最多 5 条），让它返回 `reinforce` 或 `skip`。

向量近似去重留给后续 reflect 计划。

写入原则：

- 自动流程可以跳过明确重复条目（`action == skip`、越界 source、同批 dedupe）。
- 自动流程不应无声删除旧条目。
- 合并、替换或标记冲突需要 debug trace，必要时交给用户确认。

## 7. Phase B：Recall fusion 与 fallback 分层

### 7.1 Recall result contract

已新增内部 DTO，先不要求 UI 全量展示：

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

`MemoryManager.retrieveMemories(...) -> [MemoryEntryRecord]` 保持兼容，内部使用 result 后只返回 `entries.map(\.memory)`。完整 trace 是 Memory 层能力；当前 `MemoryBackgroundSource` 已读取并包装为 `BackgroundCandidate` metadata，供 `BackgroundWorker` 生成 packet diagnostics。

### 7.2 Candidate sources

当前召回候选：

- semantic：sqlite-vec KNN，search limit 扩大到 `max(limit * 2, 20)`。
- keyword：对 `memory_entry.content` 做简单关键词匹配，后续可迁移到 FTS5。
- recent high-value：最近的 `relationship` / `summary` / 高 importance 记忆，数量小于等于 3。

注意：recent 不是默认兜底塞满 prompt。它只补充高价值上下文。

### 7.3 Rank fusion

当前第一版使用稳定融合规则：

| 信号 | 行为 |
|---|---|
| semantic | 主信号，按 distance 升序 |
| keyword | semantic 后补充；semantic unavailable / no hit 时作为 fallback 主结果 |
| recency | 只补少量 recent high-value；noSemanticHit 且有 keyword 时不额外补 recent |
| importance | keyword tie-breaker 与 recent high-value 筛选条件，不覆盖 semantic order |

### 7.4 Fallback tiers

Phase B 已把旧“语义失败或低相关时取最近 N 条”改成分层：

| fallback | 触发 | 返回 |
|---|---|---|
| `semanticUnavailable` | embedding/model/sqlite-vec 失败 | keyword + recent high-value |
| `noSemanticHit` | semantic 全部超过阈值 | keyword candidates；没有 keyword 时只返回 pinned/high-value relationship summary |
| `emptyIndex` | 角色没有记忆或没有 embedding | 空结果，不伪造 recent |
| `budgetDropped` | 有候选但 prompt 预算不足 | 留给后续 packet diagnostics / prompt budget trace |

这能解决两个体感问题：

- 不相关记忆少进 prompt。
- 相关但非近期的记忆能通过 keyword/semantic 保留下来。

### 7.5 Threshold 校准

`distanceThreshold == 1.5` 应被视为初始经验值，而不是长期常量。建议：

- 在 debug trace 记录每轮候选 distance。
- 测试中用 fake vector store 构造边界值。
- UI 不显示原始 distance 给普通用户，只显示“相关 / 近期补充 / fallback”这类解释。
- 后续可按 embedding 模型版本保存 threshold，避免换模型后沿用旧尺度。

## 8. Phase D：Reflect / observation synthesis

Phase D 当前只落地 Memory 层最小 contract，不实现 reflect LLM executor 或 UI 入口。

Reflect 是唯一明确需要 LLM 参与的 Hindsight-lite 子流程。retain 已经使用 LLM 抽取，但它只是结构化保存；recall 默认应是本地检索和排序。

### 8.1 触发方式

允许：

- 用户在记忆管理页点击“整理记忆”。
- App 空闲或后台低频触发。
- 后续 BackgroundWorker 若发现重复/冲突 cluster，可生成整理任务。

禁止：

- 每轮用户发送都调用 reflect。
- reflect 直接生成 assistant 回复。
- reflect 静默覆盖原始记忆。

### 8.2 输入输出

实现中的输入 contract：

```swift
struct MemoryReflectRequest: Sendable {
    let characterCardId: String
    let task: MemoryReflectTask
    let sourceMemoryIds: [String]
}
```

规划中的 LLM 输入：

```json
{
  "characterId": "...",
  "cluster": [
    { "id": "m1", "content": "...", "type": "event" },
    { "id": "m2", "content": "...", "type": "relationship" }
  ],
  "task": "summarize|dedupe|resolve_conflict|relationship_observation"
}
```

实现中的 observation contract：

```swift
struct MemoryReflectObservation: Sendable {
    let content: String
    let memoryType: MemoryType
    let basedOnMemoryIds: [String]
    let confidence: Double?
    let suggestedAction: MemoryReflectAction
}
```

规则：

- `sourceMemoryIds` / `basedOnMemoryIds` 不能为空。
- `content` 不能为空。
- `confidence` clamp 到 `0...1`。
- task contract 为 `summarize`、`dedupe`、`resolve_conflict`、`relationship_observation`。
- suggested action contract 为 `insert_observation`、`mark_duplicate`、`needs_user_review`。
- 第一版 relation contract 为 `summarizes`、`duplicates`、`reinforces`。

规划中的 LLM 输出：

```json
{
  "observation": "Short synthesized memory",
  "type": "summary|relationship",
  "basedOn": ["m1", "m2"],
  "confidence": 0.0,
  "suggestedAction": "insert_observation|mark_duplicate|needs_user_review"
}
```

写入原则：

- 新 observation 必须有 `basedOn`。
- 原始记忆默认保留。
- 冲突解决或删除建议进入 review，不自动破坏历史证据。
- 自动注入 prompt 时，observation 可以比原始 cluster 有更高优先级，但仍受 recall relevance 控制。

实现证据：

- `OpenChat/Core/Memory/MemoryReflectModels.swift`
- `OpenChatTests/Core/MemoryTests/MemoryReflectModelsTests.swift`

## 9. Phase D：Background 适配边界与 Responses API

### 9.1 Background 适配边界

Hindsight-lite 不直接替代 Background，也不在 Memory 模块内实现 Background orchestration。它提供更好的 Memory source；2026-05-17 Phase 4-6 已把该 source 包装进当前 Chat-Prompt 兼容链路：

```text
MemoryRecallResult
  -> BackgroundCandidate(sourceType: .memory, metadata: trace fields)
  -> BackgroundWorker
  -> BackgroundPacket
  -> PromptAssembler(... backgroundPacket:)
  -> [Memories]
```

已完成迁移顺序：

1. 先修 `PromptAssembler` order-preserving trim。
2. 本计划补齐 `MemoryRecallResult` / trace / provenance。
3. `MemoryRecallTool` / `MemoryBackgroundSource` 把 `MemoryRecallResult` 包装成 `BackgroundCandidate`。
4. `BackgroundWorker` / `BackgroundPacket` / packet-aware `PromptAssembler` 接入 Chat 主链路，保持 `[Memories]` 兼容 block。

后续迁移只剩统一 `[Background]` block、Character / ConversationState sources、diagnostics UI 和 synthesis/reflect 相关工作。

### 9.2 Responses API system folding

当前 Responses API 会把 system messages 合并到 `instructions`。因此 `[Memories]` 在源代码 message 列表中的位置，不一定等于 provider 实际看到的位置。

当前已完成：

- 对 Chat Completions 和 Responses API 分别记录最终请求 shape。
- 在本计划测试中确认当前 `[Memories]` 不会被拼进 user message，也不会丢失。
- Chat Completions 模式下 `[Memories]` 仍在 `messages` 中，位于 Current Turn user 前。
- Responses 模式下 `[Memories]` 在 `instructions` 中，`input` 只包含非 system messages，current input 不重复。

仍留给后续：

- 统一 `[Background]` block 的稳定 label 与 request-shape audit。
- Character / ConversationState sources 与 synthesis worker。
- packet diagnostics 的 debug UI 展示。

## 10. 可观测性

最低可用 trace：

| 字段 | 用途 |
|---|---|
| `extractionPromptVersion` | 判断 retain v1/v2 |
| `sourceStartSortOrder` / `sourceEndSortOrder` | 追踪记忆来源 |
| `semanticDistance` | 校准阈值 |
| `fallbackReason` | 解释为什么用了 recent/keyword |
| `selectedIds` | 本轮进入 prompt 的记忆 |
| `omitted` | 说明因预算、重复、低相关或冲突被省略的条目 |

展示策略：

- 普通 UI 只显示提取状态和记忆管理。
- debug / 详细统计显示 recall trace。
- trace 不进入主模型 prompt，避免污染角色回复。

## 11. 测试计划

必须新增或补强：

| 测试 | 覆盖 |
|---|---|
| order-preserving prompt trim | `importance` 不覆盖 retrieval order |
| recall fallback tiers | semantic 失败时不盲目注入最近噪声 |
| extraction prompt v2 parsing | source range、confidence、tags、action 兼容 |
| provenance migration | companion table 追加，不破坏旧数据 |
| dedupe behavior | 同批重复不重复写入 |
| reflect output validation | 已覆盖：observation 必须有 `basedOn`，request 必须有 source ids，relation 集合最小化 |
| Responses API request shape | 已覆盖：当前 `[Memories]` block 不丢失；统一 `[Background]` block 留给后续独立计划 |

建议 focused verification：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MemoryManagerRetrievalTests' '-only-testing:OpenChatTests/PromptAssemblerTests' '-only-testing:OpenChatTests/MemoryExtractionParsingTests'
```

## 12. 落地顺序

| 阶段 | 内容 | 是否需要 migration |
|---|---|---:|
| A | order-preserving trim + tests | 否 |
| B1 | `MemoryRecallResult` / trace 内部 DTO | 否 |
| B2 | fallback tiers + keyword/recent high-value candidate | 否，可先用现有表 |
| C | provenance companion table + extraction prompt v2 | 是（v14） |
| D | reflect contract + Responses request-shape | 否 |
| E | reflect executor / `memory_entry_link` / basedOn 表 | 是 |
| F | MemoryBackgroundSource 接入 Background | 已完成 Phase 4-6 compatible switch；统一 `[Background]` block 未启用 |

Phase A/B/C/D 与 Lead closeout 已依次完成；2026-05-16 full suite 251 tests / 46 suites passed。2026-05-17 后续 Phase 4-6 已完成 Memory source tool / adapter、BackgroundWorker / packet 和 Chat-Prompt compatible switch。剩余工作是 reflect executor、`memory_entry_link` 持久化、统一 `[Background]` block、Character / ConversationState sources 和 packet diagnostics UI。
