# 跨对话记忆模块

> 所属层：`Core/Memory/` + `Features/CharacterCard/`
> 主要依赖：`Core/Database`、`Core/Networking`、`Core/PromptEngine`

本目录记录 OpenChat 当前跨对话记忆系统的实现事实、测试边界和下一步 Hindsight-lite 规划。`index.md` 只保留导航和总览；具体流程拆到独立文档，避免单页同时承担设计、源码证据、历史修复和未来规划。

## 1. 当前能力

- 以角色卡为单位保存跨对话记忆，同一角色的不同 conversation 共享 `memory_entry`。
- 在 Chat 发送链路中，用户消息持久化后按 `conversation.lastExtractedSortOrder` 计算待处理消息数；达到 4 条后，在检索记忆之前同步调用 `MemoryManager.extractMemories(from:)`。
- 记忆条目内容由当前会话配置的聊天 API 以结构化 JSON 抽取，输入包含角色卡摘要、已有记忆 hints 和消息 id/sortOrder；输出字段为 `content`、`type`、`importance`，并支持 v2 来源元数据（source range、confidence、tags、dedupeKey、action）。
- 条目保存前使用本地 CoreML MultilingualE5Small 生成 384 维 embedding，生产 `VectorStore` 在一个 GRDB write transaction 内同时写入 `memory_entry`、`memory_embedding` 与 `memory_entry_provenance`（retain v2）。
- 每次发送消息时，当前输入先生成 query embedding，再通过 sqlite-vec KNN 检索相关记忆；语义检索异常或结果低于阈值时进入 fallback tier：keyword candidate 优先，必要时补少量 relationship / summary / high-importance recent high-value 记忆。
- 检索结果按 `MemoryManager` 输出顺序作为 `[Memories] ... [/Memories]` labeled system block 注入 Current-Turn Context；`PromptAssembler` 只按输入顺序和 token budget 裁剪，不再按 `importance` 重排。
- 角色详情页提供记忆列表、搜索、单条删除和清空入口；Chat 内联显示提取中、已提取和失败状态。
- Phase D 已新增低频 reflect 的 Memory 层 contract（request / observation / relation），但尚未接入 UI、LLM executor 或 `memory_entry_link` 持久化。

## 2. 文档结构

| 文档 | 内容 |
|---|---|
| [architecture.md](architecture.md) | 模块边界、文件职责、与 Chat/Prompt/Database 的交互 |
| [data-model.md](data-model.md) | `memory_entry`、`memory_embedding`、`conversation.lastExtractedSortOrder` 与迁移约束 |
| [embedding-vector-store.md](embedding-vector-store.md) | CoreML embedding、E5 前缀、sqlite-vec 写入/检索一致性 |
| [extraction.md](extraction.md) | 自动提取触发、LLM JSON 抽取、解析容错、增量 cutoff |
| [retrieval-prompt.md](retrieval-prompt.md) | 语义检索、fallback、prompt 注入、Phase A 后的裁剪顺序 |
| [ui-management.md](ui-management.md) | Chat 提取指示器与角色记忆管理 UI |
| [testing.md](testing.md) | 测试覆盖、验证命令和当前已知缺口 |
| [hindsight-lite.md](hindsight-lite.md) | 轻量 retain / recall / reflect 完善设计，用于关闭剩余 memory problem |
| [../background/index.md](../background/index.md) | Background 架构：Memory 当前通过 `MemoryBackgroundSource` 参与 `BackgroundPacket` 兼容调度 |

## 3. 核心数据流

### 3.1 发送链路

```
ChatViewModel.generateResponse
  -> save user MessageRecord
  -> shouldExtractMemories(conversation.lastExtractedSortOrder, messages)
  -> MemoryManager.extractMemories       // threshold reached; pre-retrieval
  -> BackgroundManager.prepare
       -> MemoryRecallTool / MemoryBackgroundSource
       -> BackgroundWorker
       -> BackgroundPacket
  -> PromptAssembler.preview(backgroundPacket:)
  -> ContextManager.prepareHistory
  -> PromptAssembler.assemble(backgroundPacket:) // inject compatible [Memories]
  -> APIClient.streamMessage
```

### 3.2 提取链路

```
MemoryManager.extractMemories
  -> fetch latest ConversationRecord
  -> fetch messages where sortOrder > lastExtractedSortOrder
  -> APIClient.sendMessage               // LLM returns JSON memories
  -> parse [ExtractedMemory] with v2 field support
  -> validateAndFilter(source range, message ids, skip/reinforce)
  -> dedupeWithinBatch(dedupeKey / normalized content)
  -> EmbeddingProvider.embed(content, isQuery: false)
  -> MemoryVectorStore.insert(entries:provenances:)  // atomic memory + vector + provenance write
  -> update conversation.lastExtractedSortOrder
```

### 3.3 检索链路

```
MemoryManager.retrieveMemories
  -> MemoryManager.recallMemories
  -> semantic candidates + keyword candidates + recent high-value candidates
  -> MemoryRecallResult(entries, trace)
  -> entries.map(\.memory)
  -> PromptAssembler.trim(memories:)     // legacy direct path; preserve input order
  -> [Memories] system block
```

Current production Chat path uses:

```
MemoryManager.recallMemories
  -> MemoryRecallTool
  -> MemoryBackgroundSource
  -> BackgroundCandidate(sourceType: .memory)
  -> BackgroundWorker
  -> BackgroundPacket
  -> PromptAssembler(... backgroundPacket:)
  -> [Memories] system block
```

## 4. 设计原则

1. **聊天主流程优先**：检索失败应降级为 keyword / recent high-value 记忆或空记忆，不阻断用户发送；提取失败通过 UI 和日志可观测。
2. **写入原子性优先**：自动提取生成的 `memory_entry` 必须和 `memory_embedding` 同事务写入，避免半索引记忆。
3. **角色隔离**：KNN 检索必须限定 `characterCardId`，避免跨角色污染。
4. **事实与计划分离**：当前实现承诺扁平 `event/fact/relationship/summary` 条目、recall trace、fallback tiers、retain v2 provenance、同批 dedupe 和 reflect DTO contract；reflect executor、`memory_entry_link` 持久化和跨批自动合并仍是规划。
5. **文档与源码同步**：涉及触发时机、迁移、prompt 注入顺序、错误处理和测试结论的变更必须同步更新本目录及相关 `arch/AntiEntropy/*` 文档。

## 5. Background 目标关系

当前生产 Chat 主链路不再直接把 `MemoryManager.retrieveMemories(...)` 的数组交给 `PromptAssembler`。2026-05-17 Phase 4B 已新增内部 read-only `MemoryRecallTool`，包装 `MemoryManager.recallMemories(...)` / `MemoryRecallResult`，并通过 focused tests 验证顺序和 trace metadata 透传。2026-05-17 Phase 4D 已新增 target-backed `MemoryBackgroundSource`，把 `MemoryRecallResult.entries` 映射为 `BackgroundCandidate(sourceType: .memory)`，并通过 focused tests 验证顺序、metadata、character boundary 和不按 token budget 裁剪。2026-05-17 Phase 5/6 已由 `BackgroundManager.prepare(...) -> BackgroundWorker -> BackgroundPacket -> PromptAssembler(... backgroundPacket:)` 接入 Chat / Prompt 兼容链路，最终仍输出 `[Memories]` block。

边界：Memory retain / recall 仍属于 `Core/Memory`；世界书向量化和 bounded rebuild 不属于 Memory。`BackgroundPolicy.tokenBudget` 只控制跨 source candidate selection，最终 request body 内 `[Memories]` 是否被裁剪仍由 `PromptAssembler` 的 token budget 负责。统一 `[Background]` block、Character / ConversationState sources 和 synthesis worker 仍是后续计划。

迁移要求：

- 已完成 retrieval ordering Phase A：`PromptAssembler` 不再用 `importance` 重排 memory。
- 已完成 recall trace / fallback Phase B：`MemoryRecallResult` / trace 能向 Background 暴露 fallback、distance、selected ids 和 omission diagnostics。
- 已完成 retain v2 provenance / dedupe Phase C：`memory_entry_provenance` 保存来源和提取元数据；结构化输入帮助 LLM 判断重复/强化/跳过；同批 dedupe 和 source validation 减少噪声。
- 已完成 Phase D 最小 contract / request-shape：`MemoryReflectModels` 锁定 based-on 约束；Responses API folding 已测试当前 `[Memories]` 不丢失且不进入 user message。
- 已完成：memory recall 输出暴露为 read-only `MemoryRecallTool`；该 tool 不写 DB、不联网、不拼 prompt，也不重新实现 Memory rank fusion。
- 已完成：`MemoryBackgroundSource` 进入 target，并以 focused tests 验证 tool result 到 `BackgroundCandidate(sourceType: .memory)` 的顺序和 metadata 映射。
- 已完成：`BackgroundWorker` 统一与 WorldBook 候选做 deterministic selection，并生成 `BackgroundPacket` diagnostics；CharacterState / ConversationState 尚未实现。
- 已完成：`PromptAssembler.preview(... backgroundPacket:)` / `assemble(... backgroundPacket:)` 消费 packet-selected memory entries，并通过 `BackgroundAssembler` 保持 `[Memories]` 兼容输出。

## 6. 实现证据

| 关注点 | 源码位置 |
|---|---|
| 自动提取触发 | `OpenChat/Features/Chat/ViewModels/ChatViewModel+Support.swift` |
| 提取/检索编排 | `OpenChat/Core/Memory/MemoryManager.swift` |
| recall DTO / trace | `OpenChat/Core/Memory/MemoryRecallModels.swift` |
| reflect DTO contract | `OpenChat/Core/Memory/MemoryReflectModels.swift` |
| embedding 协议边界 | `OpenChat/Core/Memory/MemoryDependencies.swift` |
| CoreML embedding | `OpenChat/Core/Memory/EmbeddingService.swift` |
| sqlite-vec 存储 | `OpenChat/Core/Memory/VectorStore.swift` |
| DB record/CRUD | `OpenChat/Core/Database/Records/MemoryEntryRecord.swift`, `OpenChat/Core/Database/Records/MemoryEntryProvenanceRecord.swift`, `OpenChat/Core/Database/DatabaseManager+Memory.swift` |
| migrations | `OpenChat/Core/Database/Migrations.swift` |
| prompt 注入 | `OpenChat/Core/PromptEngine/PromptAssembler.swift`, `OpenChat/Core/PromptEngine/TokenBudget.swift` |
| Chat 状态 UI | `OpenChat/Features/Chat/Models/MemoryExtractionPhase.swift`, `OpenChat/Features/Chat/Views/MemoryExtractionIndicator.swift` |
| 管理 UI | `OpenChat/Features/CharacterCard/Views/MemoryListView.swift`, `OpenChat/Features/CharacterCard/ViewModels/MemoryListViewModel.swift` |
