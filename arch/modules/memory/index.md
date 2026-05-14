# 跨对话记忆模块

> 所属层：`Core/Memory/` + `Features/CharacterCard/`
> 主要依赖：`Core/Database`、`Core/Networking`、`Core/PromptEngine`

本目录记录 OpenChat 当前跨对话记忆系统的实现事实、测试边界和下一步 Hindsight-lite 规划。`index.md` 只保留导航和总览；具体流程拆到独立文档，避免单页同时承担设计、源码证据、历史修复和未来规划。

## 1. 当前能力

- 以角色卡为单位保存跨对话记忆，同一角色的不同 conversation 共享 `memory_entry`。
- 在 Chat 发送链路中，用户消息持久化后按 `conversation.lastExtractedSortOrder` 计算待处理消息数；达到 4 条后，在检索记忆之前同步调用 `MemoryManager.extractMemories(from:)`。
- 记忆条目内容由当前会话配置的聊天 API 以 JSON 形式抽取，字段为 `content`、`type`、`importance`。
- 条目保存前使用本地 CoreML MultilingualE5Small 生成 384 维 embedding，生产 `VectorStore` 在一个 GRDB write transaction 内同时写入 `memory_entry` 与 `memory_embedding`。
- 每次发送消息时，当前输入先生成 query embedding，再通过 sqlite-vec KNN 检索相关记忆；语义检索异常或结果低于阈值时 fallback 到近期记忆。
- 检索结果作为 `[Memories] ... [/Memories]` labeled system block 注入 Current-Turn Context。
- 角色详情页提供记忆列表、搜索、单条删除和清空入口；Chat 内联显示提取中、已提取和失败状态。

## 2. 文档结构

| 文档 | 内容 |
|---|---|
| [architecture.md](architecture.md) | 模块边界、文件职责、与 Chat/Prompt/Database 的交互 |
| [data-model.md](data-model.md) | `memory_entry`、`memory_embedding`、`conversation.lastExtractedSortOrder` 与迁移约束 |
| [embedding-vector-store.md](embedding-vector-store.md) | CoreML embedding、E5 前缀、sqlite-vec 写入/检索一致性 |
| [extraction.md](extraction.md) | 自动提取触发、LLM JSON 抽取、解析容错、增量 cutoff |
| [retrieval-prompt.md](retrieval-prompt.md) | 语义检索、fallback、prompt 注入、当前排序风险 |
| [ui-management.md](ui-management.md) | Chat 提取指示器与角色记忆管理 UI |
| [testing.md](testing.md) | 测试覆盖、验证命令和当前已知缺口 |
| [hindsight-lite.md](hindsight-lite.md) | 轻量 retain / recall / reflect 完善设计，用于关闭剩余 memory problem |
| [../background/index.md](../background/index.md) | 目标 Background 架构：Memory 未来作为 `MemoryBackgroundSource` 参与统一调度 |

## 3. 核心数据流

### 3.1 发送链路

```
ChatViewModel.generateResponse
  -> save user MessageRecord
  -> shouldExtractMemories(conversation.lastExtractedSortOrder, messages)
  -> MemoryManager.extractMemories       // threshold reached; pre-retrieval
  -> MemoryManager.retrieveMemories      // semantic KNN + recent fallback
  -> PromptAssembler.preview
  -> ContextManager.prepareHistory
  -> PromptAssembler.assemble            // inject [Memories]
  -> APIClient.streamMessage
```

### 3.2 提取链路

```
MemoryManager.extractMemories
  -> fetch latest ConversationRecord
  -> fetch messages where sortOrder > lastExtractedSortOrder
  -> APIClient.sendMessage               // LLM returns JSON memories
  -> parse [ExtractedMemory]
  -> EmbeddingProvider.embed(content, isQuery: false)
  -> MemoryVectorStore.insert(entries:)  // atomic memory + vector write
  -> update conversation.lastExtractedSortOrder
```

### 3.3 检索链路

```
MemoryManager.retrieveMemories
  -> EmbeddingProvider.embed(query, isQuery: true)
  -> MemoryVectorStore.search(query, characterCardId, limit)
  -> filter distance < 1.5
  -> fetch MemoryEntryRecord by ids, restore KNN order
  -> merge recent memories, deduplicate
  -> PromptAssembler.trim(memories:)
  -> [Memories] system block
```

## 4. 设计原则

1. **聊天主流程优先**：检索失败应降级为近期记忆或空记忆，不阻断用户发送；提取失败通过 UI 和日志可观测。
2. **写入原子性优先**：自动提取生成的 `memory_entry` 必须和 `memory_embedding` 同事务写入，避免半索引记忆。
3. **角色隔离**：KNN 检索必须限定 `characterCardId`，避免跨角色污染。
4. **事实与计划分离**：当前实现只承诺扁平 `event/fact/relationship/summary` 条目；Hindsight-lite 的 provenance、recall trace、fallback tiers、reflect observation 都还只是规划。
5. **文档与源码同步**：涉及触发时机、迁移、prompt 注入顺序、错误处理和测试结论的变更必须同步更新本目录及相关 `arch/AntiEntropy/*` 文档。

## 5. Background 目标关系

当前 Memory 仍由 `ChatViewModel` 调用 `MemoryManager.retrieveMemories(...)` 后传给 `PromptAssembler` 注入 `[Memories]`。目标架构中，Memory 会变成 `MemoryBackgroundSource`：负责产生长期记忆候选，不再直接拥有 prompt 注入权。

迁移要求：

- 先修复 retrieval ordering，让语义相关性优先于 `importance` 重排。
- 引入 `MemoryRecallResult` / trace 后，Memory source 可以向 Background 暴露 fallback、distance、omission diagnostics。
- 再把 memory retrieval 输出包装为 `BackgroundCandidate(sourceType: .memory)`。
- `BackgroundWorker` 统一与 WorldBook / CharacterState / ConversationState 候选排序和裁剪。
- `PromptAssembler` 最终只消费 `BackgroundPacket` 或由 `BackgroundAssembler` 生成的 prompt block。

## 6. 实现证据

| 关注点 | 源码位置 |
|---|---|
| 自动提取触发 | `OpenChat/Features/Chat/ViewModels/ChatViewModel+Support.swift` |
| 提取/检索编排 | `OpenChat/Core/Memory/MemoryManager.swift` |
| embedding 协议边界 | `OpenChat/Core/Memory/MemoryDependencies.swift` |
| CoreML embedding | `OpenChat/Core/Memory/EmbeddingService.swift` |
| sqlite-vec 存储 | `OpenChat/Core/Memory/VectorStore.swift` |
| DB record/CRUD | `OpenChat/Core/Database/Records/MemoryEntryRecord.swift`, `OpenChat/Core/Database/DatabaseManager+Memory.swift` |
| migrations | `OpenChat/Core/Database/Migrations.swift` |
| prompt 注入 | `OpenChat/Core/PromptEngine/PromptAssembler.swift`, `OpenChat/Core/PromptEngine/TokenBudget.swift` |
| Chat 状态 UI | `OpenChat/Features/Chat/Models/MemoryExtractionPhase.swift`, `OpenChat/Features/Chat/Views/MemoryExtractionIndicator.swift` |
| 管理 UI | `OpenChat/Features/CharacterCard/Views/MemoryListView.swift`, `OpenChat/Features/CharacterCard/ViewModels/MemoryListViewModel.swift` |
