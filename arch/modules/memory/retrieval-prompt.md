# 记忆检索与 Prompt 注入

## 1. 检索入口

Chat 发送链路在自动提取之后调用：

```swift
memoryManager.retrieveMemories(
    for: characterCardId,
    query: prompt,
    limit: 10
)
```

这里的 `query` 是当前用户输入。检索结果会传入 `PromptAssembler.preview(...)` 和 `PromptAssembler.assemble(...)`。

## 2. Recall v2 检索步骤

`MemoryManager.retrieveMemories(...)` 仍是 Chat 兼容入口，内部调用 `recallMemories(...)` 后返回 `result.entries.map(\.memory)`。`MemoryManager.recallMemories(...)` 当前流程：

1. `EmbeddingProvider.embed(query, isQuery: true)` 生成 query embedding。
2. `MemoryVectorStore.search(query:characterCardId:limit:)` 执行 KNN，search limit 扩大到 `max(limit * 2, 20)`。
3. 过滤 `distance >= 1.5` 的结果，并把被阈值丢弃的 id 记录到 `MemoryRecallTrace.omitted`。
4. 根据 KNN 返回的 entry ids 回表加载 `MemoryEntryRecord`，恢复 semantic order 与 distance。
5. 从同角色 `memory_entry` 做轻量 keyword candidate：query lowercased 后拆词，长度至少 3，content 命中任一 keyword 即入候选。
6. 调用 `DatabaseManager.fetchRecentHighValueMemories(...)` 获取少量 recent high-value candidate：`relationship` / `summary` 优先，或 `importance >= 70`。
7. 根据 semantic 状态决定 fallback tier，并融合 semantic / keyword / recent high-value 候选。
8. 返回 `MemoryRecallResult(entries, trace)`；旧入口只暴露有序 `[MemoryEntryRecord]` 给 `PromptAssembler`。

## 3. Fallback tier

Phase B 后不再把任意最近 N 条记忆作为默认 fallback。当前分层：

| fallback | 触发 | 返回策略 |
|---|---|---|
| `none` | semantic 有有效命中 | semantic 为主，keyword / recent high-value 只补充未出现条目 |
| `semanticUnavailable` | embedding/model/sqlite-vec 失败 | keyword + recent high-value |
| `noSemanticHit` | semantic 全部超过阈值或没有命中 | keyword 优先；没有 keyword 时 recent high-value |
| `emptyIndex` | 角色没有 memory，或 keyword/recent high-value 也为空 | 空结果 |

`fetchRecentMemories(characterCardId:limit:)` 仍保留给管理/普通 recent 查询；fallback path 使用 `fetchRecentHighValueMemories(characterCardId:limit:)`。

## 4. Prompt 注入格式

每条记忆由 `PromptAssembler.makeMemoryMessageContent(_:)` 格式化：

```text
[Memory — event]
玩家在森林中救了一只受伤的精灵
```

多条记忆合并成一个 system message：

```text
[Memories]
[Memory — event]
...

[Memory — relationship]
...
[/Memories]
```

该 block 属于 Current-Turn Context，位于 Stable Identity / Stable Conversation State 之后、Current Turn user message 之前。

## 5. Token 预算

`TokenBudget.allocate(...)` 为 memory 分配剩余预算的 15%，上限受实际 memory token 需求约束。

```
memoryBudget = min(Int(Double(remaining) * 0.15), memoryTokens)
historyBudget = remaining - exampleDialogsBudget - worldBookBudget - memoryBudget
```

## 6. Prompt 裁剪顺序

2026-05-14 Phase A/B 已关闭原 P1 排序风险并把排序权收敛到 recall：

- `MemoryManager.retrieveMemories(...)` 会先按 KNN id 顺序恢复语义相关结果。
- `PromptAssembler.trim(memories:within:)` 现在按输入数组顺序累积 token，不再执行 `memories.sorted { importance DESC }`。
- Phase B 后 `MemoryRecallResult.entries` 是 rank fusion 后的最终顺序，`retrieveMemories(...)` 保持该顺序返回。
- 当 token 预算不足时，裁剪会保留 retrieval order 中靠前的记忆；若第一条本身超预算，仍沿用既有“至少保留第一条”的行为。

排序权属：

- 当前由 `MemoryManager` 输出最终 prompt memory 顺序。
- `MemoryRecallResult` 负责 rank fusion；未来独立 Background 计划可由 `MemoryBackgroundSource` 包装该结果。
- `importance` 只作为同等相关性时的 tie-breaker、fallback 策略输入或 UI 展示元数据，不再由 `PromptAssembler` 用来重排 prompt memory。

实现与测试证据：

- `OpenChat/Core/PromptEngine/PromptAssembler.swift`：`trim(memories:within:)` 对 `memories` 原序迭代。
- `OpenChatTests/Core/PromptEngineTests/PromptAssemblerTests.swift`：`test_memory_trim_preserves_retrieval_order_when_budget_drops_high_importance_memory` 覆盖 `[A, B, C]` 输入、`C > B > A` importance、预算只保留 A/B 的场景。
- 2026-05-14 Phase B verification：`MemoryManagerRetrievalTests`、`DatabaseManagerMemoryTests`、`VectorStoreTests`、`PromptAssemblerTests`、`ChatViewModelPromptAssemblyTests` focused suite 49 tests / 5 suites passed。

## 7. Hindsight-lite recall 当前状态

Phase B 已把 recall 拆成候选、融合和 trace：

```text
semantic KNN candidates
  + keyword candidates
  + recent high-value candidates
  -> rank fusion
  -> ordered MemoryRecallResult
  -> current [Memories] prompt compatibility
  -> future BackgroundCandidate adapter boundary
```

当前 contract：

- `MemoryRecallResult.entries` 是最终有序列表。
- `MemoryRecallTrace` 记录 semantic/keyword/recent candidate 数量、fallback reason、selected ids 和 omitted ids。
- 兼容旧链路时，`PromptAssembler` 只按输入顺序裁剪，不再了解 semantic distance、importance rerank 或 fallback 细节。
- `recent` 只作为 high-value 补充或 fallback tier，不再无条件把最近噪声塞入 prompt。

fallback 分层：

| fallback | 触发 | 目标行为 |
|---|---|---|
| `semanticUnavailable` | embedding/model/sqlite-vec 失败 | keyword + recent high-value |
| `noSemanticHit` | KNN 全部超过阈值 | keyword 命中优先；没有 keyword 时只保留少量高价值 relationship/summary |
| `emptyIndex` | 无 memory 或无 embedding | 返回空，不伪造记忆 |
| `budgetDropped` | 有候选但 prompt 预算不足 | 尚未由 `PromptAssembler` 回写；后续 Background 统一裁剪时处理 |

## 8. 错误处理

| 阶段 | 失败行为 |
|---|---|
| query embedding 失败 | `semanticUnavailable`，fallback 到 keyword + recent high-value |
| sqlite-vec KNN 失败 | `semanticUnavailable`，fallback 到 keyword + recent high-value |
| KNN 结果全部超过 distance threshold | `noSemanticHit`，keyword 优先；没有 keyword 时 recent high-value |
| fallback 查询失败 | 向 Chat 抛出，Chat 记录 warning 后继续空 memory |
| Prompt 裁剪预算不足 | 至少保留第一条记忆，即使超过预算 |

## 9. 实现证据

- `OpenChat/Core/Memory/MemoryManager.swift`
- `OpenChat/Core/Memory/MemoryRecallModels.swift`
- `OpenChat/Core/Memory/VectorStore.swift`
- `OpenChat/Core/Database/DatabaseManager+Memory.swift`
- `OpenChat/Core/PromptEngine/PromptAssembler.swift`
- `OpenChat/Core/PromptEngine/TokenBudget.swift`
- `OpenChat/Features/Chat/ViewModels/ChatViewModel+Support.swift`
- `OpenChatTests/Core/MemoryTests/MemoryManagerRetrievalTests.swift`
- `OpenChatTests/Core/DatabaseTests/DatabaseManagerMemoryTests.swift`
- `OpenChatTests/Core/PromptEngineTests/PromptAssemblerTests.swift`
- `OpenChatTests/Features/ChatTests/ChatViewModelPromptAssemblyTests.swift`
