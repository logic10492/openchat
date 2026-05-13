# Hindsight-lite 完善设计

> 状态：设计规划，尚未实现。
> 目标：用轻量 retain / recall / reflect 设计关闭 `arch/AntiEntropy/problem.md` 中剩余的记忆系统问题。

本页参考 Hindsight 论文的三段式操作：retain、recall、reflect。论文把 agent memory 视为可推理的结构化底座，并强调证据、推断和可追踪更新的区别。OpenChat 不需要完整复刻论文中的多网络记忆系统，当前目标是把已有 `memory_entry` / `memory_embedding` 演进成低延迟、可解释、可测试的本地轻量版本。

参考：<https://arxiv.org/abs/2512.12818>

## 1. 设计目标

Hindsight-lite 的目标不是增加一个远端 memory daemon，而是在现有 iOS 本地架构上补齐四个缺口：

1. **排序可靠**：当前输入相关性必须优先于 `importance`，关闭 P1 recall ordering 问题。
2. **来源可追踪**：每条自动记忆应知道来自哪段消息，降低抽取幻觉和重复污染。
3. **召回可解释**：fallback、distance threshold、预算裁剪和被省略条目都要能在 debug 视图中解释。
4. **整理低频化**：reflect 只用于记忆整理和 observation synthesis，不进入每轮主聊天链路。

## 2. 非目标

- 不在每次用户发送时额外调用 reflect LLM。
- 不让 reflect 生成给用户看的 assistant 回复。
- 不引入远端 Hindsight 服务作为必需运行时。
- 不把同会话 compression checkpoint 替换成长期记忆。
- 不让 `PromptAssembler` 承担 recall rerank。
- 不为 provider 没有返回的字段伪造“模型置信分数”。
- 不把 Background 目标架构写成当前已实现能力。

## 3. 与当前问题的对应关系

| problem.md 条目 | Hindsight-lite 设计动作 | 目标状态 |
|---|---|---|
| P1：Prompt 注入前被 importance 重排 | Phase A：order-preserving trim，排序权归 recall | 可关闭 |
| P2：fallback 和阈值缺少校准与可观测性 | Phase C：`MemoryRecallTrace` + fallback tier | 规划后可实现 |
| P2：recent fallback 只按时间取最近 | Phase C：recent high-value fallback，不盲目注入噪声 | 规划后可实现 |
| P2：提取 prompt 缺少角色卡、已有记忆、source 边界和去重 | Phase B：retain schema + extraction prompt v2 | 规划后可实现 |
| P2：Responses API system folding | Phase E：Background block position audit | 规划后可实现 |
| P3：检索可观测性不足 | Phase C / E：recall diagnostics 到 debug UI | 规划后可实现 |

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
  -> BackgroundCandidate(.memory)   // target

Reflect
  selected memory cluster
  -> LLM structured synthesis
  -> observation draft with basedOn ids
  -> user-confirmed or audited write
```

当前源码仍是：

```text
MemoryManager.retrieveMemories
  -> [MemoryEntryRecord]
  -> PromptAssembler.trim(memories:)
  -> [Memories] system block
```

目标源码应收敛为：

```text
MemoryBackgroundSource
  -> [BackgroundCandidate]
  -> BackgroundWorker
  -> BackgroundPacket
  -> BackgroundAssembler / PromptAssembler
```

## 5. Phase A：Recall ordering 先行修复

这是最小、最高优先级改动，直接关闭当前 P1。

### 5.1 排序所有权

规则：

- `MemoryManager` 或未来 `MemoryBackgroundSource` 输出的顺序就是最终相关性顺序。
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

## 6. Phase B：Retain schema v2

当前 retain 只保存 `content/type/importance`。这能工作，但无法回答“这条记忆从哪里来”“是否重复”“是否被后来信息强化或冲突”。

### 6.1 最小新增结构

建议优先追加 companion table，减少对 `MemoryEntryRecord` 主表和现有 UI 的冲击：

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
- Hindsight-lite 元数据可以独立迁移、独立测试。
- 如果后续 Background 接管 prompt，主表仍能作为稳定内容表。

### 6.2 Extraction prompt v2

输入应从纯文本：

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
- `sourceStartSortOrder` / `sourceEndSortOrder` 必须落在本批消息范围内；否则丢弃该条或降级为无 provenance。
- `confidence` 只表示抽取器自报置信，不参与最终 truth 判定。
- `action == skip` 不写入 DB，只计入 diagnostics。
- `action == reinforce` 优先写 `memory_entry_link` 或更新 `lastReinforcedAt`，不重复插入同义条目。

### 6.3 去重策略

第一阶段不需要复杂 graph。建议用三层去重：

1. **同批去重**：同一 extraction response 内 `dedupeKey` 相同只保留 importance 更高或更短的一条。
2. **近邻去重**：抽取前给 LLM 最近/最相关的 existing memory hints，让它返回 `reinforce` 或 `skip`。
3. **向量近似去重**：写入前用新条目的 embedding 搜索同角色现有记忆，距离很近且类型一致时标记为 duplicate candidate。

写入原则：

- 自动流程可以跳过明确重复条目。
- 自动流程不应无声删除旧条目。
- 合并、替换或标记冲突需要 debug trace，必要时交给用户确认。

## 7. Phase C：Recall fusion 与 fallback 分层

### 7.1 Recall result contract

新增内部 DTO，先不要求 UI 全量展示：

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

`MemoryManager.retrieveMemories(...) -> [MemoryEntryRecord]` 可以先保持兼容，内部使用 result 后只返回 `entries.map(\.memory)`。等 Background 落地后再让 `MemoryBackgroundSource` 读取完整 trace。

### 7.2 Candidate sources

建议召回候选：

- semantic：sqlite-vec KNN top 20。
- keyword：对 `memory_entry.content` 做简单关键词匹配或后续 FTS5。
- recent high-value：最近的 `relationship` / `summary` / 高 importance 记忆，数量小于等于 3。

注意：recent 不是默认兜底塞满 prompt。它只补充高价值上下文。

### 7.3 Rank fusion

第一版可用 Reciprocal Rank Fusion：

```text
score =
  semanticWeight * 1 / (k + semanticRank)
  + keywordWeight * 1 / (k + keywordRank)
  + recencyWeight * 1 / (k + recencyRank)
  + importanceTieBreaker
```

建议权重：

| 信号 | 建议 |
|---|---|
| semantic | 主信号 |
| keyword | 中等权重，用于名字、地点、专有名词 |
| recency | 小权重，只防止近期关系状态完全丢失 |
| importance | tie-breaker，不覆盖相关性 |

### 7.4 Fallback tiers

当前 fallback 是“语义失败或低相关时取最近 N 条”。这会把近期噪声注入 prompt。建议改成分层：

| fallback | 触发 | 返回 |
|---|---|---|
| `semanticUnavailable` | embedding/model/sqlite-vec 失败 | keyword + recent high-value |
| `noSemanticHit` | semantic 全部超过阈值 | keyword candidates；没有 keyword 时只返回 pinned/high-value relationship summary |
| `emptyIndex` | 角色没有记忆或没有 embedding | 空结果，不伪造 recent |
| `budgetDropped` | 有候选但 prompt 预算不足 | trace 记录 omitted，不额外补 recent |

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

Reflect 是唯一明确需要 LLM 参与的 Hindsight-lite 子流程。retain 已经使用 LLM 抽取，但它只是结构化保存；recall 默认应是本地检索和排序。

### 8.1 触发方式

允许：

- 用户在记忆管理页点击“整理记忆”。
- App 空闲或后台低频触发。
- BackgroundWorker 发现重复/冲突 cluster 后生成整理任务。

禁止：

- 每轮用户发送都调用 reflect。
- reflect 直接生成 assistant 回复。
- reflect 静默覆盖原始记忆。

### 8.2 输入输出

输入：

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

输出：

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

## 9. Phase E：Background 与 Responses API

### 9.1 Background 集成

Hindsight-lite 不直接替代 Background。它提供更好的 Memory source：

```text
MemoryRecallResult
  -> BackgroundCandidate(sourceType: .memory, metadata: trace fields)
  -> BackgroundWorker
  -> BackgroundPacket
```

迁移顺序：

1. 先修 `PromptAssembler` order-preserving trim。
2. 再把 `MemoryRecallResult` 包装成 `BackgroundCandidate`。
3. 最后让 `PromptAssembler` 消费 Background block，而不是分别消费 memories 和 world-book entries。

### 9.2 Responses API system folding

当前 Responses API 会把 system messages 合并到 `instructions`。因此 `[Memories]` 在源代码 message 列表中的位置，不一定等于 provider 实际看到的位置。

规划动作：

- 给 Background block 加稳定 label，例如 `[Background] ... [/Background]`。
- 对 Chat Completions 和 Responses API 分别记录最终请求 shape。
- 在测试中确认 memory/background 不会被拼进 user message，也不会丢失。
- 在 `arch/modules/api-client.md` 或 Responses API 文档中记录 system folding 对 prompt 层次的影响。

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
| reflect output validation | observation 必须有 `basedOn` |
| Responses API request shape | Background / Memories block 不丢失 |

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
| C | provenance companion table + extraction prompt v2 | 是 |
| D | dedupe / reinforce metadata | 可能需要 |
| E | reflect observation synthesis | 是，建议有 `basedOn` 表 |
| F | MemoryBackgroundSource 接入 Background | 否或少量 DTO |

最务实的第一步是 Phase A。它范围小、风险低、能直接关闭当前 P1，并为后续 recall fusion 建立正确的排序契约。
