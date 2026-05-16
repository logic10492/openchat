# Triangle-Consistency

> 审计日期：2026-04-30
> 三边：`arch-test`、`arch-src`、`src-test`

## 校验方法

- `arch-src`：核对 `arch/**` 对模块职责、接口、顺序、数据模型、迁移原则的描述是否符合 `OpenChat/**` 当前源码。
- `arch-test`：核对 arch 中声明的验证标准、测试数量、测试文件和行为契约是否被 `OpenChatTests/**` 覆盖。
- `src-test`：运行当前测试，并检查测试是否覆盖关键源码行为。

## 已执行验证

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

结果：成功。实际设备 iOS 26.5 `iPhone 17 Pro`，Swift Testing 最新报告 `289 tests in 54 suites passed`，`xcodebuild` 结尾为 `** TEST SUCCEEDED **`。同日一次早先 full-suite 重试在 `EmbeddingServiceTests.test_embedding_outputs_384_finite_normalized_values` 处出现 app bundle 内 `MultilingualE5Small.mlmodelc` runtime lookup 失败；随后 `EmbeddingServiceTests` 4 tests / 1 suite passed，后续 full suite 281 tests / 51 suites 和最终 full suite 289 tests / 54 suites 均通过。

本次审计还统计到 `OpenChatTests/` 当前有 20+ 个 Swift 测试文件，full suite 为 289 个 Swift Testing 测试。API/Responses/reasoning、Prompt 四层顺序、Memory embedding/vector/retrieval/extraction-cutoff/recall-trace/fallback-tier/retain-v2-provenance/reflect-contract、checkpoint compression、compression mode 与 WorldBook Vectorization Phase A/B/C/D 测试均已纳入当前基线。2026-05-16 又补充了 Phase D focused coverage 与 full-suite closeout：reflect DTO contract 与 Responses `[Memories]` request-shape；同日补充了世界书向量化 Phase A/B/C schema、vector store、embedding text/hash、indexer/backfill、WorldBookSource、Chat semantic prompt path、CRUD/import/delete/eraseAllData lifecycle maintenance 和 Data Management 手动 rebuild coverage。

2026-05-16 世界书向量化 Phase A 追加验证：`xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,id=2277CB75-AF36-4ABF-84EE-7444C1DD6759'` 在 iOS 26.5 `iPhone 17` 通过，结果为 `261 tests in 47 suites passed`，`** TEST SUCCEEDED **`。

## 总体结论

| 边 | 当前结论 | 说明 |
|---|---|---|
| `src-test` | 通过但不完整 | 全量自动化测试通过；Chat 发送链路当前输入重复风险已有 Feature 级测试覆盖，但仍缺少 UI 自动化测试。 |
| `arch-src` | 局部不一致 | Prompt 时间格式、Memory 目录/触发时机、migration 约束已按当前源码回写；Feature 分层说明仍有漂移，留待 Task 6。 |
| `arch-test` | 基本一致 | 测试数量已回写为 289；Prompt 四层顺序、migration 源码约束、Chat 当前输入去重、Memory embedding/vector/retrieval/extraction-cutoff/recall-trace/fallback-tier/retain-v2-provenance/reflect-contract/Responses request-shape、WorldBook Vectorization Phase A/B/C/D 可靠性已补测试，Feature/UI 分层契约仍需后续补强。 |

## 模块矩阵

| 模块 | `arch-src` | `arch-test` | `src-test` |
|---|---|---|---|
| API Client / Networking | 基本一致 | 基本一致 | 通过。当前覆盖 Chat Completions、Responses、reasoning、baseURL 不强拼 `/v1`、model list。 |
| PromptEngine | 基本一致 | 基本一致 | 函数级测试覆盖四层顺序、labeled context blocks、ISO8601 时间位于 Current Turn；Chat 发送链路覆盖 API request 四层顺序和当前输入去重。 |
| ContextManager | 一致 | 一致 | Truncation、CompressionPolicy、source hash、PreparedHistory、CompressionSummarizer、CheckpointCompactor、checkpoint reuse 与 fallback 均有测试覆盖；Prompt 端到端仍通过 Chat 发送链路测试间接覆盖。 |
| Memory | 一致 | 一致 | `EmbeddingServiceTests`、`VectorStoreTests`、`MemoryManagerRetrievalTests`、`DatabaseManagerMemoryTests`、`MemoryExtractionCutoffTests`、`ChatViewModelPromptAssemblyTests`、`MemoryExtractionParsingTests`、`MigrationTests` 覆盖 bundle 资源、CoreML embedding、sqlite-vec KNN、批量原子写入、recall trace、fallback tiers、recent high-value 查询、sortOrder cutoff 边界、并发消息不跳过、v2 extraction parsing、provenance CRUD、dedupe、source validation、sourceMessageIds 过滤、skip/reinforce 不插入、atomic entry+embedding+provenance write；`MemoryReflectModelsTests` 覆盖 reflect DTO contract；`ResponsesAPIRequestTests` 与 `ChatViewModelPromptAssemblyTests` 覆盖 Responses `[Memories]` request shape；`MemoryExtractionPhaseTests` 覆盖提取状态枚举语义；当前 full suite 为 289 tests / 54 suites。 |
| WorldBook Vectorization Phase A/B/C/D | 一致 | 一致 | `Migrations.swift` v15/v16、`WorldBookEntryEmbeddingMetaRecord`、`WorldBookVectorStore`、`WorldBookEmbeddingTextBuilder`、`WorldBookEntryHasher`、`WorldBookEmbeddingIndexer`、`WorldBookSource`、editor save/import lifecycle wiring、delete cleanup、eraseAllData cleanup 和 Data Management 手动 rebuild 已与 `arch/data-model.md`、`arch/modules/world-book.md`、`arch/modules/background/world-book-vectorization.md`、`arch/modules/background/sources.md`、`arch/modules/prompt-assembly.md` 同步；`MigrationTests`、`WorldBookVectorStoreTests`、`WorldBookEmbeddingTextBuilderTests`、`WorldBookEntryHasherTests`、`WorldBookEmbeddingIndexerTests`、`WorldBookSourceTests`、`PromptAssemblerTests`、`ChatViewModelPromptAssemblyTests`、`WorldBookEditorViewModelTests`、`DatabaseManagerWorldBookTests`、`SettingsViewModelWorldBookIndexTests`、`CriticalSaveFlowTests` 覆盖 schema、索引、cascade、worldBook-scoped KNN、disabled entry 过滤、delete、invalid dimension、text/hash、existing-entry rebuild/backfill、fresh skip、hash mismatch reindex、failure meta、batch continue、keyword + semantic recall、semantic-only prompt 注入、block 兼容、save/import indexing、index failure non-blocking、delete/erase cleanup 和 manual rebuild。BackgroundWorker / BackgroundPacket 仍为后续边界。 |
| Database / Data Model | 基本一致 | 基本一致 | migration/record 测试通过；MigrationTests 保护 migration 源码不引用 runtime Record/enum 符号。 |
| Features / UI | 部分不一致 | 不完整 | 缺少 Feature/ViewModel/UI 路径测试，当前主要靠编译和 Core 测试间接保护。 |
| Settings / Endpoint Model | 部分不一致 | 基本一致 | Endpoint model、API mode、fetch models、会话级 compression mode 持久化测试通过；全局测试基线已更新为 289 tests；Data Management 世界书 semantic index 手动 rebuild 已有 ViewModel 测试覆盖，其他 Settings UI/manual 路径仍需后续验收。 |

## 关键不一致

### 1. Chat 当前输入重复风险

结论：Task 1 已修复当前输入重复注入风险，`src-test` 现在覆盖 Chat 发送链路的去重契约。

证据：

- `generateResponse` 乐观保存本轮 user message 后读取当前会话消息。
- `makePromptHistoryMessages(from:prompt:persistedUserMessage:)` 从 prompt history 中排除当前输入 record。
- `ContextManager.prepareHistory(messages:conversation:endpoint:fixedTokens:)` 只处理过滤后的历史。
- `PromptAssembler.assemble` 追加 `processedHistory` 后再追加一次 `currentInput`。

测试现状：

- `OpenChatTests/Features/ChatTests/ChatViewModelPromptAssemblyTests.swift` 覆盖 `sendMessage()` 真实链路，断言 API request 中当前 user input 只出现一次。

三边判断：

- `arch-src`：Chat 数据流已回写 `promptHistoryMessages` 过滤语义。
- `arch-test`：已有“当前输入只出现一次”的契约测试。
- `src-test`：全量通过且覆盖该风险。

### 2. Prompt 时间上下文格式漂移

结论：Task 2 已统一为 ISO8601，arch、源码、测试一致。

证据：

- `arch/index.md` 声明格式为 `[Time] 2026-04-15T14:30:00+08:00 [/Time]`。
- `arch/modules/prompt-assembly.md` 声明时间上下文为 ISO 8601 含时区格式。
- 源码 `PromptAssembler.makeTimeContext()` 生成 `[Time] <ISO8601> [/Time]`。
- `PromptAssemblerTests` 解析并断言 ISO8601 时间格式。

三边判断：

- `arch-src`：一致。
- `arch-test`：一致。
- `src-test`：通过。

### 3. Prompt 四层顺序与 Current-Turn Context

结论：2026-04-30 已把 PromptAssembler 实现统一为 `Stable Identity -> Stable Conversation State -> Current-Turn Context -> Current Turn` 四层顺序，并补测试锁定源码和真实发送链路。

证据：

- `PromptAssemblyPreview` 输出 `stableIdentityMessages`、`currentTurnContextMessages`、`currentTurnMessage`。
- `PromptAssembler.assemble` 拼接 `stableIdentityMessages + processedHistory + currentTurnContextMessages + currentTurnMessage`。
- `WorldBookEntryPosition.after_system` / `.before_history` 不再拆分最终 prompt 位置，命中条目统一进入 `[World Book Entries]` block。
- 示例对话统一进入 `[Example Dialogs]` block；记忆统一进入 `[Memories]` block；时间上下文位于最后一条 Current Turn user message 内。
- `PromptAssemblerTests` 覆盖四层顺序、labeled block、world book position 兼容和 time-in-current-turn。
- `ChatViewModelPromptAssemblyTests` 覆盖真实 API request 中 history -> example -> memory -> current turn 的顺序，以及当前输入只出现一次。

三边判断：

- `arch-src`：一致。
- `arch-test`：一致。
- `src-test`：通过。

### 4. Database migration 约束修复

结论：Task 4 已把 migration 迁移到本地历史常量，并用源码守卫测试保护。

证据：

- `arch/data-model.md` 迁移原则写明 migration 中不引用 Record 类型。
- `Migrations.Historical` 维护迁移本地历史表名和默认值。
- `MigrationTests.test_migrations_do_not_reference_runtime_record_or_enum_symbols` 禁止 `.databaseTableName`、`APIMode.`、`WorldBookEntryPosition.`、`ContextStrategy.` 等 runtime 符号出现在 migration 源码中。

三边判断：

- `arch-src`：一致。
- `arch-test`：一致。
- `src-test`：通过。

### 5. Memory 文档位置、触发时机与向量可靠性漂移

结论：2026-04-27 已回写 Memory 位置和周期性提取触发的当前源码现实；2026-04-30 已补齐 embedding/vector/retrieval 可靠性修复的 `arch-src`、`arch-test`、`src-test` 证据。

证据：

- `arch/modules/memory/index.md` 文件清单已写回 `Features/CharacterCard/Views/MemoryListView.swift` 和 `Features/CharacterCard/ViewModels/MemoryListViewModel.swift`。
- 当前源码在每次 `generateResponse` 前按 DB 中 `conversation.lastExtractedSortOrder` 计算待提取消息数，达到 `ChatViewModel.minimumPendingMessagesForExtraction == 4` 后同步触发。
- `ChatView.onDisappear` 当前会调用 `triggerMemoryExtraction()`，因此离开当前聊天视图或切换对话可通过视图消失间接触发；App 进入后台 lifecycle hook 仍属于后续 UX/生命周期增强项。

新增可靠性证据：

- `OpenChat/Resources/Models/MultilingualE5Small.mlpackage` 与 `OpenChat/Resources/Models/tokenizer.json` 由 `scripts/generate_xcodeproj.rb` 加入 App Bundle。
- `EmbeddingService` 使用固定 `1 x 256` CoreML 输入，读取 Float16 / Float32 `embeddings`，输出 384 维归一化向量。
- `VectorStore` 在同一 GRDB transaction 中保存 `memory_entry + memory_embedding`；`insert(entries:)` 为协议必填方法，避免非原子默认实现。
- `MemoryManager.retrieveMemories(...)` 在 embedding/model/vector 异常时通过 `recallMemories(...)` 标记 `semanticUnavailable`，fallback 到 keyword + recent high-value；`ChatViewModel+Support` 不再用 `try?` 静默吞掉全部记忆。

测试现状：

- `DatabaseManagerMemoryTests`、`MemoryExtractionParsingTests`、`PromptAssemblerTests` 覆盖 DB、JSON 容错、Prompt 注入。
- `EmbeddingServiceTests` 覆盖模型/tokenizer bundle、tokenizer 输出、CoreML 384 维归一化向量。
- `VectorStoreTests` 覆盖 sqlite-vec KNN、角色隔离、删除同步、维度校验、单条和批量事务回滚。
- `MemoryManagerRetrievalTests` 覆盖语义检索失败 fallback、semantic no-hit、empty index、recall trace、提取向量失败不产生半索引记忆、批次失败整批回滚、v2 dedupe、越界 source range 丢弃、sourceMessageIds 过滤、skip/reinforce 不插入、向量失败不留下 provenance 半成品。
- `DatabaseManagerMemoryTests` 覆盖 recent high-value 查询只返回 relationship / summary / high-importance 条目。
- `MemoryExtractionParsingTests` 覆盖 v1/v2 JSON 解析、provenance CRUD。
- `ChatViewModelPromptAssemblyTests` 覆盖 fallback high-value 记忆最终注入 API request，普通 recent 噪声不注入，以及 ViewModel 重建后仍按 DB sortOrder 边界触发记忆提取。
- `ChatView.onDisappear` 自动触发路径属于当前源码现实，但尚未由端到端测试锁定；该缺口已保留在 `arch/roadmap.md` Phase 6 验证标准中。

三边判断：

- `arch-src`：一致。
- `arch-test`：Memory vector reliability 一致；retain v2 provenance/dedupe 一致；自动触发路径端到端测试待补。
- `src-test`：focused memory/prompt suite 27 tests 通过；该轮 full suite 为 197 tests / 41 suites。

### 6. 分层规则与当前 Feature 装配漂移

结论：源码当前存在 Feature -> App、Feature -> Feature、Shared -> Core 的现实依赖，arch 规则没有承认这些例外。

证据：

- `ChatViewModel` 持有 `AppState`：`OpenChat/Features/Chat/ViewModels/ChatViewModel.swift:13`
- `SidebarView` 位于 Feature 层但读取 `AppState`/`DependencyContainer`：`OpenChat/Features/Support/SidebarView.swift:4`
- `SidebarView` 直接创建多个 Feature 的 View/ViewModel：`OpenChat/Features/Support/SidebarView.swift:47`
- `WorldBookEditorView` 直接打开 CharacterCard editor/detail：`OpenChat/Features/WorldBook/Views/WorldBookEditorView.swift:159`
- `String+Token` 位于 Shared，但调用 Core `TokenCounter`：`OpenChat/Shared/Extensions/String+Token.swift:5`

三边判断：

- `arch-src`：不一致。
- `arch-test`：没有自动化边界测试。
- `src-test`：编译通过，但无法证明架构边界满足。

拆分计划：`arch/AntiEntropy/layering-repair-plan.md`。该问题跨 App shell、Feature navigation、Shared/Core 边界，不与 Prompt/Database 修复混在同一执行波次。

### 7. arch 中测试数量和状态说明回写

结论：2026-04-30 该轮曾把基线回写为 197 tests；API-client 对齐测试、Prompt 四层顺序测试、Memory embedding/vector/retrieval 可靠性测试和 compression mode 测试已纳入当时基线。当前全局基线见本文顶部的 289 tests。

证据：

- `arch/index.md` 当前已回写为“289 个 Swift Testing 测试 / 54 个 suites 全部通过”。
- `arch/roadmap.md` 当前已回写为“当前通过的 Swift Testing 测试（289 个 / 54 suites）”。
- `arch/modules/memory/index.md` 已回写 Memory embedding/vector/retrieval/extraction-cutoff/recall-trace/fallback-tier/retain-v2-provenance/reflect-contract/Responses-request-shape 可靠性覆盖与该计划波次的 251-test full suite 历史结果；当前全局基线见本文顶部的 289-test full suite。
- `arch/modules/settings/api-endpoint.md` 不再作为本轮测试数量来源；全局基线以本文件和 `arch/index.md` 为准。
- `arch/modules/api-client.md` 不在 Task 5 允许编辑范围内，本次不修改。

三边判断：

- `arch-test`：Task 5 允许范围内已一致；`arch/modules/api-client.md` 属于本次前置未提交改动，另行保持最小同步。
- `src-test`：通过。
- `arch-src`：不直接涉及源码。

## 当前可信结论

1. 当前工作区能编译并通过全量 Swift Testing：289 tests passed。
2. API Client / Responses / reasoning / baseURL 行为在当前工作区内有较强测试支撑。
3. Prompt/Context/Memory 的 Core 函数级测试可用，Chat 真实发送链路已有当前输入去重、Responses `[Memories]` folding 与 checkpoint invalidation 测试；Memory 提取 cutoff 已有 sortOrder 边界测试，retain v2 provenance/dedupe/source validation 和 reflect DTO contract 已有测试覆盖；仍缺少 UI 自动化覆盖。
4. arch 已回写 Prompt 四层顺序、Memory 位置与 embedding/vector/retrieval/extraction-cutoff/recall-trace/fallback-tier/retain-v2-provenance/reflect-contract/Responses-request-shape 可靠性、WorldBook Vectorization Phase A/B/C/D、migration 约束、checkpoint compression/compression mode 语义和 289-test 基线；Feature 边界漂移留待后续分层修复计划。

## 修复顺序状态

| 顺序 | 项目 | 当前状态 |
|---:|---|---|
| 1 | 补 Chat 拼装链路测试，锁定“当前输入只出现一次” | Closed：`ChatViewModelPromptAssemblyTests` 覆盖 request messages 与 DB 存储。 |
| 2 | Prompt 时间格式统一为 ISO8601 | Closed：源码输出 `[Time] <ISO8601> [/Time]`，测试解析验证。 |
| 3 | 明确 Prompt 四层顺序与 Current-Turn Context | Closed：统一为四层顺序，PromptAssemblerTests 与 ChatViewModelPromptAssemblyTests 覆盖。 |
| 4 | 回写 Memory 目录和触发时机现实 | Closed：文档写回前置同步提取、onDisappear 兜底、sortOrder cutoff 增量提取与 15% memory budget。 |
| 5 | 清理测试数量和验证命令说明 | Closed：全局状态统一为 289 tests 基线。 |
| 6 | 分层修复或 App shell 例外归档 | Open：已拆出 `arch/AntiEntropy/layering-repair-plan.md`。 |

## 修复写回（2026-04-27）

- `src-test`：新增 Chat 发送链路测试，锁定当前输入只进入 request messages 一次。
- `arch-src`：Prompt 时间上下文统一为当前输入后的 `[Time] <ISO8601> [/Time]`；Prompt 段顺序统一为四层顺序；migration 源码不再引用 runtime Record/enum 符号。
- `arch-test`：PromptAssemblerTests 覆盖四层顺序、ISO8601、labeled blocks 和 world book position 兼容；MigrationTests 覆盖 migration 源码约束；EmbeddingServiceTests / VectorStoreTests / MemoryManagerRetrievalTests / ChatViewModelPromptAssemblyTests 覆盖 Memory 可靠性。
- 分层漂移：Task 6 将单独处理，不在本次 prompt/db/doc 修复中混入跨层搬迁。

## Checkpoint Compression 三边一致性写回（2026-04-30）

范围：`OpenChat/Core/Database/*Compression*`、`OpenChat/Core/ContextManager/*Compression*`、`OpenChat/Core/ContextManager/CheckpointCompactor.swift`、`OpenChat/Features/Chat/ViewModels/ChatViewModel.swift`、`OpenChatTests/Core/ContextManagerTests/*`、`OpenChatTests/Core/DatabaseTests/CompressionCheckpointDatabaseTests.swift`、`OpenChatTests/Features/ChatTests/ChatViewModelPromptAssemblyTests.swift`、`arch/modules/context-manager.md`、`arch/data-model.md`。

### arch-src

- `arch/data-model.md` 已新增 `conversation_compression_checkpoint` 表，字段与 `CompressionCheckpointRecord`、`v11_create_compression_checkpoints` 一致。
- `arch/modules/context-manager.md` 已从“每轮临时摘要”改为 checkpoint compression：复用有效 checkpoint，超过 `CompressionPolicy.autoCompactTokenLimit` 才压缩，成功后保存，失败 fallback truncation。
- `.github/instructions/context-manager.instructions.md` 已同步会话级 compression mode、standard/highIntelligence 阈值、checkpoint 阈值匹配复用、checkpoint invalidation 和不写半成品规则。

### arch-test

- `MigrationTests` 覆盖 v11 表存在、列集合、conversation delete cascade。
- `CompressionCheckpointDatabaseTests` 覆盖 latest checkpoint 查询和受影响 checkpoint 删除。
- `CompressionPolicyTests` 覆盖 standard 模式 `maxContextTokens × 0.40`、highIntelligence 模式 `maxContextTokens × 0.25 × 0.90`、小上下文 40% 兼容和固定段 token 扣减。
- `MigrationTests` 覆盖 `conversation.compressionMode` v12 列和默认值。
- `CompressionCheckpointReuseTests` 覆盖切换压缩模式后不复用旧阈值 checkpoint。
- `ChatViewModelPromptAssemblyTests` 覆盖对话设置持久化 `compressionMode`。
- `CompressionSourceHasherTests`、`PreparedHistoryTests`、`CompressionSummarizerTests` 覆盖 source hash、旧 PromptAssembler 兼容出口和 checkpoint summarizer request。
- `CheckpointCompactorTests` 与 `CompressionCheckpointReuseTests` 覆盖低于阈值不调用网络、超过阈值保存 checkpoint、复用 checkpoint、压缩失败 fallback 且不保存 checkpoint。
- `ChatViewModelPromptAssemblyTests` 覆盖编辑/删除消息时删除受影响 checkpoint。

### src-test

- Focused context/database/chat checkpoint suite 已通过：
  `xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:OpenChatTests/CheckpointCompactorTests -only-testing:OpenChatTests/CompressionCheckpointReuseTests -only-testing:OpenChatTests/CompressionStrategyTests`
- Chat prompt suite 已通过：`xcodebuild test ... -only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests`，7 tests passed。
- 该轮 full suite：218 tests / 45 suites，`** TEST SUCCEEDED **`。

## Memory Extraction Cutoff & Observability 三边一致性写回（2026-05-13）

范围：`OpenChat/Core/Memory/MemoryManager.swift`、`OpenChat/Core/Database/Migrations.swift`、`OpenChat/Core/Database/Records/ConversationRecord.swift`、`OpenChat/Features/Chat/ViewModels/ChatViewModel*.swift`、`OpenChat/Features/Chat/Views/ChatView.swift`、`OpenChat/Features/Chat/Views/MemoryExtractionIndicator.swift`（新增）、`OpenChat/Features/Chat/Models/MemoryExtractionPhase.swift`（新增）、Memory 相关测试和 arch 文档。

### arch-src

- `arch/data-model.md` 已新增 `conversation.lastExtractedSortOrder` 列，字段与 `v13_add_last_extracted_sort_order` 一致。
- `arch/modules/memory/` 已从单一 index 拆分为 `architecture.md`、`data-model.md`、`embedding-vector-store.md`、`extraction.md`、`retrieval-prompt.md`、`ui-management.md`、`testing.md` 和 `hindsight-lite.md`；触发时机、sortOrder cutoff、UI 指示器、Phase A retrieval-order-preserving prompt trim、Phase B recall trace / fallback tiers 与 Hindsight-lite 未实现边界均已回写。
- `arch/modules/chat.md` 已更新 4.6 记忆提取触发说明。

### arch-test

- `MemoryExtractionCutoffTests` 覆盖 sortOrder cutoff 边界、首次提取全量处理、消息不足跳过、并发消息不被跳过。
- `MemoryExtractionPhaseTests` 覆盖 isActive 和 Equatable 语义。
- `ChatViewModelPromptAssemblyTests` 覆盖发送链路按 DB sortOrder 边界触发前置同步提取。
- `MigrationTests` 覆盖 v13 列存在性和 NULL 默认值。

### src-test

- Focused suite 38 tests / 3 suites passed。
- 该轮 full suite 218 tests / 45 suites passed，`** TEST SUCCEEDED **`。

## Memory Recall Ordering Phase A 三边一致性写回（2026-05-14）

范围：`OpenChat/Core/PromptEngine/PromptAssembler.swift`、`OpenChatTests/Core/PromptEngineTests/PromptAssemblerTests.swift`、Memory / Prompt / AntiEntropy 相关文档。

### arch-src

- `arch/modules/memory/retrieval-prompt.md` 已从“当前排序风险”改为 Phase A 后的 prompt 裁剪顺序事实。
- `arch/modules/memory/index.md` 已记录 `[Memories]` 按 `MemoryManager` 输出顺序注入，`PromptAssembler` 只按输入顺序和 token budget 裁剪。
- `arch/modules/prompt-assembly.md` 已移除 `memories.sortedByImportanceDescending` 伪代码。
- `arch/modules/memory/hindsight-lite.md` 已标记 Phase A implemented，同时保留 fallback tiers、trace、provenance、reflect 仍为规划。

### arch-test

- `PromptAssemblerTests.test_memory_trim_preserves_retrieval_order_when_budget_drops_high_importance_memory` 覆盖输入 `[A, B, C]`、importance `C > B > A`、预算只容纳 A/B 时仍保持 retrieval order。

### src-test

- Baseline focused suite：34 tests / 4 suites passed。
- Phase A focused suite：`PromptAssemblerTests` 14 tests / 1 suite passed。
- Post-change focused suite：35 tests / 4 suites passed。
- Full suite：219 tests / 45 suites passed。

## Memory Recall Trace / Fallback Tier Phase B 三边一致性写回（2026-05-14）

范围：`OpenChat/Core/Memory/MemoryManager.swift`、`OpenChat/Core/Memory/MemoryRecallModels.swift`、`OpenChat/Core/Database/DatabaseManager+Memory.swift`、`OpenChatTests/Core/MemoryTests/MemoryManagerRetrievalTests.swift`、`OpenChatTests/Core/DatabaseTests/DatabaseManagerMemoryTests.swift`、`OpenChatTests/Features/ChatTests/ChatViewModelPromptAssemblyTests.swift`、Memory / AntiEntropy / plan / harness 文档。

### arch-src

- `arch/modules/memory/retrieval-prompt.md` 已写回 recall v2：semantic / keyword / recent high-value candidates、fallback tier、rank fusion 和 trace contract。
- `arch/modules/memory/index.md`、`architecture.md`、`embedding-vector-store.md` 和 `hindsight-lite.md` 已记录 `MemoryRecallResult` / `MemoryRecallTrace` 当前 source reality。
- `arch/AntiEntropy/problem.md` 已关闭 P2 fallback 不可解释和 recent-by-time fallback 两项问题，同时保留 provenance、dedupe、reflect、Responses request shape 为后续阶段。

### arch-test

- `MemoryManagerRetrievalTests` 覆盖 semantic order、keyword trace、semantic unavailable、semantic no-hit、empty index、兼容 `retrieveMemories(...)` 输出顺序。
- `DatabaseManagerMemoryTests` 覆盖 `fetchRecentHighValueMemories(...)` 筛掉普通 recent 噪声并按 relationship / summary / importance 排序。
- `ChatViewModelPromptAssemblyTests` 覆盖 semantic failure 后只注入 high-value memory，不注入普通 recent 噪声。

### src-test

- Phase B focused suite：28 tests / 3 suites passed。
- Broader focused suite：49 tests / 5 suites passed。
- Full suite：225 tests / 45 suites passed，`** TEST SUCCEEDED **`。
- 2026-05-14 22:49-22:52 +0800 重新执行同一 B 阶段 focused、broader focused 和 full suite，结果仍为 28 / 49 / 225 tests 全部通过。

## WorldBook Vectorization Phase A 三边一致性写回（2026-05-16）

范围：`OpenChat/Core/Database/Migrations.swift`、`OpenChat/Core/Database/Records/WorldBookEntryEmbeddingMetaRecord.swift`、`OpenChat/Core/Database/DatabaseManager+Content.swift`、`OpenChat/Core/WorldBook/*`、`OpenChatTests/Core/DatabaseTests/MigrationTests.swift`、`OpenChatTests/Core/WorldBookTests/WorldBookVectorStoreTests.swift`、世界书向量化相关 arch/plan 文档。

### arch-src

- `arch/data-model.md` 已新增 `world_book_entry_embedding` 和 `world_book_entry_embedding_meta`，字段与 v15/v16 migration 和 `WorldBookEntryEmbeddingMetaRecord` 一致。
- `arch/source-tree.md` 已新增 `Core/WorldBook` 与 `WorldBookEntryEmbeddingMetaRecord`。
- `arch/modules/world-book.md` 已记录 Phase A 当前能力：schema、meta record、`WorldBookVectorStore`，并明确 B/C/D 当时未实现；B/C 已在后续同日写回中完成。
- `arch/modules/background/world-book-vectorization.md` 和 `arch/modules/background/sources.md` 已从“完全未实现”更新为“Phase A 已实现，Background/Source 当时未实现”；C 已在后续同日写回中完成。
- `arch/modules/prompt-assembly.md` 已明确 Prompt 输出形态未变；semantic-only 世界书条目在后续 Phase C 已进入 prompt。

### arch-test

- `MigrationTests` 覆盖 v15 table、384 维 vector insert、v16 columns、status/model index、meta cascade，并把 `EmbeddingService.` 加入 migration runtime reference forbidden list。
- `WorldBookVectorStoreTests` 覆盖 upsert、KNN 限定当前 worldBook、disabled entry 过滤、delete 同步清理 vector/meta、invalid dimension 不写入。

### src-test

- Baseline focused command：`xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MigrationTests' '-only-testing:OpenChatTests/VectorStoreTests' '-only-testing:OpenChatTests/PromptAssemblerTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests'`，结果 62 tests / 4 suites passed。
- Phase A focused command：`xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MigrationTests' '-only-testing:OpenChatTests/WorldBookVectorStoreTests'`，结果 39 tests / 2 suites passed。
- Phase A broader focused command：`xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MigrationTests' '-only-testing:OpenChatTests/VectorStoreTests' '-only-testing:OpenChatTests/WorldBookVectorStoreTests' '-only-testing:OpenChatTests/PromptAssemblerTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests'`，结果 72 tests / 5 suites passed。
- Full suite command：`xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,id=2277CB75-AF36-4ABF-84EE-7444C1DD6759'`，实际设备 iOS 26.5 `iPhone 17`，结果 261 tests / 47 suites passed，`** TEST SUCCEEDED **`。
- 同日一次 `iPhone 17 Pro` full-suite 尝试在测试体执行前被 Simulator 拒绝启动，错误为 `Busy ("Application failed preflight checks")`；换用上述 `iPhone 17` 设备后通过。

### 未完成边界

- Phase B：embedding text builder、hash、indexer/backfill 已在后续同日写回中完成。
- Phase C 已在后续同日写回中完成。
- 当时边界：D 阶段 lifecycle maintenance 不在 Phase A 范围；当前已由后续 Phase D 写回关闭，见本文 `WorldBook Vectorization Phase D 三边一致性写回`。

## WorldBook Vectorization Phase B 三边一致性写回（2026-05-16）

范围：`OpenChat/App/DependencyContainer.swift`、`OpenChat/Core/Memory/EmbeddingService.swift`、`OpenChat/Core/WorldBook/WorldBookEmbeddingTextBuilder.swift`、`WorldBookEntryHasher.swift`、`WorldBookEmbeddingIndexer.swift`、`WorldBookVectorStore.swift`、`OpenChatTests/Core/WorldBookTests/*`、世界书向量化相关 arch/plan 文档。

### arch-src

- `arch/modules/world-book.md` 已从 Phase A 更新为 Phase A/B 当前能力：stable embedding text、content hash、indexer/backfill、failed meta 和 `DependencyContainer` 共享 embedding service。
- `arch/modules/background/world-book-vectorization.md` 已把 indexer/backfill 从未实现目标改为当前源码事实，同时保留当时未实现的 Background、WorldBookSource、Chat semantic recall、CRUD/import/delete wiring；WorldBookSource / Chat semantic recall 已在后续 Phase C 写回中完成。
- `arch/modules/memory/embedding-vector-store.md` 已记录 `EmbeddingService.embeddingModelId == "multilingual-e5-small-384:v1"`，以及 Memory 与 WorldBook 共用 `EmbeddingProvider` / E5 passage embedding。
- `arch/source-tree.md`、`arch/data-model.md`、`arch/modules/background/sources.md` 已同步新增 Phase B 文件和现有边界。

### arch-test

- `WorldBookEmbeddingTextBuilderTests` 覆盖 title/keywords/content trim 拼接、空 keywords 兼容和 bad keywords JSON typed error。
- `WorldBookEntryHasherTests` 覆盖 hash 稳定性、title/keywords/content 变化会变、priority/isEnabled/position/updatedAt 不影响 hash。
- `WorldBookEmbeddingIndexerTests` 覆盖 migration 后 existing entries backfill、fresh meta skip、hash mismatch reindex、embedding failure 写 failed meta 不删除 entry、bad keywords JSON 写 failed meta、batch rebuild 单条失败后继续。

### src-test

- Phase B focused command：`xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/WorldBookEmbeddingTextBuilderTests' '-only-testing:OpenChatTests/WorldBookEntryHasherTests' '-only-testing:OpenChatTests/WorldBookEmbeddingIndexerTests'`，结果 12 tests / 3 suites passed，`** TEST SUCCEEDED **`。
- Phase B broader focused command：`xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MigrationTests' '-only-testing:OpenChatTests/VectorStoreTests' '-only-testing:OpenChatTests/WorldBookVectorStoreTests' '-only-testing:OpenChatTests/WorldBookEmbeddingTextBuilderTests' '-only-testing:OpenChatTests/WorldBookEntryHasherTests' '-only-testing:OpenChatTests/WorldBookEmbeddingIndexerTests' '-only-testing:OpenChatTests/PromptAssemblerTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests'`，结果 84 tests / 8 suites passed，`** TEST SUCCEEDED **`。
- Full suite command：`xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,id=2277CB75-AF36-4ABF-84EE-7444C1DD6759'`，实际设备 iOS 26.5 `iPhone 17`，结果 273 tests / 50 suites passed，`** TEST SUCCEEDED **`。
- 同日一次 `iPhone 17 Pro` full-suite 尝试在测试体执行前被 Simulator 拒绝启动，错误为 `Busy ("Application failed preflight checks")`；换用上述 `iPhone 17` 设备后通过。

### 未完成边界

- Phase C 已在后续同日写回中完成。
- 当时边界：D 阶段 lifecycle maintenance 不在 Phase B 范围；当前已由后续 Phase D 写回关闭。

## WorldBook Vectorization Phase C 三边一致性写回（2026-05-16）

范围：`OpenChat/Core/WorldBook/WorldBookRecallModels.swift`、`WorldBookSource.swift`、`OpenChat/Core/PromptEngine/PromptAssembler.swift`、`OpenChat/Features/Chat/ViewModels/ChatViewModel.swift`、`ChatViewModel+Support.swift`、`OpenChat/App/DependencyContainer.swift`、`OpenChat/ContentView.swift`、`OpenChatTests/Core/WorldBookTests/WorldBookSourceTests.swift`、`PromptAssemblerTests.swift`、`ChatViewModelPromptAssemblyTests.swift`、世界书向量化相关 arch/plan 文档。

### arch-src

- `arch/modules/world-book.md` 已记录 `WorldBookSource` keyword + semantic 融合、bounded lazy rebuild、preselected prompt path；后续 Phase D 写回已补充 save/import/delete/eraseAllData lifecycle maintenance。
- `arch/modules/prompt-assembly.md` 已记录 Chat 主链路使用 `previewWithPreselectedWorldBookEntries(...)` / `assembleWithPreselectedWorldBookEntries(...)`，旧调用方保留 keyword fallback。
- `arch/modules/background/sources.md` 与 `arch/modules/background/world-book-vectorization.md` 已把 Phase C 从未实现目标更新为当前源码事实，同时保留 BackgroundWorker 未实现。
- `arch/data-model.md` 在该阶段记录 Phase A-C source reality；后续 Phase D 写回已补充 CRUD/import/delete/eraseAllData 当前实现。
- `.github/instructions/prompt-engine.instructions.md` 已同步规则：PromptAssembler 不做 embedding/KNN/DB 访问，Chat 主链路消费 WorldBookSource 预选条目。

### arch-test

- `WorldBookSourceTests` 覆盖 keyword-only、semantic-only、keyword+semantic duplicate merge、disabled world book、disabled entry、semantic failure fallback。
- `PromptAssemblerTests` 覆盖 semantic candidate 仍输出兼容 `[World Book Entries]` block。
- `ChatViewModelPromptAssemblyTests` 覆盖 semantic-only world book entry 通过真实 Chat 主链路进入 API request。

### src-test

- Baseline focused command：`xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MigrationTests' '-only-testing:OpenChatTests/VectorStoreTests' '-only-testing:OpenChatTests/PromptAssemblerTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests'`，结果 67 tests / 4 suites passed。
- Phase C focused command：`xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/WorldBookSourceTests' '-only-testing:OpenChatTests/PromptAssemblerTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests'`，结果 34 tests / 3 suites passed，`** TEST SUCCEEDED **`。
- Phase A/B/C broader focused command：`xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MigrationTests' '-only-testing:OpenChatTests/VectorStoreTests' '-only-testing:OpenChatTests/WorldBookVectorStoreTests' '-only-testing:OpenChatTests/WorldBookEmbeddingTextBuilderTests' '-only-testing:OpenChatTests/WorldBookEntryHasherTests' '-only-testing:OpenChatTests/WorldBookEmbeddingIndexerTests' '-only-testing:OpenChatTests/WorldBookSourceTests' '-only-testing:OpenChatTests/PromptAssemblerTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests'`，结果 92 tests / 9 suites passed，`** TEST SUCCEEDED **`。
- Full suite command：`xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`，实际设备 iOS 26.5 `iPhone 17 Pro`，结果 281 tests / 51 suites passed，`** TEST SUCCEEDED **`。
- 同日一次 full-suite 重试在 `EmbeddingServiceTests.test_embedding_outputs_384_finite_normalized_values` 处出现 app bundle 内 `MultilingualE5Small.mlmodelc` runtime lookup 失败；随后 `EmbeddingServiceTests` 4 tests / 1 suite passed，最终 full suite 281 tests / 51 suites passed。当前未复现为稳定失败。

### 未完成边界

- 当时边界：Chat lazy rebuild 能补 existing/missing/stale，但该阶段尚未负责 CRUD/delete 清理；当前已由后续 Phase D 写回关闭。
- BackgroundWorker / BackgroundPacket 未切换；Prompt 输出仍是 `[World Book Entries]`。

## WorldBook Vectorization Phase D 三边一致性写回（2026-05-16）

范围：`DatabaseManager` cleanup、WorldBook editor save/import、Settings Data Management rebuild、Phase D focused tests、世界书向量化相关 arch/harness 文档。

### arch-src

- `arch/data-model.md` 已把世界书向量化状态更新为 Phase A-D 当前实现，并记录 delete / eraseAllData 不能只依赖 FK cascade，必须显式清理 sqlite-vec virtual table。
- `arch/modules/world-book.md` 已记录 `WorldBookEditorViewModel.saveEntry(_:)` / `importEntries(_:)` 的 non-blocking indexing policy、delete/clear cleanup 和 Data Management rebuild 入口。
- `arch/modules/background/world-book-vectorization.md` 与 `arch/modules/background/sources.md` 已把 CRUD/import/delete/eraseAllData 从 Phase D 目标更新为当前源码事实，同时保留 BackgroundWorker / BackgroundPacket 未实现边界。

### arch-test

- `WorldBookEditorViewModelTests` 覆盖 save entry 后 index、index failure 保留 entry、import batch save/index、新建 worldBook import 后复用已保存 id。
- `DatabaseManagerWorldBookTests` 覆盖 delete entry、delete worldBook、eraseAllData 不留下 vector/meta 残留。
- `SettingsViewModelWorldBookIndexTests` 覆盖手动 rebuild 可 backfill existing entries。
- `CriticalSaveFlowTests` 继续覆盖 editor save 不允许 `try?` 静默 dismiss。

### src-test

- Baseline focused command：`xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MigrationTests' '-only-testing:OpenChatTests/VectorStoreTests' '-only-testing:OpenChatTests/PromptAssemblerTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests'`，结果 69 tests / 4 suites passed。
- Phase D focused command：`xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/WorldBookEditorViewModelTests' '-only-testing:OpenChatTests/DatabaseManagerWorldBookTests' '-only-testing:OpenChatTests/CriticalSaveFlowTests' '-only-testing:OpenChatTests/SettingsViewModelWorldBookIndexTests'`，结果 9 tests / 4 suites passed，`** TEST SUCCEEDED **`。
- Final A/B/C/D focused acceptance command：`xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MigrationTests' '-only-testing:OpenChatTests/WorldBookVectorStoreTests' '-only-testing:OpenChatTests/WorldBookEmbeddingTextBuilderTests' '-only-testing:OpenChatTests/WorldBookEntryHasherTests' '-only-testing:OpenChatTests/WorldBookEmbeddingIndexerTests' '-only-testing:OpenChatTests/WorldBookSourceTests' '-only-testing:OpenChatTests/PromptAssemblerTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests' '-only-testing:OpenChatTests/WorldBookEditorViewModelTests' '-only-testing:OpenChatTests/DatabaseManagerWorldBookTests' '-only-testing:OpenChatTests/CriticalSaveFlowTests' '-only-testing:OpenChatTests/SettingsViewModelWorldBookIndexTests'`，结果 94 tests / 12 suites passed，`** TEST SUCCEEDED **`。
- Full suite command：`xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`，实际设备 iOS 26.5 `iPhone 17 Pro`，结果 289 tests / 54 suites passed，`** TEST SUCCEEDED **`。

### 未完成边界

- BackgroundWorker / BackgroundPacket / WorldBookBackgroundSource 统一调度仍未实现。
- Prompt 输出仍是兼容 `[World Book Entries]` block；当前 Phase D 只关闭 lifecycle maintenance，不改变 prompt packet contract。
