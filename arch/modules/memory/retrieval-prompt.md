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

## 2. 语义检索步骤

`MemoryManager.retrieveMemories(...)` 当前流程：

1. `EmbeddingProvider.embed(query, isQuery: true)` 生成 query embedding。
2. `MemoryVectorStore.search(query:characterCardId:limit:)` 执行 KNN。
3. 捕获 embedding/model/vector 异常，fallback 到 `retrieveRecentSummary(...)`。
4. 过滤 `distance >= 1.5` 的结果。
5. 若过滤后为空，fallback 到 `retrieveRecentSummary(...)`。
6. 根据 KNN 返回的 entry ids 回表加载 `MemoryEntryRecord`。
7. 按 KNN id 顺序恢复 `orderedEntries`。
8. 追加最近 2 条记忆作为补充，并按 id 去重。

## 3. 近期记忆 fallback

`retrieveRecentSummary(for:limit:)` 当前实现是按 `createdAt DESC` 查询指定角色的最近记忆。

注意：

- 这个函数名包含 `Summary`，但当前源码没有只筛选 `memoryType == summary`。
- fallback 的含义是“近期记忆”，不是“摘要类型记忆”。
- 文档或 UI 不应暗示它只返回 summary 条目。

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

## 6. 当前排序风险

当前有一个已知 P1 风险：

- `MemoryManager.retrieveMemories(...)` 会先按 KNN id 顺序恢复语义相关结果。
- 但 `PromptAssembler.trim(memories:within:)` 在裁剪前执行 `memories.sorted { importance DESC }`。
- 当 token 预算不足时，高 importance 但低相关的记忆可能挤掉当前输入更相关的记忆。

这也是 `arch/AntiEntropy/problem.md` 中仍打开的“语义检索顺序在 Prompt 注入前被 importance 重排”问题。

修复方向：

- 保留 retrieval order 作为主排序。
- `importance` 只作为同分/补充排序或预算内展示元数据。
- 如引入 Hindsight-lite recall，可在 `MemoryManager` 内完成 semantic + keyword + recency fusion 后输出最终顺序，`PromptAssembler` 不再重排。

## 7. Hindsight-lite recall 规划

Hindsight-lite 将 recall 拆成候选、融合、裁剪和 trace 四步：

```text
semantic KNN candidates
  + keyword candidates
  + recent high-value candidates
  -> rank fusion
  -> ordered MemoryRecallResult
  -> prompt trim / BackgroundCandidate
```

目标 contract：

- `MemoryRecallResult.entries` 是最终有序列表。
- `MemoryRecallTrace` 记录 semantic/keyword/recent candidate 数量、fallback reason、selected ids 和 omitted ids。
- `PromptAssembler` 只按输入顺序裁剪，不再了解 semantic distance 或 fallback 细节。
- `recent` 只作为 high-value 补充或 fallback tier，不再无条件把最近噪声塞入 prompt。

fallback 分层：

| fallback | 触发 | 目标行为 |
|---|---|---|
| `semanticUnavailable` | embedding/model/sqlite-vec 失败 | keyword + recent high-value |
| `noSemanticHit` | KNN 全部超过阈值 | keyword 命中优先；没有 keyword 时只保留少量高价值 relationship/summary |
| `emptyIndex` | 无 memory 或无 embedding | 返回空，不伪造记忆 |
| `budgetDropped` | 有候选但预算不足 | trace 记录 omitted |

这些规划尚未实现，当前源码仍使用 `distanceThreshold == 1.5` 与 recent fallback。

## 8. 错误处理

| 阶段 | 失败行为 |
|---|---|
| query embedding 失败 | fallback 到近期记忆 |
| sqlite-vec KNN 失败 | fallback 到近期记忆 |
| KNN 结果全部超过 distance threshold | fallback 到近期记忆 |
| fallback 查询失败 | 向 Chat 抛出，Chat 记录 warning 后继续空 memory |
| Prompt 裁剪预算不足 | 至少保留第一条记忆，即使超过预算 |

## 9. 实现证据

- `OpenChat/Core/Memory/MemoryManager.swift`
- `OpenChat/Core/Memory/VectorStore.swift`
- `OpenChat/Core/PromptEngine/PromptAssembler.swift`
- `OpenChat/Core/PromptEngine/TokenBudget.swift`
- `OpenChat/Features/Chat/ViewModels/ChatViewModel+Support.swift`
- `OpenChatTests/Core/MemoryTests/MemoryManagerRetrievalTests.swift`
- `OpenChatTests/Core/PromptEngineTests/PromptAssemblerTests.swift`
- `OpenChatTests/Features/ChatTests/ChatViewModelPromptAssemblyTests.swift`
