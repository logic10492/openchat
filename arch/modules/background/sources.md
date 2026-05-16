# BackgroundSource 统一候选来源

> 状态：BackgroundWorker 目标架构规划尚未实现；Memory / WorldBook read-only source tool 尚未实现；`WorldBookSource` keyword + semantic 最小闭环已在 2026-05-16 Phase C 落地。

## 1. Source 类型

```swift
enum BackgroundSourceType: String, Codable, Sendable {
    case memory
    case worldBook
    case character
    case conversationState
}
```

## 1.1 Source tool 前置边界

在实现 `BackgroundWorker` 前，Memory 与 WorldBook 应先暴露内部 read-only source tool：

| Tool | 包装对象 | 输出 | 禁止事项 |
|---|---|---|---|
| `MemoryRecallTool` | `MemoryManager.recallMemories(...)` | `MemoryRecallResult` / trace | 不复制 rank fusion、不写 DB、不拼 prompt |
| `WorldBookRecallTool` | `WorldBookSource.recallEntries(...)` | `WorldBookRecallResult` / trace | 不复制 keyword+semantic fusion、不触发索引 rebuild、不拼 prompt |

这些 tool 不是普通角色工具，不进入角色回复的 tool call，也不向用户暴露。它们只作为 BackgroundSource adapter 的输入边界，让后续 `BackgroundWorker` 消费统一候选，而不是直接依赖 Memory / WorldBook 的内部实现。

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

当前状态：2026-05-16 Phase A/B 已实现 schema、meta record、`WorldBookVectorStore`、embedding text/hash 和 `WorldBookEmbeddingIndexer` rebuild/backfill；Phase C 已实现 `WorldBookSource`，Chat prompt 主链路会先执行 bounded rebuild，再召回 keyword + semantic 融合候选，并继续输出 `[World Book Entries]`；Phase D 已实现 save/import/delete/eraseAllData 维护和 Data Management 手动 rebuild。`WorldBookBackgroundSource` / `BackgroundWorker` 统一调度仍未实现。

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
