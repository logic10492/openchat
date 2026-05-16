# Memory Hindsight-lite Repair - Propagation Audit

> 日期：2026-05-14
> 范围：`docs/superpowers/plans/2026-05-14-memory-hindsight-lite-repair/03_phase_a_recall_ordering.md`、`04_phase_b_recall_trace_fallback.md`、`05_phase_c_retain_v2_provenance.md`
> 阶段：A - Recall Ordering；B - Recall Trace / Fallback Tier；C - Retain v2 / Provenance / Dedupe
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
- token budget 与"至少保留第一条"行为不变。
- 排序权现在回到 recall 输出侧：`MemoryManager` 当前输出顺序就是 `PromptAssembler` 裁剪顺序；未来 Background / Hindsight-lite 可在进入 `PromptAssembler` 前完成 fusion / tie-break。

质量结论：

- P1 "语义检索顺序在 Prompt 注入前被 importance 重排"已关闭。
- 本阶段没有扩大 Swift import 图或 Feature/Core 边界。
- Phase A 时 P2 fallback tiers、recall trace、provenance、Responses API system folding 仍未实现；本文件后续 Phase B/C 章节记录已关闭。

## 5. 验证

详见 `evidence.txt`。

## 6. Phase B 目标

关闭 AE P2 中两个 Memory recall 问题：

- fallback / distance threshold 缺少 trace 与可解释性。
- semantic fail / no hit 后只按 `createdAt DESC` 注入 recent memory，容易把近期噪声塞进 prompt。

本阶段只改变 Memory 层输出能力和 fallback 策略：

- 新增 `MemoryRecallResult` / `MemoryRecallTrace` / reason / fallback / omission DTO。
- `MemoryManager.retrieveMemories(...) -> [MemoryEntryRecord]` 保持兼容，内部调用 `recallMemories(...)`。
- fallback 改成 semantic / keyword / recent high-value tiers。
- `PromptAssembler`、`ContextManager`、`APIClient` 不消费 trace，不改变 `[Memories]` request 层级。

## 7. Phase B Baseline 传播链

行为链路：

```text
ChatViewModel.generateResponse
  -> MemoryManager.retrieveMemories(for:query:limit:)
  -> EmbeddingProvider.embed(query, isQuery: true)
  -> MemoryVectorStore.search(...)
  -> DatabaseManager.fetchMemories(...)
  -> PromptAssembler.preview(memories:)
  -> PromptAssembler.assemble(...)
```

Phase B 后：

```text
ChatViewModel.generateResponse
  -> MemoryManager.retrieveMemories(for:query:limit:)
  -> MemoryManager.recallMemories(for:query:limit:)
  -> semantic candidates + keyword candidates + recent high-value candidates
  -> MemoryRecallResult(entries, trace)
  -> entries.map(\.memory)
  -> PromptAssembler.preview/assemble
```

## 8. Phase B 修改后传播评估

源码变更：

- `OpenChat/Core/Memory/MemoryRecallModels.swift`：新增 recall result / entry / trace / fallback / omission DTO，全部 `Sendable`。
- `OpenChat/Core/Memory/MemoryManager.swift`：新增 `recallMemories(...)`，保留 `retrieveMemories(...)` 兼容入口；semantic 搜索 limit 扩大到 `max(limit * 2, 20)`；新增 keyword candidates、recent high-value candidates 和稳定 fusion。
- `OpenChat/Core/Database/DatabaseManager+Memory.swift`：新增 `fetchRecentHighValueMemories(...)`，只返回 `relationship`、`summary` 或 `importance >= 70` 的条目，并按 type priority / importance / createdAt 排序。
- `OpenChat.xcodeproj/project.pbxproj`：只把 `MemoryRecallModels.swift` 加入 app target；签名配置未改。

传播结果：

- Chat/Prompt 调用签名不变：`ChatViewModel+Support` 仍调用 `retrieveMemories(...)`，`PromptAssembler` 仍只接收 `[MemoryEntryRecord]`。
- `PromptAssembler` 不理解 semantic distance、fallback reason 或 trace；排序权继续在 Memory 层。
- 没有新增 DB migration；`memory_entry` schema 未变。
- `fetchRecentMemories(...)` 保留普通 recent 查询，但不再作为 prompt fallback 路径。
- Phase B 关闭 P2 fallback 可解释性和 recent-by-time fallback 问题；provenance / dedupe / reflect / Responses request shape 仍未实现。

质量结论：

- 传播面限定在 `Core/Memory` / `Core/Database` / tests / docs。
- 未新增 Feature 间依赖，未扩大 App -> Features -> Core -> Shared 方向。
- project 文件是最小 source membership diff，没有生成脚本造成的 UUID churn。
- 2026-05-14 22:49-22:52 +0800 重新执行 B 阶段验收：focused 28 tests / 3 suites、broader focused 49 tests / 5 suites、full suite 225 tests / 45 suites 均通过；后置传播评估仍确认 Chat/Prompt/API 接口未变。

## 9. Phase C 目标

关闭 AE P2 中 retain 问题：

- 提取 prompt 缺少角色卡、已有记忆、source 边界和去重约束。
- 没有 provenance schema，无法追踪记忆来源和提取质量。

本阶段追加 retain v2：

- `memory_entry_provenance` companion table（v14 migration）。
- 结构化提取输入（character summary + existing memory hints + message id/sortOrder）。
- `ExtractedMemory` 扩展 v2 字段（source range、confidence、tags、dedupeKey、action）。
- 同批 dedupe、source range validation、atomic entry+embedding+provenance 写入。

## 10. Phase C Baseline 传播链

Phase C 前：

```text
MemoryManager.extractMemories
  -> callExtractionAPI(messages:endpoint:)
  -> role: content 拼接文本
  -> [ExtractedMemory(content, type, importance)]
  -> EmbeddingProvider.embed
  -> VectorStore.insert(entries:)
  -> memory_entry + memory_embedding
```

Phase C 后：

```text
MemoryManager.extractMemories
  -> callExtractionAPI(messages:characterCard:existingMemoryHints:endpoint:)
  -> MemoryExtractionInput(character + hints + messages)
  -> [ExtractedMemory(v2 fields)]
  -> validateAndFilter(source range, message ids, action == skip)
  -> dedupeWithinBatch(dedupeKey / normalized content)
  -> EmbeddingProvider.embed
  -> VectorStore.insert(entries:provenances:)
  -> memory_entry + memory_embedding + memory_entry_provenance
```

## 11. Phase C 修改后传播评估

源码变更：

- `OpenChat/Core/Database/Records/MemoryEntryProvenanceRecord.swift`（新增）：GRDB Record，定义 companion table 字段与 JSON 编解码辅助。
- `OpenChat/Core/Database/Migrations.swift`：追加 `v14_create_memory_entry_provenance` migration，只创建新表，不修改旧 migration。
- `OpenChat/Core/Database/DatabaseManager+Memory.swift`：新增 provenance CRUD（save/fetch/delete）。
- `OpenChat/Core/Memory/VectorStore.swift`：新增 `insert(entries:provenances:)`，在同一 GRDB write transaction 中保存 entry + embedding + provenance。
- `OpenChat/Core/Memory/MemoryDependencies.swift`：在 `MemoryVectorStore` 协议中新增 `insert(entries:provenances:)` 方法要求，并提供默认空实现保持测试 mock 兼容。
- `OpenChat/Core/Memory/MemoryManager.swift`：
  - `callExtractionAPI` 改为结构化输入；fallback 到纯文本时仍兼容旧路径。
  - `ExtractedMemory` 扩展 v2 字段与 `Decodable` 解析。
  - 新增 `fetchExistingMemoryHints`、`validateAndFilter`、`dedupeWithinBatch`、`makeProvenance`。
  - `extractMemories` 使用 `VectorStore.insert(entries:provenances:)` 原子写入。
- `OpenChatTests/Core/MemoryTests/MemoryManagerRetrievalTests.swift`：新增 dedupe、越界 source range、向量失败不留下 provenance 半成品测试。
- `OpenChatTests/Core/MemoryExtractionParsingTests.swift`：新增 v2 字段解析、provenance CRUD、旧 memory 无 provenance 兼容测试。
- `OpenChatTests/Core/DatabaseTests/MigrationTests.swift`：新增 v14 表存在、列集合、外键 cascade 测试。
- `OpenChat.xcodeproj/project.pbxproj`：已通过 `ruby scripts/generate_xcodeproj.rb` 重新生成，新增 `MemoryEntryProvenanceRecord.swift` 引用；签名配置保持原有值。

传播结果：

- `ChatViewModel+Support` 仍调用 `MemoryManager.extractMemories(from:)`，签名不变。
- `PromptAssembler` 仍只消费 `[MemoryEntryRecord]`，不理解 provenance。
- `MemoryEntryRecord` 主表未修改，旧 memory 无 provenance 时仍能检索和注入。
- 原子写入保证 embedding/vector 失败时 entry 和 provenance 一起回滚，不留半成品。
- 传播面限定在 `Core/Memory` / `Core/Database` / tests / docs。

质量结论：

- P2 "提取 prompt 缺少角色卡、已有记忆、source 边界和去重约束"已关闭。
- 未新增 Feature 间依赖，未扩大 App -> Features -> Core -> Shared 方向。
- 2026-05-14 23:57 +0800 Phase C 初次验收：focused 103 tests / 7 suites、full suite 240 tests / 45 suites 均通过。
- 2026-05-15 19:20-19:21 +0800 Phase C 最终复验：core focused subset 66 tests / 3 suites、C full focused suite 107 tests / 7 suites、full suite 244 tests / 45 suites 均通过；后置传播评估仍确认 Chat/Prompt/API 接口未变，传播面限定在 `Core/Memory` / `Core/Database` / tests / docs。
- Phase D 后剩余 open：reflect LLM executor / UI 入口 / `memory_entry_link` migration、Background block request-shape、BackgroundWorker 统一调度（均为后续独立计划）。

## 12. Phase D 目标

关闭当前 Memory 包内最后两个验收点：

- 低频 reflect 的最小 Memory 层 contract。
- 当前 `[Memories]` 在 Responses API system folding 下的 request shape。

本阶段不实现：

- reflect LLM executor。
- UI “整理记忆”入口。
- `memory_entry_link` migration / CRUD。
- `Core/Background` / `BackgroundWorker` / `BackgroundPacket`。

## 13. Phase D Baseline 传播链

Phase D 前：

```text
PromptAssembler.assemble
  -> [Memories] system block
  -> APIClient.streamMessage
  -> ResponsesAPIRequest joins all system messages into instructions
```

缺口：没有专门测试证明 `[Memories]` 在 Responses mode 下不丢失、不进入 user input、current input 不重复。

Phase D 后：

```text
ResponsesAPIRequestTests
  -> [Memories] folds into instructions
ChatViewModelPromptAssemblyTests
  -> Responses request capture confirms current input appears once
MemoryReflectModelsTests
  -> source/basedOn ids must be non-empty
```

## 14. Phase D 修改后传播评估

源码变更：

- `OpenChat/Core/Memory/MemoryReflectModels.swift`（新增）：定义 `MemoryReflectRequest`、`MemoryReflectObservation`、`MemoryReflectTask`、`MemoryReflectAction`、`MemoryEntryLinkRelation` 和 typed contract error。
- `OpenChatTests/Core/MemoryTests/MemoryReflectModelsTests.swift`（新增）：覆盖 source ids、basedOn ids、content、confidence clamp 和 relation 集合。
- `OpenChatTests/Core/NetworkingTests/ResponsesAPITests.swift`：新增 request-level `[Memories]` folding 验收。
- `OpenChatTests/Features/ChatTests/ChatViewModelPromptAssemblyTests.swift`：新增 Responses mode 端到端 request 捕获。
- `OpenChat.xcodeproj/project.pbxproj` / scheme：通过 `ruby scripts/generate_xcodeproj.rb` 重新生成以纳入新增 Swift 文件；签名配置仍由脚本保持。

传播结果：

- `ResponsesAPIRequest.swift` 未改，当前实现被测试承认为 provider adapter 行为。
- `ChatViewModel.generateResponse(...)` 未增加 reflect 调用；reflect 不进入每轮主聊天链路。
- `PromptAssembler` 不消费 reflect observation，也不消费 Background candidate。
- 未新增 DB migration；`memory_entry_link` 只作为 relation contract 留给后续。
- 未新增 Feature 间依赖，未引入 `Core/Background` 生产代码。

质量结论：

- Phase D 关闭 P2 Responses `[Memories]` request-shape 风险。
- Phase D 建立 reflect 最小 contract，但不声称实现 observation synthesis executor。
- 后续 Background / reflect 持久化计划必须复用本阶段 contract，并重新验收 Background block request-shape。

验证记录：

- 2026-05-16 02:55 +0800 reflect contract focused suite：`MemoryReflectModelsTests` 5 tests / 1 suite passed（`iPhone 17` UDID `4435A025-9E0B-40AF-9BE0-DE0648F77AED`）。
- 2026-05-16 02:57 +0800 Responses suite-name command：21 tests / 5 suites passed（`iPhone 17 Pro` UDID `6F61E759-8E3C-4951-B929-0A63AA47BFBB`）。
- 2026-05-16 02:58 +0800 Chat + reflect focused suite：17 tests / 2 suites passed（`iPhone 17 Pro` UDID `F8D0D88B-71FD-471F-855A-B2B5D8267117`）。
- 两次中间重试在进入测试断言前被 simulator launch preflight `Busy` 拒绝，按环境 runner failure 记录，不作为源码断言失败。

## 15. Lead closeout

Full-suite closeout 先暴露一个测试隔离问题：`MemoryManagerRetrievalTests` 中两个 retain v2 测试在 full suite 并发执行时使用默认 `KeychainAPIKeyStore()`，触发 simulator Keychain duplicate item `-25299`。本轮只在测试文件内修复：所有该文件内的 `MemoryManager` 构造都注入 `InMemoryAPIKeyStore()`；生产默认值仍为 `KeychainAPIKeyStore()`。

验证记录：

- 2026-05-16 03:07 +0800 `MemoryManagerRetrievalTests` focused recheck：15 tests / 1 suite passed（`iPhone 17 Pro Max` UDID `B20ADF19-7ADC-427D-9EBE-A76712A3E2AE`）。
- 2026-05-16 03:10 +0800 final full suite：251 tests / 46 suites passed（`iPhone 17e` UDID `4DC4D569-DFFE-41E4-9383-2A6386B5B26E`）。

结论：Memory Hindsight-lite A/B/C/D 与 Lead closeout 均已完成；剩余 reflect executor、`memory_entry_link` 持久化、UI 入口和 Background 接入均属于后续独立计划。
