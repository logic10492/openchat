# BackgroundSource 统一候选来源

> 状态：Memory / WorldBook read-only recall tools 与 `MemoryBackgroundSource` / `WorldBookBackgroundSource` adapters 已在 2026-05-17 Phase 4A-4D 落地；2026-05-17 Phase 5/6 已由 `BackgroundWorker` / `BackgroundManager` 消费这些 candidates 并切入 Chat/Prompt 兼容链路。Character / ConversationState sources 尚未实现。

## 1. Source 类型

```swift
enum BackgroundSourceType: String, Codable, Sendable {
    case memory
    case worldBook
}
```

当前源码只包含 `.memory` / `.worldBook`；`character` / `conversationState` 是后续目标 source，不是 live enum case。

## 1.1 Source tool 前置边界

在实现 `BackgroundWorker` 前，Memory 与 WorldBook 已先暴露内部 read-only source tool：

| Tool | 包装对象 | 输出 | 禁止事项 |
|---|---|---|---|
| `MemoryRecallTool` | `MemoryManager.recallMemories(...)` | `MemoryRecallResult` / trace | 不复制 rank fusion、不写 DB、不拼 prompt |
| `WorldBookRecallTool` | `WorldBookSource.recallEntries(...)` | `WorldBookRecallResult` / trace | 不复制 keyword+semantic fusion、不触发索引 rebuild、不拼 prompt |

这些 tool 不是普通角色工具，不进入角色回复的 tool call，也不向用户暴露。它们只作为 BackgroundSource adapter 的输入边界，让 `BackgroundWorker` 消费统一候选，而不是直接依赖 Memory / WorldBook 的内部实现。

当前实现证据（2026-05-17）：

- `OpenChat/Core/Memory/MemoryRecallTool.swift` 已实现并进入 target；`MemoryRecallToolTests` 覆盖 input forwarding、result order、rank/reason/trace/fallback 透传和 `limit == 0` 透传。
- `OpenChat/Core/WorldBook/WorldBookRecallTool.swift` 已实现并进入 target；`WorldBookRecallToolTests` 覆盖 keyword-only、semantic-only、hybrid、disabled、semanticUnavailable、staleEmbedding、limit/duplicate omission 透传和无 indexer/rebuild dependency。
- `OpenChat/Core/Background/MemoryBackgroundSource.swift` / `WorldBookBackgroundSource.swift` 已实现并进入 target；`BackgroundSourceTests` 覆盖 candidate id prefix、顺序、metadata、request 边界和不按 token budget 裁剪。
- `OpenChat/Core/Background/BackgroundWorker.swift` / `BackgroundManager.swift` 已消费这两个 source adapters；`BackgroundManagerTests` 覆盖 source merge 与 worldBook source failure keyword fallback。

## 2. MemoryBackgroundSource

来源：`memory_entry` + `memory_embedding`。

职责：

- 用当前输入做 semantic retrieval。
- 保留 recent high-value fallback，并作为 fallback metadata 标记；不得恢复任意最近 N 条 prompt 注入。
- 返回 `BackgroundCandidate(sourceType: .memory)`。
- 不再直接把 memories 传给 `PromptAssembler`。

实现顺序：

1. 先实现 `MemoryRecallTool`，只调用 `MemoryManager.recallMemories(...)` 并返回 `MemoryRecallResult`。
2. 再实现 `MemoryBackgroundSource`，把 result entries 与 trace 映射到 `BackgroundCandidate` metadata。
3. 最后由 `BackgroundWorker` 对不同 source 的 candidates 做跨源预算裁剪。

`MemoryBackgroundSource` 不应重新实现 semantic / keyword / recent high-value fallback，也不应让 `importance` 覆盖 Memory 层已经确定的相关性顺序。

2026-05-14 Phase A 已在现有 `PromptAssembler.trim(memories:)` 关闭 Memory P1 排序问题：prompt 裁剪保持 recall 输入顺序，不再按 `importance` 重排。Background 接入后仍必须保持该契约，semantic retrieval order 是主排序信号，`importance` 只能做 tie-breaker。

## 3. WorldBookBackgroundSource

来源：`world_book_entry` + 当前已存在的 `world_book_entry_embedding`。

当前状态：2026-05-16 Phase A/B 已实现 schema、meta record、`WorldBookVectorStore`、embedding text/hash 和 `WorldBookEmbeddingIndexer` rebuild/backfill；Phase C 已实现 `WorldBookSource`；Phase D 已实现 save/import/delete/eraseAllData 维护和 Data Management 手动 rebuild。2026-05-17 Phase 4D 已新增 target-backed `WorldBookBackgroundSource` adapter 和 focused tests；2026-05-17 Phase 5/6 已由 `BackgroundWorker` 统一调度，并继续通过 `BackgroundAssembler` 输出兼容 `[World Book Entries]` block。

职责：

- 保留 keyword trigger。
- 增加 semantic KNN。
- 融合 `priority`、keyword hit 和 semantic rank。
- 返回 `BackgroundCandidate(sourceType: .worldBook)`。

实现顺序：

1. 先实现 `WorldBookRecallTool`，只调用 `WorldBookSource.recallEntries(...)` 并返回 `WorldBookRecallResult`。
2. 再实现 `WorldBookBackgroundSource`，把 recall entries / trace / omissions 映射到 `BackgroundCandidate` metadata。
3. 最后由 `BackgroundWorker` 与 Memory / CharacterState / ConversationState 候选统一裁剪。

`WorldBookBackgroundSource` 不应复制 `WorldBookSource` 的 keyword + semantic fusion；索引 rebuild / save-import-delete 维护仍属于既有 WorldBook lifecycle，不由 BackgroundWorker 触发。

WorldBook 的 `position` 字段继续作为旧数据兼容字段，不参与最终 prompt 位置决策。

Phase A 实现证据：

- `OpenChat/Core/Database/Migrations.swift` v15/v16 创建 `world_book_entry_embedding` 与 `world_book_entry_embedding_meta`。
- `OpenChat/Core/WorldBook/WorldBookVectorStore.swift` 的 KNN 查询限定当前 `worldBookId` 且过滤 disabled entries。
- `OpenChatTests/Core/WorldBookTests/WorldBookVectorStoreTests.swift` 覆盖 worldBook 范围限定与 disabled entry 过滤。

Phase B 实现证据：

- `OpenChat/Core/WorldBook/WorldBookEmbeddingTextBuilder.swift` / `WorldBookEntryHasher.swift` / `WorldBookEmbeddingIndexer.swift`。
- `OpenChat/App/DependencyContainer.swift`：Memory 与 WorldBook 共享 `EmbeddingService`。
- `OpenChatTests/Core/WorldBookTests/WorldBookEmbeddingTextBuilderTests.swift`、`WorldBookEntryHasherTests.swift`、`WorldBookEmbeddingIndexerTests.swift`。

Phase D 实现证据：

- `OpenChat/Features/WorldBook/ViewModels/WorldBookEditorViewModel.swift`：entry save/import 后调用 `WorldBookEmbeddingIndexer`。
- `OpenChat/Core/Database/DatabaseManager+Content.swift` / `DatabaseManager.swift`：delete 和 eraseAllData 显式清理 vector/meta。
- `OpenChat/Features/Settings/ViewModels/SettingsViewModel.swift` / `DataManagementView.swift`：手动 rebuild 世界书语义索引。
- `OpenChatTests/Features/WorldBookTests/WorldBookEditorViewModelTests.swift`、`OpenChatTests/Core/DatabaseTests/DatabaseManagerWorldBookTests.swift`、`OpenChatTests/Features/SettingsTests/SettingsViewModelWorldBookIndexTests.swift`。

Phase C 实现证据：

- `OpenChat/Core/WorldBook/WorldBookRecallModels.swift`：recall result、entry、trace、reason、omission DTO。
- `OpenChat/Core/WorldBook/WorldBookSource.swift`：keyword candidates、semantic KNN、duplicate merge、disabled filter、semantic unavailable fallback。
- `OpenChat/Features/Chat/ViewModels/ChatViewModel+Support.swift`：Chat 主链路先调用 bounded `rebuildMissingOrStale(worldBookId:limit:)`，再把 recalled entries 传入 preselected prompt path。
- `OpenChat/Core/PromptEngine/PromptAssembler.swift`：保留 keyword fallback，同时新增 preselected world book entry path，避免 semantic-only entries 被二次 keyword 过滤。
- `OpenChatTests/Core/WorldBookTests/WorldBookSourceTests.swift`、`OpenChatTests/Core/PromptEngineTests/PromptAssemblerTests.swift`、`OpenChatTests/Features/ChatTests/ChatViewModelPromptAssemblyTests.swift`。

## 4. CharacterBackgroundSource

来源：`CharacterCardRecord`。

职责：

- 输出少量与当前输入相关的角色卡派生背景，例如关键身份、说话风格、长期目标。
- 不替代 Stable Identity。
- 不重复注入完整角色卡。

适用场景：

- 用户提到外貌、职业、背景故事中的具体细节。
- 当前 prompt budget 不允许注入完整角色描述，但允许注入一条短背景提醒。

## 5. ConversationStateBackgroundSource

来源：当前 conversation 的派生状态。

目标状态可能包括：

- 当前场景。
- 未完成事件。
- 近期情绪余波。
- 角色与用户之间的短期互动状态。

注意：

- 这不是长期 memory。
- 这也不是 compression checkpoint。
- 它是本轮对话中需要稳定保留的短期 state。

## 6. Candidate metadata

建议统一 metadata key：

| key | 说明 |
|---|---|
| `sourceTable` | 来源表，如 `memory_entry` / `world_book_entry` |
| `sourceId` | 来源 record id |
| `semanticDistance` | sqlite-vec distance |
| `keywordHits` | 命中的关键词 |
| `priority` | source 自带 priority |
| `importance` | memory importance |
| `fallback` | 是否来自 fallback |
| `sourceUpdatedAt` | 来源更新时间 |
