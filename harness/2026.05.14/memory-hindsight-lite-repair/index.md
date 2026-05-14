# Memory Hindsight-lite Repair - Phase A Propagation Audit

> 日期：2026-05-14
> 范围：`docs/superpowers/plans/2026-05-14-memory-hindsight-lite-repair/03_phase_a_recall_ordering.md`
> 阶段：A - Recall Ordering
> 审计模式：窄范围增量传播审计。OpenChat 当前没有可生成 Swift import graph 的传播审计脚本，本轮使用源码链路、`rg` 静态引用和 focused tests 作为证据。

## 1. Phase A 目标

关闭 AE P1：`MemoryManager.retrieveMemories(...)` 已按 KNN id 顺序恢复语义检索结果，但 `PromptAssembler.trim(memories:within:)` 在注入 `[Memories]` 前按 `importance DESC` 重排，可能让高 importance 但低相关的记忆挤掉当前输入更相关的记忆。

本阶段只改变 prompt 裁剪排序权属：

- `MemoryManager` / 未来 `MemoryBackgroundSource` 拥有 recall 排序权。
- `PromptAssembler` 只按输入数组顺序和 token budget 裁剪。
- `importance` 不再在 prompt trim 阶段覆盖 retrieval order。

## 2. Baseline 传播链

行为链路：

```text
ChatViewModel.generateResponse
  -> MemoryManager.retrieveMemories(for:query:limit:)
  -> PromptAssembler.preview(memories:)
  -> PromptAssembler.trim(memories:within:)
  -> PromptAssembler.makeMemoryBlock(_:)
  -> PromptAssembler.assemble(...)
  -> APIClient.streamMessage(...)
```

关键源码锚点：

- `OpenChat/Features/Chat/ViewModels/ChatViewModel+Support.swift:102` 定义本轮 prompt memories 数组。
- `OpenChat/Features/Chat/ViewModels/ChatViewModel+Support.swift:105` 调用 `MemoryManager.retrieveMemories(...)`。
- `OpenChat/Core/Memory/MemoryManager.swift:127` 从 KNN filtered ids 得到 `ids`。
- `OpenChat/Core/Memory/MemoryManager.swift:131` 按 `ids.compactMap` 恢复 KNN 顺序。
- `OpenChat/Core/Memory/MemoryManager.swift:138` 返回 `orderedEntries + uniqueSummaries`。
- `OpenChat/Core/PromptEngine/PromptAssembler.swift:61` 调用 `trim(memories:within:)`。
- `OpenChat/Core/PromptEngine/PromptAssembler.swift:201` 把裁剪后的记忆合并为 `[Memories]` block。
- `OpenChat/Core/PromptEngine/PromptAssembler.swift:283` 是 Phase A 唯一需要改变的源码函数。

## 3. Baseline 风险

| 风险 | Baseline 状态 | Phase A 处理 |
|---|---|---|
| retrieval order 被 prompt trim 覆盖 | `trim(memories:)` 对 `memories.sorted { importance DESC }` 迭代 | 删除排序，按输入顺序迭代 |
| budget 裁剪后无记忆 | 现有逻辑保证至少保留第一条，即使超过预算 | 保留该行为 |
| world book / example dialog 行为被误改 | `trim(entries:)` 和 `trim(messages:)` 与 memory trim 并列但职责不同 | 不修改 |
| Chat / MemoryManager 接口震荡 | `retrieveMemories(...) -> [MemoryEntryRecord]` 仍是兼容接口 | 不修改 |
| Responses API system folding | 属 Phase D 风险，不由 Phase A 改动 | 保持 open |

## 4. 修改后传播评估

源码变更：

- `OpenChat/Core/PromptEngine/PromptAssembler.swift`：`trim(memories:within:)` 删除 `memories.sorted(by: { $0.importance > $1.importance })`，改为按输入 `memories` 原序迭代。
- `OpenChatTests/Core/PromptEngineTests/PromptAssemblerTests.swift`：新增 `test_memory_trim_preserves_retrieval_order_when_budget_drops_high_importance_memory`。

传播结果：

- Production Swift 改动只触及 `Core/PromptEngine`，未改变 `MemoryManager`、Chat ViewModel、API request、Database migration 或 Xcode project。
- `PromptAssembler.preview(...)` / `assemble(...)` 签名不变，调用方不需要迁移。
- `[Memories]` block 的层级位置不变：仍在 Current-Turn Context，world book block 之后、current user input 之前。
- token budget 与“至少保留第一条”行为不变。
- 排序权现在回到 recall 输出侧：`MemoryManager` 当前输出顺序就是 `PromptAssembler` 裁剪顺序；未来 Background / Hindsight-lite 可在进入 `PromptAssembler` 前完成 fusion / tie-break。

质量结论：

- P1 “语义检索顺序在 Prompt 注入前被 importance 重排”已关闭。
- 本阶段没有扩大 Swift import 图或 Feature/Core 边界。
- P2 fallback tiers、recall trace、provenance、Responses API system folding 仍未实现，继续保留为后续阶段问题。

## 5. 验证

详见 `evidence.txt`。
