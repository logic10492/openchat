# Propagation Audit

> 审计日期：2026-04-27
> 范围：`OpenChat/`、`OpenChatTests/`、`arch/`

## 审计方法

本次审计先只读检查现有约束、源码、测试和 arch 文档，然后再写入本文件。Swift 项目没有现成的 import 图脚本，因此使用了两类证据：

1. 静态类型引用图：扫描 Swift `struct/class/enum/protocol/actor` 定义与跨文件引用，估算文件间传播面。
2. 行为链路复核：对 Chat 发送、API 模式分发、Prompt/Context、Memory、Database migration、Feature 导航装配做源码行号复核。

该图是启发式传播图，不等同于 Swift AST 或编译器依赖图。结论中把“图指标”和“源码行为证据”分开记录。

## 静态图摘要

| 指标 | 当前值 |
|---|---:|
| App Swift 文件 | 95 |
| Test Swift 文件 | 20 |
| App 类型定义 | 138 |
| Test 类型定义 | 31 |
| 源码跨文件类型引用边 | 329 |
| 测试到源码类型引用边 | 63 |
| 启发式 SCC 数 | 3 |
| 分层/Feature 隔离可疑边 | 40 |

### 高直接传播面

| D | 文件 |
|---:|---|
| 18 | `OpenChat/Features/Chat/ViewModels/ChatViewModel.swift` |
| 16 | `OpenChat/Core/Memory/MemoryManager.swift` |
| 13 | `OpenChat/Features/Chat/ViewModels/ChatViewModel+Support.swift` |
| 13 | `OpenChat/Core/PromptEngine/PromptAssembler.swift` |
| 11 | `OpenChat/Features/Support/SidebarView.swift` |
| 10 | `OpenChat/Features/WorldBook/Views/WorldBookEditorView.swift` |
| 10 | `OpenChat/Features/Settings/ViewModels/APIEndpointEditorViewModel.swift` |
| 10 | `OpenChat/ContentView.swift` |
| 9 | `OpenChat/Core/Networking/APIClient.swift` |
| 9 | `OpenChat/Core/Database/Migrations.swift` |

### 高入边传播面

| T | 文件 |
|---:|---|
| 18 | `OpenChat/Core/Database/DatabaseManager.swift` |
| 16 | `OpenChat/Core/Networking/ChatMessage.swift` |
| 15 | `OpenChat/Core/Database/Records/MessageRecord.swift` |
| 14 | `OpenChat/Core/Database/Records/ConversationRecord.swift` |
| 14 | `OpenChat/Core/Database/Records/CharacterCardRecord.swift` |
| 13 | `OpenChat/App/AppState.swift` |
| 11 | `OpenChat/Core/Database/Records/WorldBookRecord.swift` |
| 11 | `OpenChat/Core/Database/Records/APIEndpointRecord.swift` |
| 10 | `OpenChat/App/DependencyContainer.swift` |
| 10 | `OpenChat/Core/Networking/APIEndpointConfig.swift` |

## SCC 观察

本次启发式图发现 3 个强连通簇。它们不是 Swift import 层面的循环，但表示修改其中任意类型时容易牵动同簇文件。

1. Networking/Memory 响应簇：
   - `OpenChat/Core/Memory/MemoryManager.swift`
   - `OpenChat/Core/Networking/APIClient.swift`
   - `OpenChat/Core/Networking/APIRequest.swift`
   - `OpenChat/Core/Networking/APIResponse.swift`
   - `OpenChat/Core/Networking/ResponsesAPIRequest.swift`
   - `OpenChat/Core/Networking/ResponsesAPIResponse.swift`
2. Context/Message 簇：
   - `OpenChat/Core/ContextManager/ContextStrategy.swift`
   - `OpenChat/Core/Database/Records/ConversationRecord.swift`
   - `OpenChat/Core/Database/Records/MessageRecord.swift`
3. Endpoint model 簇：
   - `OpenChat/Core/Database/Records/APIEndpointRecord.swift`
   - `OpenChat/Core/Database/Records/EndpointModelRecord.swift`

## 行为链路结论

### Chat 发送链路

链路：

`ContentView` -> `ChatViewModel` -> `DatabaseManager` -> `MemoryManager` -> `PromptAssembler.preview` -> `ContextManager.prepareHistory` -> `PromptAssembler.assemble` -> `APIClient.streamMessage` -> UI/DB 回写。

关键证据：

- `ContentView` 在 detail 中创建 `ChatViewModel`，注入 `databaseManager`、`apiClient`、`contextManager`、`memoryManager`、`titleGenerator`、`appState`：`OpenChat/ContentView.swift:79`
- `ChatViewModel+Support.generateResponse` 在 `persistUserMessage=true` 时先保存 user message，再读取 `currentMessages`，随后构造 `promptHistoryMessages`。
- `makePromptHistoryMessages(from:prompt:persistedUserMessage:)` 会移除本轮乐观保存的 user record；重新生成/编辑路径会移除与 `currentInput` 匹配的最后一条 user record。
- `PromptAssembler.preview(...)`、`ContextManager.prepareHistory(messages:conversation:endpoint:fixedTokens:)`、`PromptAssembler.assemble(...)` 均使用过滤后的 `promptHistoryMessages`。
- `PromptAssembler.assemble(...)` 在过滤后的 `processedHistory` 之后追加一次 `currentInput`。

结论：当前输入重复注入风险已修复。`promptHistoryMessages` 在 preview/history/assemble 前过滤掉本轮 current input record，`OpenChatTests/Features/ChatTests/ChatViewModelPromptAssemblyTests.swift` 覆盖 API request 中当前输入只出现一次，同时验证 DB 中本轮 user message 只存储一次。

### API 模式链路

链路：

`Settings/APIEndpointEditor` -> `endpoint_model` -> `APIEndpointConfig` -> `APIClient.sendMessage/streamMessage` -> Chat Completions 或 Responses 分发。

关键证据：

- `APIClient.sendMessage` 按 `endpoint.apiMode` 分发：`OpenChat/Core/Networking/APIClient.swift:14`
- Chat Completions URL 为 `{baseURL}/chat/completions`：`OpenChat/Core/Networking/APIClient.swift:158`
- Responses URL 为 `{baseURL}/responses`：`OpenChat/Core/Networking/APIClient.swift:289`
- `APIRequest` 当前支持 Codable、`max_tokens`/`max_completion_tokens` 分支和 `stream_options.include_usage`：`OpenChat/Core/Networking/APIRequest.swift:3`
- `ResponsesAPIRequest` 固定 `store=false`，并把 system messages 合并为 `instructions`：`OpenChat/Core/Networking/ResponsesAPIRequest.swift:14`

结论：API 模式链路当前是本次审计中 `arch-src-test` 对齐度最高的区域。注意这部分依赖审计开始前已有的未提交改动，报告记录的是当前工作区现实，不代表已提交基线。

### Prompt/Context 链路

链路：

`PromptAssembler.preview` 计算 Stable Identity、Current-Turn Context、Current Turn 与 fixedTokens -> `ContextManager.prepareHistory` 处理 Stable Conversation State -> `PromptAssembler.assemble` 输出四层顺序。

关键证据：

- 两阶段调用由 `ChatViewModel+Support` 串联：`OpenChat/Features/Chat/ViewModels/ChatViewModel+Support.swift:81`、`OpenChat/Features/Chat/ViewModels/ChatViewModel+Support.swift:92`、`OpenChat/Features/Chat/ViewModels/ChatViewModel+Support.swift:98`
- `PromptAssembler.preview` 使用 40% 总预算并输出 `stableIdentityMessages`、`currentTurnContextMessages`、`currentTurnMessage`：`OpenChat/Core/PromptEngine/PromptAssembler.swift:14`
- `TokenBudget` 分配 example/worldBook/memory/history：`OpenChat/Core/PromptEngine/TokenBudget.swift:18`
- `CompressionStrategy` 失败后由 `ContextManager` fallback 到 truncation：`OpenChat/Core/ContextManager/ContextManager.swift:26`

结论：主链路可运行且有测试覆盖；2026-04-30 已把 Prompt 四层顺序回写到 arch，并保留 Chat 当前输入去重修复证据。

- 时间上下文为 `[Time] ISO 8601 含时区 [/Time]`，源码 `PromptAssembler.makeTimeContext()` 生成该片段，并由 `makeCurrentTurnContent(...)` 放入最后一条 Current Turn user message。
- 世界书 position 字段不再拆分最终 prompt 位置；当前轮命中条目统一进入 `[World Book Entries]` block，位于 `[Example Dialogs]` 之后、`[Memories]` 之前。

> 修复写回：`docs/superpowers/plans/2026-04-27-triangle-consistency-repair.md` Task 1 已通过 Feature 级测试和 `promptHistoryMessages` 过滤修复当前输入重复注入风险。

### Memory 链路

链路：

`ChatViewModel` 前置提取记忆 → `MemoryManager.extractMemories` → `DatabaseManager` 更新 `conversation.lastExtractedSortOrder` → `MemoryManager.retrieveMemories` → `EmbeddingService`/`VectorStore`/`DatabaseManager` → `PromptAssembler` 注入记忆。

关键证据：

- 前置同步提取（在检索前）：`OpenChat/Features/Chat/ViewModels/ChatViewModel+Support.swift` `generateResponse` 中先按 DB 中 `conversation.lastExtractedSortOrder` 计算待提取消息数，达到 `minimumPendingMessagesForExtraction` 后同步 await `extractMemories`
- 发送时检索记忆（提取后）：`OpenChat/Features/Chat/ViewModels/ChatViewModel+Support.swift` `generateResponse` 中调用 `retrieveMemories`
- cutoff 使用 `conversation.lastExtractedSortOrder`（message sortOrder 边界），不再使用 `latestMemoryDate`（memory_entry.createdAt）
- `MemoryManager.extractMemories` 成功后更新 `conversation.lastExtractedSortOrder = messages.last?.sortOrder`
- UI 反馈通过 `extractionPhase` 状态驱动 `MemoryExtractionIndicator`（替代旧的 `MemoryMarkerView` + `MessageDisplayItem.memoryMarker`）
- `ChatView.onDisappear` 保留 fire-and-forget 调用 `triggerMemoryExtraction()`
- `MemoryManager.extractMemories` 使用 `conversation.lastExtractedSortOrder` 增量提取和 API 提取：`OpenChat/Core/Memory/MemoryManager.swift`
- 向量保存使用批量原子写入；失败时整批回滚，不留半索引记忆：`OpenChat/Core/Memory/VectorStore.swift`

结论：源码已具备 Memory 主链路；2026-05-13 修复了 cutoff 边界问题和提取可观测性：

- cutoff 从 `latestMemoryDate(conversationId:)`（基于 memory_entry.createdAt）改为 `conversation.lastExtractedSortOrder`（基于 message sortOrder），避免并发写入导致消息被永久跳过。
- 提取时机从响应完成后异步触发改为下一次 generateResponse 中前置同步等待，新提取的记忆立即可用于当前轮检索。
- UI 反馈从非持久化的 `MessageDisplayItem.memoryMarker` 改为 `MemoryExtractionPhase` 状态驱动的 `MemoryExtractionIndicator`，支持 extracting/completed/failed 三态指示。
- `ChatView.onDisappear` 保留 fire-and-forget 提取。
- `arch/modules/memory/index.md` 已同步更新 6.1 触发时机、6.2 提取步骤、6.4 cutoff 策略和 6.5 UI 指示器。

### Database migration 链路

关键证据：

- 迁移集中在 `OpenChat/Core/Database/Migrations.swift`，当前从 `v1_initial` 到 `v13_add_last_extracted_sort_order`。
- `v8_endpoint_model_decoupling` 创建 `endpoint_model` 并迁移旧端点字段：`OpenChat/Core/Database/Migrations.swift:85`
- `Migrations.Historical` 维护迁移本地历史表名和默认值，`v8` migration 使用这些常量而非 runtime Record/enum 符号。

结论：迁移测试当前通过；Task 4 已将 migration 源码改为使用迁移本地历史常量，Task 5 已在 arch/data-model 写回该约束，并由 `MigrationTests.test_migrations_do_not_reference_runtime_record_or_enum_symbols` 守卫。

### Feature 导航与分层链路

关键证据：

- `SidebarView` 位于 `Features/Support`，但直接读取 `AppState` 和 `DependencyContainer`：`OpenChat/Features/Support/SidebarView.swift:4`
- `SidebarView` 直接创建 CharacterCard、WorldBook、Settings 三个 Feature 的 View/ViewModel：`OpenChat/Features/Support/SidebarView.swift:47`、`OpenChat/Features/Support/SidebarView.swift:57`、`OpenChat/Features/Support/SidebarView.swift:67`
- `WorldBookEditorView` 直接打开 CharacterCard 编辑/详情：`OpenChat/Features/WorldBook/Views/WorldBookEditorView.swift:159`、`OpenChat/Features/WorldBook/Views/WorldBookEditorView.swift:168`
- `Shared/String+Token` 反向依赖 Core 的 `TokenCounter`：`OpenChat/Shared/Extensions/String+Token.swift:5`

结论：源码结构名义上仍是 App -> Features -> Core -> Shared，但实际存在 Feature -> App、Feature -> Feature、Shared -> Core 的分层漂移。`Features/Support` 更像 App shell/Coordinator，后续若继续保留该模式，应在 arch 中明确其边界；若坚持原规则，应迁移到 App 层或通过 App 层协调。

## 风险分级

| 级别 | 风险 | 证据 |
|---|---|---|
| P2 | App/Core/Shared 分层漂移扩大传播面 | `AppConstants.swift:3`、`PromptAssembler.swift:38`、`MemoryManager.swift:167`、`String+Token.swift:5` |
| P2 | Feature 间直接引用和 Feature 直接读取 App 环境 | `SidebarView.swift:4`、`:47`、`:57`、`:67`、`WorldBookEditorView.swift:159` |
| Closed | Chat 当前输入重复注入风险已修复并有测试覆盖 | `promptHistoryMessages` 过滤；`ChatViewModelPromptAssemblyTests.swift` |
| Closed | Database migration runtime 符号引用风险已修复并有源码守卫 | `Migrations.Historical`；`MigrationTests.test_migrations_do_not_reference_runtime_record_or_enum_symbols` |
| Closed | arch 中测试数量、时间格式、Memory 目录说明已回写 | 详见 `triangle-consistency.md` |

## 建议修复顺序

1. 明确 `AppConstants` 的归属：如果 Core 会使用，应迁移到 Core/Shared 的配置类型或通过依赖注入传入，避免 Core -> App。
2. 决定 `Features/Support` 是否是 App shell。如果是，把 arch 规则写清；如果不是，把跨 Feature 导航上移到 App。
3. 对 Memory 的 `EmbeddingService`/`VectorStore` 增加更直接的测试或至少文档标注当前自动化覆盖边界。

## 2026-04-30 Memory Vector Reliability Incremental Audit

范围：`OpenChat/Core/Memory/`、`OpenChat/Features/Chat/ViewModels/ChatViewModel+Support.swift`、`OpenChat/App/DependencyContainer.swift`、`OpenChatTests/Core/MemoryTests/`、`OpenChatTests/Features/ChatTests/ChatViewModelPromptAssemblyTests.swift`、`scripts/generate_xcodeproj.rb`、`OpenChat/Resources/Models/`、Memory 相关 arch 文档。

审计模式：窄范围增量审计。OpenChat 当前没有 Magnum Agent 的 `arch/propagation-audit/` 脚本基线，因此本次使用 durable `harness/2026.04.30/memory-vector-reliability/evidence.txt` 记录静态 `rg` 证据、changed files 和 import surface；行为传播结论以源码链路为准。

### 静态传播面

- `EmbeddingService` 仍位于 `Core/Memory`，新增的 `XLMRobertaTokenizer` 只被 `EmbeddingService` 使用，没有扩大到 Feature 层。
- `MemoryDependencies` 只定义 Core 内部协议，并由 `EmbeddingService` / `VectorStore` conform；生产注入仍由 `DependencyContainer` 完成。
- `VectorStore` 的原子写入把 `memory_entry` 与 `memory_embedding` 放在同一 GRDB write transaction，传播面限定在 `Core/Memory` 与 `Core/Database`。
- `ChatViewModel+Support` 只改变 memory retrieval 错误处理，不改变 `PromptAssembler`、`ContextManager`、`APIClient` 的主链路接口。
- `scripts/generate_xcodeproj.rb` 只扩展资源识别，让 `.mlpackage` / `.mlmodelc` 与 `tokenizer.json` 进入 App Bundle；签名配置仍由脚本维持。

### 行为传播结论

- 写入链路从 `MemoryManager.extractMemories -> DatabaseManager.saveMemory -> VectorStore.insert(entryId:embedding:)` 收敛为 `MemoryManager.extractMemories -> EmbeddingProvider.embed -> MemoryVectorStore.insert(entries:)`，避免半索引记忆。
- `MemoryVectorStore.insert(entries:)` 是协议必填方法，不提供非原子默认实现；生产 `VectorStore` 在所有维度校验和 blob 转换完成后进入单个 GRDB write transaction。
- 检索链路从 Chat 层 `try?` 静默吞错，改为 `MemoryManager.retrieveMemories` 内部 fallback；2026-05-14 Phase B 后 fallback 不再是任意 recent，而是 keyword + recent high-value tier，Chat 层只记录 fallback 仍失败的 warning。
- Prompt 注入仍由 `PromptAssembler` 的 `memories: [MemoryEntryRecord]` 参数完成，段顺序没有改变。
- 本次修复没有新增 Feature 间直接依赖，也没有改变 App -> Features -> Core -> Shared 的既有名义方向；实际影响集中在 `Core/Memory` 与 Chat 发送链路中的记忆检索错误处理。

### 验证

- `EmbeddingServiceTests`
- `VectorStoreTests`
- `MemoryManagerRetrievalTests`
- `ChatViewModelPromptAssemblyTests`
- Focused command: `xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/VectorStoreTests' '-only-testing:OpenChatTests/DatabaseManagerMemoryTests' '-only-testing:OpenChatTests/EmbeddingServiceTests' '-only-testing:OpenChatTests/MemoryManagerRetrievalTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests'`，结果 26 tests passed，`** TEST SUCCEEDED **`。
- Focused memory/prompt command including `PromptAssemblerTests`：27 tests / 5 suites passed，`** TEST SUCCEEDED **`。
- Full suite：该轮审计时为 166 tests / 34 suites passed，`** TEST SUCCEEDED **`；最新 Prompt 四层顺序审计已更新为 197 tests / 41 suites。

## 2026-04-30 Checkpoint Compression Incremental Audit

范围：`OpenChat/Core/Database/Records/CompressionCheckpointRecord.swift`、`OpenChat/Core/Database/DatabaseManager+CompressionCheckpoints.swift`、`OpenChat/Core/Database/Migrations.swift`、`OpenChat/Core/ContextManager/CompressionPolicy.swift`、`CompressionSourceHasher.swift`、`PreparedHistory.swift`、`CompressionSummarizer.swift`、`CheckpointCompactor.swift`、`ContextManager.swift`、`OpenChat/Features/Chat/ViewModels/ChatViewModel.swift`、checkpoint 相关测试和 arch 文档。

审计模式：窄范围增量审计。OpenChat 当前没有 Magnum Agent 的 `arch/propagation-audit/` 脚本基线，本次沿用本文件的 AntiEntropy 审计方法：`git status` / `rg` / 文件统计确认传播面，源码链路确认行为传播，测试结果确认 `src-test`。

### 静态传播面

- 当前变更新增的 production 类型限定在 `Core/Database` 与 `Core/ContextManager`，外加 `ChatViewModel` 的历史编辑/删除失效调用。
- `DatabaseManager+CompressionCheckpoints` 只暴露 checkpoint CRUD、受影响 checkpoint 删除、按 sortOrder 范围读取 messages；未把数据库细节传播到 View 层。
- `CheckpointCompactor` 依赖 `DatabaseManager`、`APIClient`、`TokenCounter` 和 `CompressionSummarizer`，保持在 Core 内；没有新增 Feature -> Feature 或 Shared -> Core 依赖。
- `ChatViewModel` 只在 `editMessage` / `deleteMessage` 中调用 `deleteCompressionCheckpoints(conversationId:sourceEndAtOrAfter:)`，避免 stale summary；不直接读写 checkpoint record。
- `ruby scripts/generate_xcodeproj.rb` 已重新生成 project，使新增 Swift 文件进入 target；签名值仍由脚本维持。

本轮静态计数：

- App Swift files: 106
- Test Swift files: 31
- Context Swift files: 11
- Database Swift files: 19

### 行为传播链路

主链路：

`ChatViewModel+Support.generateResponse -> PromptAssembler.preview -> ContextManager.prepareContextHistory -> CheckpointCompactor -> DatabaseManager+CompressionCheckpoints / CompressionSummarizer(APIClient) -> PreparedHistory.messagesForLegacyPrompt -> PromptAssembler.assemble`

结论：

- `ContextManager.prepareHistory(...)` 保持旧返回类型，内部委托 `prepareContextHistory(...)`；旧 `PromptAssembler` 入口继续接收 `[MessageRecord]`。
- `.compression` 策略先复用有效 checkpoint；低于阈值不调用网络；高于阈值只压缩 checkpoint 后的旧历史段。
- checkpoint 保存以 source hash 校验为边界；root checkpoint 校验完整源消息 hash，链式 checkpoint 校验 parent hash + delta messages。
- summarizer 成功后才保存 `conversation_compression_checkpoint`；summarizer 或网络失败 fallback truncation，不写半成品。
- 原始 `message` 不删除、不改写；checkpoint 作为派生缓存，由编辑/删除历史触发失效。

### Database 传播

- `v11_create_compression_checkpoints` 只追加 `conversation_compression_checkpoint` 表和索引，不修改旧 migration。
- `conversationId` 删除级联到 checkpoint；`parentCheckpointId` 删除置空；`endpointId` 删除置空。
- `ConversationRecord.compressionCheckpoints` 建立 has-many 关系，但 Feature 层不直接使用该关系。

### 三边一致性

- `arch-src`：`arch/data-model.md`、`arch/modules/context-manager.md`、`.github/instructions/context-manager.instructions.md` 已写回 checkpoint schema、Codex 风格阈值语义、复用/失效/fallback 行为。
- `arch-test`：新增 migration/database/context/chat 测试覆盖 v11 表、checkpoint CRUD、source hash、policy、summarizer、compactor、复用和编辑/删除失效。
- `src-test`：focused suites 与 full suite 均通过；该轮基线为 197 tests / 41 suites。

### 验证

- Context focused command：`xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:OpenChatTests/CompressionPolicyTests -only-testing:OpenChatTests/CompressionSourceHasherTests -only-testing:OpenChatTests/PreparedHistoryTests -only-testing:OpenChatTests/CompressionSummarizerTests -only-testing:OpenChatTests/CheckpointCompactorTests -only-testing:OpenChatTests/CompressionCheckpointReuseTests`，结果 14 tests / 6 suites passed，`** TEST SUCCEEDED **`。
- Database focused command：`xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:OpenChatTests/MigrationTests -only-testing:OpenChatTests/CompressionCheckpointDatabaseTests`，结果 24 tests / 2 suites passed，`** TEST SUCCEEDED **`。
- Chat/prompt focused command：`xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests -only-testing:OpenChatTests/PromptAssemblerTests`，结果 16 tests / 2 suites passed，`** TEST SUCCEEDED **`。
- Full suite：`xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`，结果 197 tests / 41 suites passed，`** TEST SUCCEEDED **`。

## 2026-04-30 Compression Mode Threshold Incremental Audit

范围：`OpenChat/Core/ContextManager/CompressionMode.swift`、`CompressionPolicy.swift`、`CheckpointCompactor.swift`、`ContextManager.swift`、`ConversationRecord.swift`、`Migrations.swift`、`ChatViewModel.swift`、`ChatSettingsSheet.swift`、conversation preview/test helpers、压缩策略与迁移测试、context-manager / data-model / settings 文档。

审计模式：窄范围增量审计。该轮不新增大型目录，不改变 Feature 间依赖方向；传播面集中在会话设置、conversation schema、ContextManager policy 和 checkpoint 复用判断。

### 静态传播面

- `CompressionMode` 是 Core/ContextManager 内的会话级枚举，当前值为 `standard` 与 `highIntelligence`。
- `ConversationRecord` 新增 `compressionMode` 字段和 `compressionModeValue` 解析辅助；`v12_add_compression_mode_to_conversation` 只追加列并默认 `standard`。
- `ChatViewModel` 读取并保存 `selectedCompressionMode`；`ChatSettingsSheet` 仅在 `.compression` strategy 下显示 picker。
- `CompressionPolicy` 不再读取模型名特判阈值；阈值由 `compressionMode` 决定。
- `CheckpointCompactor.latestValidCheckpoint` 复用 checkpoint 时同时校验 source hash 与生成时阈值，避免模式切换后复用旧摘要。

### 行为传播链路

`ChatSettingsSheet -> ChatViewModel.selectedCompressionMode -> ConversationRecord.compressionMode -> ContextManager.prepareContextHistory -> CompressionPolicy(endpoint:compressionMode:) -> CheckpointCompactor.latestValidCheckpoint / saveCompressionCheckpoint`

结论：

- 标准模式下，自动压缩阈值为 `endpoint.maxContextTokens × 0.40`。
- 高智能模式下，effective compact window 为 `endpoint.maxContextTokens × 0.25`，自动压缩阈值为该 effective window 的 90%。
- 旧会话通过 v12 默认值继续走标准模式，不改变既有 40% 行为。
- 新模式没有新增 Feature-to-Feature 依赖；Chat 仍只通过 Core service 和 conversation record 交互。

### 三边一致性

- `arch-src`：`arch/modules/context-manager.md`、`arch/data-model.md`、`arch/modules/settings/context-strategy.md`、`.github/instructions/context-manager.instructions.md` 已写回 compression mode、v12 schema、阈值公式和 checkpoint 阈值匹配复用规则。
- `arch-test`：`CompressionPolicyTests`、`MigrationTests`、`CompressionCheckpointReuseTests`、`ChatViewModelPromptAssemblyTests` 覆盖阈值公式、v12 默认值、模式切换不复用旧 checkpoint、设置持久化。
- `src-test`：focused compression mode suite 39 tests / 4 suites passed；该轮 full suite 197 tests / 41 suites passed，`** TEST SUCCEEDED **`。

## 2026-04-30 Prompt Four-Layer Assembly Incremental Audit

范围：`OpenChat/Core/PromptEngine/PromptAssemblyModels.swift`、`PromptAssembler.swift`、`PromptSegment.swift`、`OpenChatTests/Core/PromptEngineTests/PromptAssemblerTests.swift`、`OpenChatTests/Features/ChatTests/ChatViewModelPromptAssemblyTests.swift`、Prompt/AntiEntropy/roadmap 相关文档。

审计模式：窄范围增量审计。OpenChat 当前没有 Magnum Agent 的静态 import 图脚本，本轮沿用 AntiEntropy 方法：`git diff --name-only` / `rg '^import '` / Swift 文件计数确认传播面，源码链路确认行为传播，focused/full tests 确认 `src-test`。

### 静态传播面

- App Swift files：106。
- Test Swift files：31。
- Production Swift 改动限定在 `Core/PromptEngine` 3 个文件。
- Test Swift 改动限定在 `PromptAssemblerTests` 与 `ChatViewModelPromptAssemblyTests`。
- 未新增 Swift import 依赖；变更后的 PromptEngine production 文件仍只显式 `import Foundation`。
- 未修改 `ChatViewModel+Support.swift` 生产调用链、数据库 migration、签名配置或 Xcode project。
- Feature 层新增覆盖只在测试文件中，不扩大生产 Feature 依赖面。

### 行为传播链路

主链路仍为：

`ChatViewModel+Support.generateResponse -> PromptAssembler.preview -> ContextManager.prepareHistory -> PromptAssembler.assemble -> APIClient.streamMessage`

结论：

- `PromptAssemblyPreview` 从单一 `messagesBeforeHistory` 改为 `stableIdentityMessages`、`currentTurnContextMessages`、`currentTurnMessage`。
- `PromptAssembler.preview(...)` 生成 Stable Identity、Current-Turn Context、Current Turn，并用这些不可裁剪段计算 `fixedTokens`。
- `ContextManager.prepareHistory(...)` 继续只接收过滤后的 history 和 `fixedTokens`，负责 Stable Conversation State 的剔除/压缩结果。
- `PromptAssembler.assemble(...)` 输出 `stableIdentityMessages + processedHistory + currentTurnContextMessages + currentTurnMessage`。
- 世界书 position 字段保留为旧数据兼容字段；当前轮命中条目统一进入 `[World Book Entries]` block。
- 示例对话统一进入 `[Example Dialogs]` block；记忆统一进入 `[Memories]` block；时间上下文进入最后一条 Current Turn user message。

### 三边一致性

- `arch-src`：`arch/modules/prompt-assembly.md`、`.github/instructions/prompt-engine.instructions.md`、`arch/index.md`、`arch/modules/chat.md`、`arch/modules/world-book.md`、`arch/modules/memory/index.md`、`arch/data-model.md` 已同步四层顺序、labeled blocks、world book position 兼容和 time-in-current-turn。
- `arch-test`：`PromptAssemblerTests` 覆盖四层顺序、preview 四层结构、world book position 兼容、labeled blocks、time-in-current-turn；`ChatViewModelPromptAssemblyTests` 覆盖真实 API request 的 history -> example -> memory -> current turn 顺序和当前输入去重。
- `src-test`：focused prompt suite 13 tests passed；focused chat prompt suite 9 tests passed；combined prompt/chat suite 22 tests passed；full suite 197 tests / 41 suites passed。

### Durable Evidence

- `harness/2026.04.30/prompt-four-layer-assembly/index.md`
- `harness/2026.04.30/prompt-four-layer-assembly/evidence.txt`

## 2026-05-13 Memory Extraction Cutoff & Observability Incremental Audit

范围：`OpenChat/Core/Memory/MemoryManager.swift`、`OpenChat/Core/Database/Migrations.swift`、`OpenChat/Core/Database/Records/ConversationRecord.swift`、`OpenChat/Features/Chat/ViewModels/ChatViewModel.swift`、`OpenChat/Features/Chat/ViewModels/ChatViewModel+Support.swift`、`OpenChat/Features/Chat/Views/ChatView.swift`、`OpenChat/Features/Chat/Views/MemoryExtractionIndicator.swift`（新增）、`OpenChat/Features/Chat/Models/MemoryExtractionPhase.swift`（新增）、`OpenChatTests/Core/MemoryTests/MemoryExtractionCutoffTests.swift`（新增）、`OpenChatTests/Features/ChatTests/MemoryExtractionPhaseTests.swift`（新增）、Memory 相关 arch 文档。

审计模式：窄范围增量审计，解决 `arch/AntiEntropy/problem.md` 中 P1 cutoff 边界问题和 P1 自动提取触发可靠性问题。

### 静态传播面

- `ConversationRecord` 新增 `lastExtractedSortOrder: Int?` 字段，`v13_add_last_extracted_sort_order` 追加列默认 NULL。
- `MemoryManager.extractMemories` 改用 `conversation.lastExtractedSortOrder` 替代 `latestMemoryDate(conversationId:)`；提取成功后更新 `conversation.lastExtractedSortOrder`。
- `ChatViewModel` 新增 `extractionPhase: MemoryExtractionPhase` 属性。
- `ChatViewModel+Support.generateResponse` 在检索记忆前同步等待提取（当 DB 中 `sortOrder > lastExtractedSortOrder` 的消息数达到 `minimumPendingMessagesForExtraction` 时）。
- `MemoryExtractionIndicator`（新增）替代 `MemoryMarkerView`（已删除），根据 `extractionPhase` 渲染内联 UI。
- `MessageDisplayItem.memoryMarker()` 工厂方法已移除。

### 行为传播链路

主链路变更：

`ChatViewModel+Support.generateResponse` -> 持久化 user message -> **前置同步提取** (`MemoryManager.extractMemories`) -> 更新 `conversation.lastExtractedSortOrder` -> `MemoryManager.retrieveMemories` -> `PromptAssembler.preview/assemble` -> `APIClient.streamMessage`

结论：

- 提取时机从响应完成后异步 fire-and-forget 改为下次 generateResponse 中前置同步等待。
- cutoff 从 `memory_entry.createdAt` 改为 `conversation.lastExtractedSortOrder`（message sortOrder），消除了并发写入导致消息被跳过的 P1 风险。
- 提取结果立即可用于当前轮语义检索。
- `ChatView.onDisappear` 保留 fire-and-forget 提取（无 UI 指示）。
- 没有新增 Feature-to-Feature 依赖；传播面限定在 Chat Feature + Core/Memory + Core/Database。

### 三边一致性

- `arch-src`：`arch/modules/memory/index.md` 已更新 6.1 触发时机（前置同步提取）、6.2 提取步骤（sortOrder cutoff + 更新 lastExtractedSortOrder）、6.4 cutoff 策略（sortOrder 替代 createdAt）、6.5 UI 指示器（MemoryExtractionPhase + MemoryExtractionIndicator）。`arch/data-model.md` 已新增 `conversation.lastExtractedSortOrder` 列。`arch/modules/chat.md` 已更新 4.6 记忆提取触发说明。
- `arch-test`：`MemoryExtractionCutoffTests` 覆盖 sortOrder cutoff、首次提取全量处理、消息不足跳过、并发消息不被跳过。`MemoryExtractionPhaseTests` 覆盖 isActive 和 Equatable 语义。`MigrationTests` 覆盖 v13 列存在性和 NULL 默认值。`ChatViewModelPromptAssemblyTests` 覆盖 ViewModel 重建后仍按 DB sortOrder 边界触发提取。
- `src-test`：focused suite 49 tests / 4 suites passed；full suite 218 tests / 45 suites passed，`** TEST SUCCEEDED **`。

### 验证

- Focused command: `xcodebuild test ... -only-testing:OpenChatTests/MemoryExtractionCutoffTests -only-testing:OpenChatTests/MemoryExtractionPhaseTests -only-testing:OpenChatTests/MigrationTests -only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests`，结果 49 tests / 4 suites passed。
- Full suite: 218 tests / 45 suites passed，`** TEST SUCCEEDED **`。

## 2026-05-14 Memory Recall Ordering Phase A Incremental Audit

范围：`OpenChat/Core/PromptEngine/PromptAssembler.swift`、`OpenChatTests/Core/PromptEngineTests/PromptAssemblerTests.swift`、`arch/modules/memory/*`、`arch/modules/prompt-assembly.md`、`arch/AntiEntropy/*`、`harness/2026.05.14/memory-hindsight-lite-repair/*`。

审计模式：窄范围增量审计，解决 `arch/AntiEntropy/problem.md` 中 P1 “语义检索顺序在 Prompt 注入前被 importance 重排”问题。OpenChat 当前没有可生成 Swift import graph 的传播审计脚本，本轮使用源码链路、`rg` 静态引用和 focused tests 作为证据。

### 静态传播面

- Production Swift 改动限定在 `OpenChat/Core/PromptEngine/PromptAssembler.swift`。
- Test Swift 改动限定在 `OpenChatTests/Core/PromptEngineTests/PromptAssemblerTests.swift`。
- 未新增 Swift import，未修改 `MemoryManager.retrieveMemories(...) -> [MemoryEntryRecord]` 兼容接口。
- 未修改 Chat ViewModel、API request、Database migration、签名配置或 Xcode project。
- 文档写回限定在 Memory / Prompt / AntiEntropy / Background migration plan 的排序事实同步。

### 行为传播链路

主链路保持：

`ChatViewModel+Support.generateResponse -> MemoryManager.retrieveMemories -> PromptAssembler.preview -> ContextManager.prepareHistory -> PromptAssembler.assemble -> APIClient.streamMessage`

变更点：

- `MemoryManager.retrieveMemories(...)` 仍负责按 KNN ids 恢复 ordered entries，并追加去重后的 recent summaries。
- `PromptAssembler.trim(memories:within:)` 从 `memories.sorted { importance DESC }` 改为对输入 `memories` 原序迭代。
- `[Memories]` block 仍位于 Current-Turn Context，位于 world book block 之后、Current Turn user message 之前。
- token budget 与“至少保留第一条”行为不变。

结论：Phase A 把 prompt memory 的排序权收敛回 recall 侧，关闭 P1 重排问题；未扩大 Core/Memory、Chat、Networking 或 Database 的行为传播面。`importance` 仍可作为未来 recall fusion、fallback tier 或 UI 元数据，但不再由 `PromptAssembler` 覆盖 retrieval order。

### 三边一致性

- `arch-src`：`arch/modules/memory/retrieval-prompt.md`、`arch/modules/memory/index.md`、`arch/modules/memory/hindsight-lite.md`、`arch/modules/prompt-assembly.md` 已同步 Phase A 后的 order-preserving trim 事实。
- `arch-test`：`PromptAssemblerTests.test_memory_trim_preserves_retrieval_order_when_budget_drops_high_importance_memory` 覆盖高 importance 低 relevance 第三条在预算不足时不会挤掉前两条 retrieval-order memory。
- `src-test`：baseline focused suite 34 tests / 4 suites passed；Phase A `PromptAssemblerTests` 14 tests / 1 suite passed；post-change focused suite 35 tests / 4 suites passed；full suite 219 tests / 45 suites passed。2026-05-14 20:14-20:17 +0800 已重跑 Phase A focused、post-change focused 和 full suite，结果仍为 14 / 35 / 219 tests 全部通过。

## 2026-05-14 Memory Hindsight-lite Phase B Incremental Audit

范围：`OpenChat/Core/Memory/MemoryRecallModels.swift`（新增）、`OpenChat/Core/Memory/MemoryManager.swift`、`OpenChat/Core/Database/DatabaseManager+Memory.swift`、`OpenChat.xcodeproj/project.pbxproj`、`OpenChatTests/Core/MemoryTests/MemoryManagerRetrievalTests.swift`、`OpenChatTests/Core/DatabaseTests/DatabaseManagerMemoryTests.swift`、`OpenChatTests/Features/ChatTests/ChatViewModelPromptAssemblyTests.swift`、Memory/AntiEntropy/harness 文档。

审计模式：窄范围增量传播审计。OpenChat 当前仍没有 Swift AST import graph 脚本，本轮沿用静态 `rg` 引用面 + 行为链路 + focused tests。

### 静态传播面

- 新增 production Swift 文件 1 个：`Core/Memory/MemoryRecallModels.swift`，只定义 `Sendable` DTO / enum，没有新增外部框架依赖。
- `MemoryManager.retrieveMemories(...) -> [MemoryEntryRecord]` 兼容接口保持不变；Chat 发送链路无需改签名。
- `DatabaseManager+Memory` 新增 `fetchRecentHighValueMemories(...)`，不新增 migration，不修改 `memory_entry` schema。
- `PromptAssembler`、`ContextManager`、`APIClient` 未修改；`PromptAssembler` 仍只消费 `[MemoryEntryRecord]`，不理解 semantic distance 或 fallback trace。
- `OpenChat.xcodeproj/project.pbxproj` 只新增 `MemoryRecallModels.swift` 的 file reference 和 source build phase 引用；签名配置保持 `PRODUCT_BUNDLE_IDENTIFIER=fukujusou.openchat.com`、`DEVELOPMENT_TEAM=GZAC7644XS`、`CODE_SIGN_STYLE=Automatic`。

### 行为传播结论

链路：

```text
ChatViewModel+Support.generateResponse
  -> MemoryManager.retrieveMemories
  -> MemoryManager.recallMemories
  -> semantic candidates + keyword candidates + recent high-value candidates
  -> MemoryRecallResult(entries, trace)
  -> PromptAssembler.preview/assemble
```

- semantic 正常命中时，semantic distance order 是主顺序；keyword / recent high-value 只补充未出现条目。
- semantic unavailable 时，trace fallback 为 `semanticUnavailable`，返回 keyword + recent high-value。
- semantic no hit 时，trace fallback 为 `noSemanticHit`；有 keyword 时不额外塞 recent high-value，没有 keyword 时才返回少量 high-value。
- empty index 或所有候选为空时返回空 entries，trace fallback 为 `emptyIndex`。
- 普通 `fetchRecentMemories(createdAt DESC)` 仍存在，但不再作为 prompt fallback 路径。

结论：Phase B 关闭 P2 “fallback 不可解释”和“recent fallback 只按时间取最近 N 条”。传播面限定在 `Core/Memory` / `Core/Database` 和测试；Chat/Prompt 主链路只看到原有 `[MemoryEntryRecord]` 输出。

### 验证

- `MemoryManagerRetrievalTests` 覆盖 semantic order + keyword trace、semantic failure、no semantic hit、empty index、兼容 retrieve API。
- `DatabaseManagerMemoryTests` 覆盖 recent high-value 查询筛掉普通 recent 噪声并按 type priority 排序。
- `ChatViewModelPromptAssemblyTests` 覆盖 semantic failure 时 high-value memory 进入 request、普通 recent 噪声不进入 request。
- Focused command：`xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MemoryManagerRetrievalTests' '-only-testing:OpenChatTests/DatabaseManagerMemoryTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests'`，结果 28 tests / 3 suites passed，`** TEST SUCCEEDED **`。
- Broader focused command：`xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MemoryManagerRetrievalTests' '-only-testing:OpenChatTests/DatabaseManagerMemoryTests' '-only-testing:OpenChatTests/VectorStoreTests' '-only-testing:OpenChatTests/PromptAssemblerTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests'`，结果 49 tests / 5 suites passed，`** TEST SUCCEEDED **`。
- 2026-05-14 22:49-22:52 +0800 按用户要求重新执行 B 阶段验收与后置传播评估：同一 `iPhone 17 Pro` destination 下 focused 28 tests / 3 suites、broader focused 49 tests / 5 suites、full suite 225 tests / 45 suites 均通过；`MemoryManager.retrieveMemories(...)`、`PromptAssembler`、`ContextManager`、`APIClient` 的接口传播边界未扩大。

## 2026-05-15 Memory Hindsight-lite Phase C Incremental Audit

范围：`OpenChat/Core/Database/Migrations.swift`、`OpenChat/Core/Database/Records/MemoryEntryProvenanceRecord.swift`（新增）、`OpenChat/Core/Database/DatabaseManager+Memory.swift`、`OpenChat/Core/Memory/VectorStore.swift`、`OpenChat/Core/Memory/MemoryDependencies.swift`、`OpenChat/Core/Memory/MemoryManager.swift`、`OpenChatTests/Core/DatabaseTests/MigrationTests.swift`、`OpenChatTests/Core/MemoryExtractionParsingTests.swift`、`OpenChatTests/Core/MemoryTests/MemoryManagerRetrievalTests.swift`、`OpenChatTests/Core/DatabaseTests/DatabaseManagerMemoryTests.swift`、Memory/AntiEntropy/harness 文档。

审计模式：窄范围增量传播审计，解决 `arch/AntiEntropy/problem.md` 中 P2 “提取 prompt 缺少角色卡、已有记忆、source 边界和去重约束”。

### 静态传播面

- 新增 production Swift 文件 1 个：`Core/Database/Records/MemoryEntryProvenanceRecord.swift`，定义 companion table GRDB Record，无新增外部框架依赖。
- `Migrations.swift` 追加 `v14_create_memory_entry_provenance`，只创建新表，不修改旧 migration。
- `DatabaseManager+Memory.swift` 新增 provenance CRUD（save/fetch/delete），不修改 `memory_entry` schema。
- `VectorStore.swift` 新增 `insert(entries:provenances:)`，在同一 GRDB transaction 中写入 entry + embedding + provenance。
- `MemoryDependencies.swift` 在 `MemoryVectorStore` 协议中新增 `insert(entries:provenances:)` 要求，并提供默认空实现（向后兼容测试 mock）。
- `MemoryManager.swift` 改动集中在 extraction pipeline：
  - `callExtractionAPI(...)` 输入从纯文本改为结构化 JSON（character summary + existing memory hints + message id/sortOrder）。
  - `ExtractedMemory` 扩展 v2 字段（sourceStartSortOrder、sourceEndSortOrder、sourceMessageIds、confidence、tags、dedupeKey、action）。
  - 新增同批 dedupe、source range validation、source message id filtering、skip/reinforce suppression。
  - `extractMemories(...)` 使用 `VectorStore.insert(entries:provenances:)` 原子写入。
- `PromptAssembler`、`ContextManager`、`APIClient` 未修改；Chat 发送链路仍只消费 `[MemoryEntryRecord]`。
- `OpenChat.xcodeproj/project.pbxproj` 已通过 `ruby scripts/generate_xcodeproj.rb` 重新生成，新增 `MemoryEntryProvenanceRecord.swift` 引用；签名配置保持原有值。

### 行为传播链路

链路：

```text
ChatViewModel+Support.generateResponse
  -> MemoryManager.extractMemories
    -> callExtractionAPI(character + existingHints + messages)
    -> validateAndFilter(source range, message ids, skip/reinforce)
    -> dedupeWithinBatch(dedupeKey / normalized content)
    -> EmbeddingProvider.embed
    -> VectorStore.insert(entries:provenances:)
      -> GRDB transaction: memory_entry + memory_embedding + memory_entry_provenance
    -> update conversation.lastExtractedSortOrder
```

- 结构化输入帮助 LLM 判断重复、强化或跳过；fallback 到纯文本时仍兼容旧路径。
- `action == skip` 的条目在 validation 阶段丢弃，不进入 DB。
- `action == reinforce` 第一版不覆盖旧记忆，也不新增重复记忆，直接跳过插入（后续 reflect 计划可扩展）。
- 同批 dedupe 保留 importance 更高或 content 更短的条目；不自动删除旧 memory。
- 越界 source range 的条目丢弃；无效 sourceMessageIds 从 provenance 中过滤。
- confidence 在 provenance 中 clamp 到 0...1；tags 去空去重并限制 10 条。
- 原子写入保证 embedding/vector 失败时 entry 和 provenance 一起回滚，不留半成品。

### 三边一致性

- `arch-src`：`arch/modules/memory/data-model.md` 已新增 `memory_entry_provenance` schema；`arch/modules/memory/extraction.md` 已更新为 retain v2 流程；`arch/modules/memory/hindsight-lite.md` 已标记 Phase C implemented；`arch/AntiEntropy/problem.md` 已关闭 P2 “提取 prompt 缺 source/dedupe”。
- `arch-test`：`MigrationTests` 覆盖 v14 表存在、列集合、外键 cascade；`MemoryExtractionParsingTests` 覆盖 v2 字段解析、provenance CRUD、旧 memory 无 provenance 兼容；`MemoryManagerRetrievalTests` 覆盖同批 dedupe、越界 source range 丢弃、无效 sourceMessageIds 过滤、skip/reinforce 不插入、向量失败不留下 entry/provenance 半成品。
- `src-test`：Phase C focused suite 107 tests / 7 suites passed；full suite 244 tests / 45 suites passed，`** TEST SUCCEEDED **`。

### 验证

- Focused command：`xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MemoryManagerRetrievalTests' '-only-testing:OpenChatTests/VectorStoreTests' '-only-testing:OpenChatTests/PromptAssemblerTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests' '-only-testing:OpenChatTests/MemoryExtractionParsingTests' '-only-testing:OpenChatTests/DatabaseManagerMemoryTests' '-only-testing:OpenChatTests/MigrationTests'`，结果 107 tests / 7 suites passed，`** TEST SUCCEEDED **`。
- Full suite：`xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`，结果 244 tests / 45 suites passed，`** TEST SUCCEEDED **`。

### Durable Evidence

- `harness/2026.05.14/memory-hindsight-lite-repair/index.md`
- `harness/2026.05.14/memory-hindsight-lite-repair/evidence.txt`

## 2026-05-16 Memory Hindsight-lite Phase D Incremental Audit

范围：`OpenChat/Core/Memory/MemoryReflectModels.swift`（新增）、`OpenChatTests/Core/MemoryTests/MemoryReflectModelsTests.swift`（新增）、`OpenChatTests/Core/NetworkingTests/ResponsesAPITests.swift`、`OpenChatTests/Features/ChatTests/ChatViewModelPromptAssemblyTests.swift`、`arch/modules/api-client.md`、`arch/modules/memory/*`、`arch/AntiEntropy/problem.md`、Memory Hindsight-lite 计划包和 harness evidence。

审计模式：窄范围增量传播审计，解决 `arch/AntiEntropy/problem.md` 中 P2 Responses system folding request-shape 风险，并为 reflect 建立 Memory 层最小 contract。

### 静态传播面

- 新增 production Swift 文件 1 个：`Core/Memory/MemoryReflectModels.swift`，只定义 `Sendable` DTO / enum / typed LocalizedError，不引入 DB、Networking、Prompt 或 UI 依赖。
- 新增测试文件 1 个：`MemoryReflectModelsTests.swift`，覆盖 source/basedOn ids 非空、observation content 非空、confidence clamp 和 relation 最小集合。
- `ResponsesAPITests.swift` 新增 request-level test，确认 `[Memories]` folding 到 `instructions`，不进入 user input。
- `ChatViewModelPromptAssemblyTests.swift` 新增 Responses 模式端到端 request 捕获，确认 Chat 发送链路下 current input 只出现一次，`[Memories]` 在 `instructions` 中。
- `ResponsesAPIRequest.swift` 未修改；测试确认当前 shape 符合 Phase D 目标。
- 未新增 migration；`memory_entry_link` 仍未持久化，只有 relation enum contract。
- 未新增 `Core/Background`、Background worker 或 PromptAssembler-to-Background 依赖。

### 行为传播链路

Responses request shape：

```text
PromptAssembler.assemble
  -> stableIdentityMessages + processedHistory + currentTurnContextMessages + currentTurnMessage
  -> APIClient.streamMessage(... endpoint.apiMode == .responses)
  -> ResponsesAPIRequest.init
  -> system messages joined into instructions
  -> non-system messages kept in input
```

Reflect contract：

```text
MemoryReflectRequest(characterCardId, task, sourceMemoryIds)
  -> source ids must be non-empty
MemoryReflectObservation(content, type, basedOnMemoryIds, confidence, action)
  -> basedOn ids must be non-empty
  -> confidence clamped to 0...1
```

### 三边一致性

- `arch-src`：`arch/modules/api-client.md` 记录 Responses folding；`arch/modules/memory/hindsight-lite.md` 记录 Phase D DTO contract 和未实现边界；`arch/modules/memory/index.md` / `ui-management.md` 记录 reflect contract 不等于 UI/executor。
- `arch-test`：`MemoryReflectModelsTests`、`ResponsesAPIRequestTests`、`ChatViewModelPromptAssemblyTests` 覆盖本阶段 contract / request shape；文档明确 Swift Testing 选择器需要 suite 名称。
- `src-test`：Phase D focused verification 已通过（reflect contract 5 tests / 1 suite、Responses suites 21 tests / 5 suites、Chat + reflect 17 tests / 2 suites）；Lead closeout full suite 251 tests / 46 suites passed。

### 验证

- Reflect contract command：`xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'id=4435A025-9E0B-40AF-9BE0-DE0648F77AED' '-only-testing:OpenChatTests/MemoryReflectModelsTests'`，结果 5 tests / 1 suite passed，`** TEST SUCCEEDED **`。
- Responses suites command：`xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'id=6F61E759-8E3C-4951-B929-0A63AA47BFBB' '-only-testing:OpenChatTests/ResponsesAPIRequestTests' '-only-testing:OpenChatTests/ResponsesAPIResponseTests' '-only-testing:OpenChatTests/SSEParserTypedEventsTests' '-only-testing:OpenChatTests/APIClientResponsesModeTests' '-only-testing:OpenChatTests/ModelParametersAPIModeTests'`，结果 21 tests / 5 suites passed，`** TEST SUCCEEDED **`。
- Chat + reflect focused command：`xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'id=F8D0D88B-71FD-471F-855A-B2B5D8267117' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests' '-only-testing:OpenChatTests/MemoryReflectModelsTests'`，结果 17 tests / 2 suites passed，`** TEST SUCCEEDED **`。
- 两次中间重试被 simulator runner launch preflight `Busy` 拒绝，未进入测试断言；未作为代码失败处理。
- Full-suite closeout：第一次成功启动的 full suite 暴露 `MemoryManagerRetrievalTests` 两个 retain v2 测试在并发运行时触碰真实 Keychain 的 `-25299` duplicate item；已将该测试文件内 `MemoryManager` 构造统一注入 `InMemoryAPIKeyStore()`。随后 `MemoryManagerRetrievalTests` 15 tests / 1 suite passed，最终 full suite 251 tests / 46 suites passed，`** TEST SUCCEEDED **`。

### 结论

Phase D 关闭当前 Memory 包内的 Responses `[Memories]` request-shape 风险，并为 low-frequency reflect 建立最小 DTO contract。剩余 reflect executor、`memory_entry_link` 持久化、Background block request-shape 和 BackgroundWorker 统一调度均属于后续独立计划，不应写成当前实现。

## 2026-05-16 WorldBook Vectorization Phase A Incremental Audit

范围：`OpenChat/Core/Database/Migrations.swift`、`OpenChat/Core/Database/Records/WorldBookEntryEmbeddingMetaRecord.swift`、`OpenChat/Core/Database/DatabaseManager+Content.swift`、`OpenChat/Core/WorldBook/WorldBookError.swift`、`WorldBookRecallModels.swift`、`WorldBookVectorStore.swift`、`OpenChatTests/Core/DatabaseTests/MigrationTests.swift`、`OpenChatTests/Core/WorldBookTests/WorldBookVectorStoreTests.swift`、世界书向量化相关 arch/plan 文档。

审计模式：窄范围增量传播审计，执行 `docs/superpowers/plans/2026-05-16-world-book-vectorization/03_phase_a_schema_vector_store.md`。本阶段目标是 schema + vector store，不改变 Chat prompt 链路。

### 静态传播面

- 新增 production Swift 文件 4 个：
  - `Core/Database/Records/WorldBookEntryEmbeddingMetaRecord.swift`
  - `Core/WorldBook/WorldBookError.swift`
  - `Core/WorldBook/WorldBookRecallModels.swift`
  - `Core/WorldBook/WorldBookVectorStore.swift`
- `Migrations.swift` 只追加 v15/v16，不修改既有 migration；384 维度使用 migration-local historical constant，不引用 `EmbeddingService.embeddingDimension`。
- `DatabaseManager+Content.swift` 只新增 cleanup helper；`saveWorldBookEntry`、`deleteWorldBookEntry`、`deleteWorldBook`、`eraseAllData` 主链路未接入向量维护，避免 Phase A 越界到 Phase D。
- `PromptAssembler`、`ChatViewModel`、`WorldBookEditorViewModel`、`APIClient` 未修改；Chat prompt 输出仍是 keyword-only `[World Book Entries]`。
- `OpenChat.xcodeproj/project.pbxproj` 只新增上述 Swift 文件和 `WorldBookVectorStoreTests.swift` 的 file reference/source build phase；签名配置未改。

### 行为传播链路

Phase A 新增链路：

```text
WorldBookVectorStore.upsert
  -> validate 384 dimension
  -> DatabaseManager.write
  -> DELETE old world_book_entry_embedding row
  -> INSERT new world_book_entry_embedding row

WorldBookVectorStore.search(query, worldBookId, limit)
  -> validate 384 dimension
  -> SELECT world_book_entry ids WHERE worldBookId = ? AND isEnabled = 1
  -> sqlite-vec MATCH / k limited KNN
```

清理 helper 链路：

```text
DatabaseManager.deleteWorldBookEntryEmbedding(entryId, db)
DatabaseManager.deleteWorldBookEntryEmbeddings(worldBookId, db)
  -> DELETE world_book_entry_embedding
  -> DELETE world_book_entry_embedding_meta
```

结论：传播面限定在 Core/Database 与新增 Core/WorldBook。当前没有把 semantic recall 传播到 Prompt/Chat，也没有把 embedding maintenance 传播到 Feature CRUD/import/delete；这些仍是 Phase B-D。

### 三边一致性

- `arch-src`：`arch/data-model.md`、`arch/source-tree.md`、`arch/modules/world-book.md`、`arch/modules/background/world-book-vectorization.md`、`arch/modules/background/sources.md`、`arch/modules/prompt-assembly.md` 已同步当前实现和未实现边界。
- `arch-test`：`MigrationTests` 覆盖 v15/v16 schema、索引、cascade、migration forbidden references；`WorldBookVectorStoreTests` 覆盖 upsert、worldBook-scoped KNN、disabled entry 过滤、delete、invalid dimension。
- `src-test`：Phase A focused command 39 tests / 2 suites passed；broader focused command 72 tests / 5 suites passed；full suite 261 tests / 47 suites passed，`** TEST SUCCEEDED **`。

### 验证

- Baseline focused command：`xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MigrationTests' '-only-testing:OpenChatTests/VectorStoreTests' '-only-testing:OpenChatTests/PromptAssemblerTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests'`，结果 62 tests / 4 suites passed。
- Phase A focused command：`xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MigrationTests' '-only-testing:OpenChatTests/WorldBookVectorStoreTests'`，结果 39 tests / 2 suites passed。
- Phase A broader focused command：`xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MigrationTests' '-only-testing:OpenChatTests/VectorStoreTests' '-only-testing:OpenChatTests/WorldBookVectorStoreTests' '-only-testing:OpenChatTests/PromptAssemblerTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests'`，结果 72 tests / 5 suites passed。
- Full suite command：`xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,id=2277CB75-AF36-4ABF-84EE-7444C1DD6759'`，实际设备 iOS 26.5 `iPhone 17`，结果 261 tests / 47 suites passed，`** TEST SUCCEEDED **`。
- 同日一次 `iPhone 17 Pro` full-suite 尝试在测试体执行前被 Simulator 拒绝启动，错误为 `Busy ("Application failed preflight checks")`；换用上述 `iPhone 17` 设备后通过。

## 2026-05-16 WorldBook Vectorization Phase B Incremental Audit

范围：`OpenChat/App/DependencyContainer.swift`、`OpenChat/Core/Memory/EmbeddingService.swift`、`OpenChat/Core/WorldBook/WorldBookEmbeddingTextBuilder.swift`、`WorldBookEntryHasher.swift`、`WorldBookEmbeddingIndexer.swift`、`WorldBookVectorStore.swift`、`OpenChatTests/Core/WorldBookTests/WorldBookEmbedding*Tests.swift`、`WorldBookEntryHasherTests.swift`、世界书向量化相关 arch/plan 文档。

审计模式：窄范围增量传播审计，执行 `docs/superpowers/plans/2026-05-16-world-book-vectorization/04_phase_b_indexer_backfill.md`。本阶段目标是 indexer + existing world-book backfill，不改变 Chat prompt 链路，不接入 Feature CRUD/import/delete。

### 静态传播面

- 新增 production Swift 文件 3 个：
  - `Core/WorldBook/WorldBookEmbeddingTextBuilder.swift`
  - `Core/WorldBook/WorldBookEntryHasher.swift`
  - `Core/WorldBook/WorldBookEmbeddingIndexer.swift`
- `EmbeddingService.swift` 只新增 `embeddingModelId` 常量，供 hash/meta 审计使用；未改变 CoreML 推理、tokenizer、dimension 或 prefix 行为。
- `WorldBookVectorStore.swift` 新增 `upsert(entryId:embedding:meta:)`，把 vector row 与 indexed meta 放进同一 DB write。
- `DependencyContainer.swift` 共享一个 `EmbeddingService` 给 `MemoryManager` 和 `WorldBookEmbeddingIndexer`，新增 `worldBookVectorStore` / `worldBookEmbeddingIndexer` Core service 持有；没有把 indexer 注入 View 或 Chat。
- `PromptAssembler`、`ChatViewModel`、`WorldBookEditorViewModel` 未修改；semantic recall 和 CRUD/import/delete maintenance 仍未传播到 Feature/UI。

### 行为传播链路

Phase B 新增链路：

```text
WorldBookEmbeddingIndexer.index(entry)
  -> WorldBookEmbeddingTextBuilder.text(for:)
  -> WorldBookEntryHasher.hash(text, modelId, dimension)
  -> read existing meta
  -> skip if indexed + hash/model/dimension fresh
  -> EmbeddingProvider.embed(text, isQuery: false)
  -> WorldBookVectorStore.upsert(entryId, embedding, meta)
  -> DatabaseManager.write: replace vector row + save indexed meta
```

Backfill 链路：

```text
rebuildAllMissingOrStale(limit)
rebuildMissingOrStale(worldBookId, limit)
  -> scan existing world_book_entry records
  -> per-entry index
  -> failures write failed meta and are aggregated
  -> later entries continue
```

结论：传播面仍限定在 App DI、Core/WorldBook 与 Core/Memory 的 embedding provider 复用。Phase B 没有改变 Prompt/Chat 输入输出，也没有改变世界书 CRUD/import/delete 主链路。

### 三边一致性

- `arch-src`：`arch/data-model.md`、`arch/source-tree.md`、`arch/modules/world-book.md`、`arch/modules/background/world-book-vectorization.md`、`arch/modules/background/sources.md`、`arch/modules/memory/embedding-vector-store.md` 已同步 Phase B 当前实现和 Phase C/D 未实现边界。
- `arch-test`：`WorldBookEmbeddingTextBuilderTests`、`WorldBookEntryHasherTests`、`WorldBookEmbeddingIndexerTests` 覆盖 text/hash/indexer/backfill/failure meta。
- `src-test`：Phase B focused command 12 tests / 3 suites passed；broader focused command 84 tests / 8 suites passed；full suite 在 iOS 26.5 `iPhone 17` 上 273 tests / 50 suites passed，`** TEST SUCCEEDED **`。

### 验证

- Phase B focused command：`xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/WorldBookEmbeddingTextBuilderTests' '-only-testing:OpenChatTests/WorldBookEntryHasherTests' '-only-testing:OpenChatTests/WorldBookEmbeddingIndexerTests'`，结果 12 tests / 3 suites passed，`** TEST SUCCEEDED **`。
- Phase B broader focused command：`xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MigrationTests' '-only-testing:OpenChatTests/VectorStoreTests' '-only-testing:OpenChatTests/WorldBookVectorStoreTests' '-only-testing:OpenChatTests/WorldBookEmbeddingTextBuilderTests' '-only-testing:OpenChatTests/WorldBookEntryHasherTests' '-only-testing:OpenChatTests/WorldBookEmbeddingIndexerTests' '-only-testing:OpenChatTests/PromptAssemblerTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests'`，结果 84 tests / 8 suites passed，`** TEST SUCCEEDED **`。
- Full suite command：`xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,id=2277CB75-AF36-4ABF-84EE-7444C1DD6759'`，实际设备 iOS 26.5 `iPhone 17`，结果 273 tests / 50 suites passed，`** TEST SUCCEEDED **`。
- 同日一次 `iPhone 17 Pro` full-suite 尝试在测试体执行前被 Simulator 拒绝启动，错误为 `Busy ("Application failed preflight checks")`；换用上述 `iPhone 17` 设备后通过。

## 2026-05-16 WorldBook Vectorization Phase C Incremental Audit

范围：`OpenChat/Core/WorldBook/WorldBookRecallModels.swift`、`WorldBookSource.swift`、`OpenChat/Core/PromptEngine/PromptAssembler.swift`、`OpenChat/Features/Chat/ViewModels/ChatViewModel.swift`、`ChatViewModel+Support.swift`、`OpenChat/App/DependencyContainer.swift`、`OpenChat/ContentView.swift`、`OpenChatTests/Core/WorldBookTests/WorldBookSourceTests.swift`、`PromptAssemblerTests.swift`、`ChatViewModelPromptAssemblyTests.swift`、世界书向量化相关 arch/plan 文档。

审计模式：窄范围增量传播审计，执行 `docs/superpowers/plans/2026-05-16-world-book-vectorization/05_phase_c_world_book_source_prompt_compat.md`。本阶段目标是 WorldBookSource + Prompt 兼容接入，不改变 schema，不接入 Feature CRUD/import/delete 维护。

### 静态传播面

- 新增 production Swift 文件 1 个：
  - `Core/WorldBook/WorldBookSource.swift`
- 扩展 `WorldBookRecallModels.swift`：新增 recall result、entry、trace、reason、omission DTO。
- 扩展 `PromptAssembler.swift`：保留旧 `preview(...)` / `assemble(...)` keyword fallback；新增 `previewWithPreselectedWorldBookEntries(...)` / `assembleWithPreselectedWorldBookEntries(...)`，消费 `WorldBookSource` 已预选条目，避免 semantic-only entry 被二次 keyword 过滤。
- 扩展 `DependencyContainer.swift`：生产路径构造 `WorldBookSource`，与 Memory / WorldBook indexer 共用同一个 `EmbeddingService` 和 `WorldBookVectorStore`。
- 扩展 `ChatViewModel` / `ChatViewModel+Support`：注入可选 `WorldBookEmbeddingIndexer` / `WorldBookSource`；Chat 主链路在 prompt preview 前做 bounded lazy rebuild + recall，preview 和 assemble 使用同一批 recalled entries。
- `DatabaseManager+Content.swift`、`Migrations.swift`、`WorldBookEditorViewModel`、WorldBook import/delete UI 未修改；Phase D 维护一致性仍未传播。

### 行为传播链路

Phase C 新增主链路：

```text
ChatViewModel.generateResponse
  -> fetch characterCard/worldBook/worldBookEntries
  -> makePromptHistoryMessages(...) removes current user record
  -> WorldBookEmbeddingIndexer.rebuildMissingOrStale(worldBookId, limit: 8)
       failure: log warning, continue
  -> WorldBookSource.recallEntries(worldBook, entries, promptHistoryMessages, currentInput, limit: 10)
       keyword candidates: KeywordMatcher over recent 5 messages + current input
       semantic candidates: EmbeddingProvider.embed(query, isQuery: true)
         -> WorldBookVectorStore.search(query, worldBookId, limit)
       fusion: keyword+semantic > keyword-only > semantic-only
       failure: semanticUnavailable omission, keyword-only fallback
  -> PromptAssembler.previewWithPreselectedWorldBookEntries(...)
  -> ContextManager.prepareHistory(...)
  -> PromptAssembler.assembleWithPreselectedWorldBookEntries(...)
  -> APIClient.streamMessage(...)
```

Prompt 兼容结论：

- `[World Book Entries]` block 标签、`[World Book: title]` entry 包装和四层顺序未改变。
- semantic-only 世界书条目可以进入当前 prompt。
- `PromptAssembler` 仍是纯拼装/预算裁剪层，不访问 DB、不调用 embedding/KNN。

### 三边一致性

- `arch-src`：`arch/modules/world-book.md`、`arch/modules/prompt-assembly.md`、`arch/modules/background/sources.md`、`arch/modules/background/world-book-vectorization.md`、`arch/data-model.md`、`.github/instructions/prompt-engine.instructions.md` 已同步 Phase C 当前实现和当时的 Phase D / Background 边界；Phase D lifecycle maintenance 后续已关闭，BackgroundWorker 仍未实现。
- `arch-test`：`WorldBookSourceTests` 覆盖 keyword-only、semantic-only、keyword+semantic duplicate merge、disabled world/entry、semantic failure fallback；`PromptAssemblerTests` 覆盖 preselected semantic candidate 的 `[World Book Entries]` block shape；`ChatViewModelPromptAssemblyTests` 覆盖 semantic world book entry 经真实发送链路进入 API request。
- `src-test`：Phase C baseline focused command 67 tests / 4 suites passed；Phase C focused command 34 tests / 3 suites passed；Phase A/B/C broader focused command 92 tests / 9 suites passed；Phase C closeout full suite 281 tests / 51 suites passed，`** TEST SUCCEEDED **`。

### 验证

- Baseline focused command：`xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MigrationTests' '-only-testing:OpenChatTests/VectorStoreTests' '-only-testing:OpenChatTests/PromptAssemblerTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests'`，结果 67 tests / 4 suites passed，`** TEST SUCCEEDED **`。
- Phase C focused command：`xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/WorldBookSourceTests' '-only-testing:OpenChatTests/PromptAssemblerTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests'`，结果 34 tests / 3 suites passed，`** TEST SUCCEEDED **`。
- Phase A/B/C broader focused command：`xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MigrationTests' '-only-testing:OpenChatTests/VectorStoreTests' '-only-testing:OpenChatTests/WorldBookVectorStoreTests' '-only-testing:OpenChatTests/WorldBookEmbeddingTextBuilderTests' '-only-testing:OpenChatTests/WorldBookEntryHasherTests' '-only-testing:OpenChatTests/WorldBookEmbeddingIndexerTests' '-only-testing:OpenChatTests/WorldBookSourceTests' '-only-testing:OpenChatTests/PromptAssemblerTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests'`，结果 92 tests / 9 suites passed，`** TEST SUCCEEDED **`。
- 一次中间 Phase C focused 重试在测试执行前被 Swift 6 编译检查拦截：新增 Chat 测试用 `var card` 被 `DatabaseManager.write` 的 concurrently-executing closure 捕获；已改为不可变 `CharacterCardRecord` 构造后通过。该失败是测试代码并发约束修复，不是产品行为回归。
- Full suite command：`xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`，实际设备 iOS 26.5 `iPhone 17 Pro`，结果 281 tests / 51 suites passed，`** TEST SUCCEEDED **`。
- 同日一次 full-suite 重试在 `EmbeddingServiceTests.test_embedding_outputs_384_finite_normalized_values` 处出现 app bundle 内 `MultilingualE5Small.mlmodelc` runtime lookup 失败；随后 `EmbeddingServiceTests` 4 tests / 1 suite passed，最终 full suite 281 tests / 51 suites passed。当前未复现为稳定失败。

### 未完成边界

- 当时边界：D 阶段 lifecycle maintenance 不在 Phase C 范围；当前已由后续 Phase D 写回关闭，见下方 `WorldBook Vectorization Phase D Incremental Audit`。
- BackgroundWorker：`WorldBookBackgroundSource` 后续已在 2026-05-17 Phase 4D 落地；统一 BackgroundCandidate 到 BackgroundPacket 的 worker 调度仍未实现。
- 当前 `AssemblyResult.triggeredEntries` 名称仍保持兼容，实际可表示 selected world book entry ids；后续可独立重命名但本阶段未扩大 API churn。

## 2026-05-16 WorldBook Vectorization Phase D Incremental Audit

范围：`OpenChat/Core/Database/DatabaseManager.swift`、`DatabaseManager+Content.swift`、`OpenChat/Features/WorldBook/ViewModels/WorldBookEditorViewModel.swift`、`WorldBookEditorView.swift`、`WorldBookListView.swift`、`OpenChat/Features/Settings/ViewModels/SettingsViewModel.swift`、`DataManagementView.swift`、`SidebarView.swift`、`OpenChat/Resources/Localizable.xcstrings`、`OpenChatTests/Core/DatabaseTests/DatabaseManagerWorldBookTests.swift`、`OpenChatTests/Features/WorldBookTests/WorldBookEditorViewModelTests.swift`、`OpenChatTests/Features/SettingsTests/SettingsViewModelWorldBookIndexTests.swift`、世界书向量化相关 arch/harness 文档。

审计模式：窄范围增量传播审计，执行 `docs/superpowers/plans/2026-05-16-world-book-vectorization/06_phase_d_crud_import_delete_wiring.md`。本阶段目标是 CRUD/import/delete/eraseAllData 维护闭环和手动 rebuild，不改变 Prompt 输出格式，不引入 BackgroundWorker。

### 静态传播面

- `DatabaseManager+Content.swift`：`deleteWorldBookEntry(id:)` 和 `deleteWorldBook(id:)` 在删除业务 record 前显式调用 world book vector/meta cleanup helper；新增 `saveWorldBookEntries(_:)` 支持 import batch 单事务保存。
- `DatabaseManager.swift`：`eraseAllData(...)` 先清理 `memory_embedding`，再清理 `world_book_entry_embedding` 和 `world_book_entry_embedding_meta`，随后删除 message/conversation/worldBookEntry/worldBook/character。
- `WorldBookEditorViewModel.swift`：注入 `WorldBookEmbeddingIndexer`；`saveEntry(_:)` 保存成功后调用 `index(entry:)`；`importEntries(_:)` 保存 worldBook + 批量 entries 后调用 `index(entries:)`，并缓存新建 worldBook id。
- `WorldBookEditorView.swift` / `WorldBookListView.swift`：传递 indexer，显示 non-blocking indexing warning，import 改为调用 ViewModel 批量方法。
- `SettingsViewModel.swift` / `DataManagementView.swift` / `SidebarView.swift`：Data Management 新增 “Rebuild World Book Semantic Index” 入口，调用 `rebuildAllMissingOrStale(limit: nil)` 并展示 running / result 状态。
- `Localizable.xcstrings`：新增 rebuild 和 index warning 文案。
- `OpenChat.xcodeproj/project.pbxproj`：仅加入 Phase D 新测试文件到 test target；签名配置未修改。

### 行为传播链路

Save / update 链路：

```text
WorldBookEntryEditorView onSave
  -> WorldBookEditorViewModel.saveEntry(entry)
  -> DatabaseManager.saveWorldBookEntry(entry)
  -> WorldBookEmbeddingIndexer.index(entry)
       fresh: skippedFresh
       success: upsert vector + indexed meta
       failure: failed meta + indexingWarningMessage; entry remains saved
  -> reload entries
```

Import 链路：

```text
WorldBookImportView
  -> WorldBookEditorViewModel.importEntries(parsed)
  -> save/reuse worldBook id
  -> DatabaseManager.saveWorldBookEntries(entries)
  -> WorldBookEmbeddingIndexer.index(entries)
       single failure does not roll back imported entries
  -> reload entries once
```

Delete / clear 链路：

```text
deleteWorldBookEntry(id)
  -> DELETE world_book_entry_embedding WHERE entry_id = ?
  -> DELETE world_book_entry_embedding_meta WHERE entryId = ?
  -> DELETE world_book_entry

deleteWorldBook(id)
  -> DELETE world_book_entry_embedding WHERE entry_id IN current world book entries
  -> DELETE world_book_entry_embedding_meta WHERE entryId IN current world book entries
  -> DELETE world_book

eraseAllData(...)
  -> DELETE memory_embedding
  -> DELETE world_book_entry_embedding
  -> DELETE world_book_entry_embedding_meta
  -> delete content tables
```

Manual rebuild 链路：

```text
DataManagementView
  -> SettingsViewModel.rebuildWorldBookSemanticIndex()
  -> WorldBookEmbeddingIndexer.rebuildAllMissingOrStale(limit: nil)
  -> status message with indexed/skipped/failed counts
```

### 三边一致性

- `arch-src`：`arch/data-model.md`、`arch/modules/world-book.md`、`arch/modules/background/world-book-vectorization.md`、`arch/modules/background/sources.md` 已同步 Phase D 当前实现；BackgroundWorker 仍明确为未实现。
- `arch-test`：`WorldBookEditorViewModelTests` 覆盖 save index、index failure non-blocking、import batch index、新建 worldBook import 后 id 复用；`DatabaseManagerWorldBookTests` 覆盖 delete entry/delete worldBook/eraseAllData vector/meta cleanup；`SettingsViewModelWorldBookIndexTests` 覆盖 Data Management rebuild backfill；`CriticalSaveFlowTests` 继续防止 editor save 失败时静默 dismiss。
- `src-test`：Phase D focused command 9 tests / 4 suites passed；Final A/B/C/D focused acceptance command 94 tests / 12 suites passed；full suite 289 tests / 54 suites passed，`** TEST SUCCEEDED **`。

### 验证

- Baseline focused command：`xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MigrationTests' '-only-testing:OpenChatTests/VectorStoreTests' '-only-testing:OpenChatTests/PromptAssemblerTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests'`，结果 69 tests / 4 suites passed，`** TEST SUCCEEDED **`。
- Phase D focused command：`xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/WorldBookEditorViewModelTests' '-only-testing:OpenChatTests/DatabaseManagerWorldBookTests' '-only-testing:OpenChatTests/CriticalSaveFlowTests' '-only-testing:OpenChatTests/SettingsViewModelWorldBookIndexTests'`，最终结果 9 tests / 4 suites passed，`** TEST SUCCEEDED **`。
- Final A/B/C/D focused acceptance command：`xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MigrationTests' '-only-testing:OpenChatTests/WorldBookVectorStoreTests' '-only-testing:OpenChatTests/WorldBookEmbeddingTextBuilderTests' '-only-testing:OpenChatTests/WorldBookEntryHasherTests' '-only-testing:OpenChatTests/WorldBookEmbeddingIndexerTests' '-only-testing:OpenChatTests/WorldBookSourceTests' '-only-testing:OpenChatTests/PromptAssemblerTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests' '-only-testing:OpenChatTests/WorldBookEditorViewModelTests' '-only-testing:OpenChatTests/DatabaseManagerWorldBookTests' '-only-testing:OpenChatTests/CriticalSaveFlowTests' '-only-testing:OpenChatTests/SettingsViewModelWorldBookIndexTests'`，结果 94 tests / 12 suites passed，`** TEST SUCCEEDED **`。
- Full suite command：`xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`，实际设备 iOS 26.5 `iPhone 17 Pro`，结果 289 tests / 54 suites passed，`** TEST SUCCEEDED **`。
- 中间 focused 重试曾暴露两类问题：Swift 6 要求 `DatabaseManager.write` closure 内显式 `self` 调用 cleanup helper；`WorldBookEditorViewModelTests` 初始被加入错误 Xcode group 路径。均已修复后通过。

### 未完成边界

- `WorldBookBackgroundSource` 后续已在 2026-05-17 Phase 4D 落地；`BackgroundWorker` / `BackgroundPacket` 统一调度仍未实现。
- Prompt 输出仍保持 `[World Book Entries]` 兼容 block；本阶段不切换 Background packet。

## AgentCore Foundation 增量传播审计（2026-05-17）

范围：`OpenChat/Core/AgentCore/*`、`OpenChatTests/Core/AgentCoreTests/*`、`OpenChat.xcodeproj/*`、AgentCore / Background / Stage / LibMan 相关 arch 文档、`PLANING.md`、`docs/superpowers/plans/2026-05-17-agent-core-foundation/*`、`harness/2026.05.17/agent-core-foundation/index.md`。

审计模式：窄范围新增基座审计。OpenChat 当前没有 Swift AST import graph 脚本，本轮沿用文件级传播审计 + 行为链路审计：`git diff --name-only`、`rg` source symbol scan、project membership scan、focused tests 和 full suite。

### 静态传播面

- 新增 `OpenChat/Core/AgentCore/` 下 13 个 Swift source 文件，覆盖 identity、capability/policy、task/context/result、diagnostics/schema、executor 和 typed error。
- 新增 `OpenChatTests/Core/AgentCoreTests/` 下 4 个 focused test 文件，覆盖 descriptor、policy、deterministic executor 和 diagnostics。
- `ruby scripts/generate_xcodeproj.rb` 已重新生成 project；`OpenChat.xcodeproj/project.pbxproj` 包含 AgentCore source/test membership，`OpenChat.xcodeproj/xcshareddata/xcschemes/OpenChat.xcscheme` 的 target `BlueprintIdentifier` 随 generator target UUID 更新。
- 签名关键值仍由脚本保持：`PRODUCT_BUNDLE_IDENTIFIER = fukujusou.openchat.com`、`DEVELOPMENT_TEAM = GZAC7644XS`、`CODE_SIGN_STYLE = Automatic`；test bundle id 仍为 `com.openchat.app.tests`。

未触达的禁止传播面：

- `OpenChat/App/DependencyContainer.swift`
- `OpenChat/Features/Chat/ViewModels/ChatViewModel.swift`
- `OpenChat/Features/Chat/ViewModels/ChatViewModel+Support.swift`
- `OpenChat/Core/PromptEngine/*`
- `OpenChat/Core/Memory/*`
- `OpenChat/Core/WorldBook/*`
- `OpenChat/Core/Database/*`
- `OpenChat/Core/Networking/*`
- `OpenChat/Features/*/Views/*`
- `OpenChat/Resources/Localizable.xcstrings`

### 行为传播链路

AgentCore 当前只提供 zero-runtime-consumer Core contract：

```text
AgentTask
  -> DeterministicAgentExecutor.execute(...)
  -> policy/capability/network/database-write preflight
  -> task.run(...)
  -> AgentExecutionResult(output, diagnostics)
```

主聊天链路未接入 AgentCore，仍保持：

```text
ChatViewModel.generateResponse
  -> MemoryManager.retrieveMemories / WorldBookSource.recallEntries
  -> PromptAssembler.preview / assemble
  -> ContextManager.prepareHistory
  -> APIClient.streamMessage
```

结论：

- `AgentPolicy.backgroundWorkerDefault()` 只允许 deterministic/internal diagnostics，不开放 LLM、web search 或 database write。
- `AgentPolicy.directorDefault(allowsLLM:)` 可选 LLM，但不开放 web search 或 database write。
- `AgentPolicy.librarianDraftDefault()` 允许 LLM/webSearch/userVisibleDraft，tool policy 限定 `exa`，并要求 draft apply / persistent write confirmation。
- `DeterministicAgentExecutor` 会在执行 task 前拒绝 unsupported capability、network tool 和 database write。
- `AgentDiagnostics` 随 execution result 返回，不写 DB，不拼入 prompt，不展示到聊天 UI。

### 三边一致性

- `arch-src`：`arch/modules/agent-core.md` 已从目标架构更新为 AgentCore foundation 已落地；BackgroundWorker、Director、LibMan 文档只标记为可复用 AgentCore contract，runtime 仍未实现。
- `arch-test`：`AgentDescriptorTests`、`AgentPolicyTests`、`DeterministicAgentExecutorTests`、`AgentDiagnosticsTests` 覆盖 stable raw values、policy profile、denial behavior、diagnostics shape 和 `LocalizedError` 文案。
- `src-test`：AgentCore focused 12 tests / 4 suites passed；主链路 focused 50 tests / 4 suites passed；full suite 303 tests / 58 suites passed，`** TEST SUCCEEDED **`。

### 验证

- Simulator discovery：`xcrun simctl list devices available | rg 'iPhone'`，实际使用 `iPhone 17 Pro`。
- 主链路 focused baseline / regression：`xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/PromptAssemblerTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests' '-only-testing:OpenChatTests/MemoryManagerRetrievalTests' '-only-testing:OpenChatTests/WorldBookSourceTests'`，结果 50 tests / 4 suites passed。
- AgentCore focused：`xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/AgentDescriptorTests' '-only-testing:OpenChatTests/AgentPolicyTests' '-only-testing:OpenChatTests/DeterministicAgentExecutorTests' '-only-testing:OpenChatTests/AgentDiagnosticsTests'`，结果 12 tests / 4 suites passed。
- Full suite：`xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`，结果 303 tests / 58 suites passed。

### 未完成边界

- 2026-05-17 Phase 4A-4D 已完成 `Core/Background` 的 source tool contract、`MemoryRecallTool`、`WorldBookRecallTool`、`MemoryBackgroundSource` 和 `WorldBookBackgroundSource`。
- `BackgroundWorker` / `BackgroundPacket` / `BackgroundManager` / `BackgroundAssembler` 未实现。
- Chat 主链路未切换到 `BackgroundManager.prepare(...)`。
- `PromptAssembler` 未消费 `BackgroundPacket`。
- Director runtime / LibMan runtime / Exa broker 未实现。
- 未新增 database migration。

## Background Source Tool 顺序修正传播审计（2026-05-17）

范围：`PLANING.md`、`arch/modules/agent-core.md`、`arch/modules/background/*`、`arch/modules/memory/*`、`arch/modules/world-book.md`、`docs/superpowers/plans/2026-05-17-agent-core-foundation/*`。

审计模式：docs-only 窄范围传播审计。触发原因是计划顺序修正：AgentCore foundation 已完成后，不应直接进入 `Core/Background` DTO / BackgroundWorker；应先暴露 Memory / WorldBook 的内部 read-only source tool。该段是 Phase 4A-4D 落地前的历史记录；当前 source tool / adapter 状态以后续 `Background Source Tools Phase 4 docs/harness baseline` 段为准。

### 静态传播面

- 本次不修改 Swift 源码、Xcode project、数据库 migration、测试文件或资源。
- 文档传播面限定在 Background / AgentCore / Memory / WorldBook 架构说明、AgentCore 计划包 closeout 文档和本 AntiEntropy 写回。
- 当时源码事实保持不变：`MemoryManager.recallMemories(...)` 与 `WorldBookSource.recallEntries(...)` 是下一步 source tool 应包装的对象。后续 Phase 4A-4D 已完成对应 wrappers 和 adapters。

### 行为传播结论

当前主聊天链路仍保持：

```text
ChatViewModel.generateResponse
  -> MemoryManager.retrieveMemories / WorldBookSource.recallEntries
  -> PromptAssembler.preview / assemble
  -> ContextManager.prepareHistory
  -> APIClient.streamMessage
```

本次文档修正后的目标顺序为：

```text
AgentCore foundation
  -> MemoryRecallTool / WorldBookRecallTool
  -> MemoryBackgroundSource / WorldBookBackgroundSource
  -> Core/Background DTO
  -> deterministic BackgroundWorker
  -> Chat / Prompt switch to BackgroundPacket
```

结论：

- BackgroundWorker 仍是 AgentCore 的受限 consumer，但不是紧邻下一步实现入口。
- `MemoryRecallTool` / `WorldBookRecallTool` 是内部 read-only source tool，不是普通角色 tool call，不向用户暴露，不生成 assistant message。
- Memory tool 只能包装 `MemoryManager.recallMemories(...)` / `MemoryRecallResult`，不复制 Memory rank fusion。
- WorldBook tool 只能包装 `WorldBookSource.recallEntries(...)` / `WorldBookRecallResult`，不复制 keyword + semantic fusion，也不通过 BackgroundWorker 触发索引 rebuild。
- BackgroundWorker 后续只消费 `BackgroundCandidate` 和 diagnostics metadata，不直接读写 Memory / WorldBook 数据库。

### 三边一致性

- `arch-src`：当时文档已把“下一步直接 BackgroundWorker”修正为“先 source tool 暴露，再 Background DTO / worker”；未提前把 source tool 或 BackgroundWorker 写成已实现。后续 Phase 4A-4D 段已把 source tool / adapter 更新为当前已实现。
- `arch-test`：本次无源码变更，不新增测试；仍沿用 AgentCore closeout 的 303 tests / 58 suites 基线作为上一轮实现证据。后续 Phase 4A-4D 已补充 focused tests。
- `src-test`：未运行。docs-only 改动不改变 runtime；后续 source tool 计划包需要新增 focused tests；该要求已在 2026-05-17 Phase 4A-4D closeout 中完成。

### 未完成边界

> 2026-05-17 后续 Phase 4A-4D 已完成 `MemoryRecallTool`、`WorldBookRecallTool`、`BackgroundSourceTool`、`MemoryBackgroundSource`、`WorldBookBackgroundSource` 和 focused tests。以下仅保留 Phase 5/6 仍未实现边界。

- `BackgroundWorker` / `BackgroundPacket` / `BackgroundManager` / `BackgroundAssembler` 未实现。
- Chat 主链路未切换到 `BackgroundManager.prepare(...)`。
- `PromptAssembler` 未消费 `BackgroundPacket`。

## Background Source Tools Phase 4 docs/harness baseline（2026-05-17）

范围：`docs/superpowers/plans/2026-05-17-background-source-tools/`、`arch/modules/background/*`、`arch/modules/memory/*`、`arch/modules/world-book.md`、live Swift source anchors、`harness/2026.05.17/background-source-tools/`。

审计模式：文档 / harness evidence 同步；docs lane 不主动修改 runtime source。执行中 concurrent source workers 落地了 Phase 4A-4D，本审计记录当前真实状态、target/test 证据和 Phase 5/6 后置边界，避免把 source tool / adapter pass 误读为 worker/prompt switch 已落地。

### 静态传播面

- `OpenChat/Core/Background/BackgroundSourceTool.swift` 已出现并进入 Xcode target。
- `OpenChat/Core/Memory/MemoryRecallTool.swift` 已出现并进入 Xcode target。
- `OpenChat/Core/WorldBook/WorldBookRecallTool.swift` 已出现并进入 Xcode target。
- `OpenChatTests/Core/MemoryTests/MemoryRecallToolTests.swift` 与 `OpenChatTests/Core/WorldBookTests/WorldBookRecallToolTests.swift` 已出现并进入 Xcode target。
- `OpenChat/Core/Background/MemoryBackgroundSource.swift` / `WorldBookBackgroundSource.swift` 已出现并进入 Xcode target。
- `OpenChatTests/Core/BackgroundTests/BackgroundSourceTests.swift` 已出现并进入 Xcode target。
- 本轮实际写回新增 `harness/2026.05.17/background-source-tools/index.md` 与 `evidence.txt`，并更新本传播审计、Background migration plan 和相关 arch status。

### 行为传播结论

当前主聊天链路仍保持：

```text
ChatViewModel.generateResponse
  -> MemoryManager.retrieveMemories(...)
  -> WorldBookSource.recallEntries(...)
  -> PromptAssembler.preview / assemble
  -> ContextManager.prepareHistory
  -> APIClient.streamMessage
```

已确认的可包装前置 contract：

- `MemoryManager.recallMemories(...)` 返回 `MemoryRecallResult(entries, trace)`；trace 包含 candidate counts、selected ids、omitted 和 fallback。
- `WorldBookSource.recallEntries(...)` 返回 `WorldBookRecallResult(entries, trace)`；trace 包含 keyword/semantic candidate counts、selected ids 和 omissions。
- `MemoryRecallTool` 只调用 `MemoryManager.recallMemories(...)`，focused tests 覆盖 result order、rank、reasons、selected ids、omitted 和 fallback 透传。
- `WorldBookRecallTool` 只调用 `WorldBookSource.recallEntries(...)`，focused tests 覆盖 keyword-only、semantic-only、hybrid、disabled、semanticUnavailable、staleEmbedding、limit/duplicate omission 透传和无 indexer/rebuild dependency。
- `WorldBookRecallTool` 与 `MemoryRecallTool` 均符合 `BackgroundSourceTool`，source type 分别为 `.worldBook` / `.memory`。
- `MemoryBackgroundSource` / `WorldBookBackgroundSource` 把 recall result 映射为 `BackgroundCandidate`，focused tests 覆盖 source-prefixed ids、顺序、metadata、request 边界和不按 token budget 裁剪。
- `ChatViewModel+Support` 当前仍在世界书召回前执行 bounded `rebuildMissingOrStale(worldBookId:limit:)`；后续不能把 rebuild 变成 `BackgroundWorker` side effect。
- `PromptAssembler` 仍直接生成 `[Memories]` / `[World Book Entries]` 兼容 block；未消费 `BackgroundPacket`。

### 验证

Baseline focused command：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MemoryManagerRetrievalTests' '-only-testing:OpenChatTests/WorldBookSourceTests' '-only-testing:OpenChatTests/PromptAssemblerTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests' '-only-testing:OpenChatTests/AgentPolicyTests' '-only-testing:OpenChatTests/DeterministicAgentExecutorTests'
```

结果：58 tests / 6 suites passed，`** TEST SUCCEEDED **`。

Phase 4A-4C + regression focused command：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MemoryRecallToolTests' '-only-testing:OpenChatTests/WorldBookRecallToolTests' '-only-testing:OpenChatTests/MemoryManagerRetrievalTests' '-only-testing:OpenChatTests/WorldBookSourceTests' '-only-testing:OpenChatTests/PromptAssemblerTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests' '-only-testing:OpenChatTests/AgentPolicyTests' '-only-testing:OpenChatTests/DeterministicAgentExecutorTests'
```

结果：68 tests / 8 suites passed，`** TEST SUCCEEDED **`。

Phase 4A-4D closeout focused command：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MemoryRecallToolTests' '-only-testing:OpenChatTests/WorldBookRecallToolTests' '-only-testing:OpenChatTests/BackgroundSourceTests' '-only-testing:OpenChatTests/MemoryManagerRetrievalTests' '-only-testing:OpenChatTests/WorldBookSourceTests' '-only-testing:OpenChatTests/PromptAssemblerTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests' '-only-testing:OpenChatTests/AgentPolicyTests' '-only-testing:OpenChatTests/DeterministicAgentExecutorTests'
```

结果：74 tests / 9 suites passed，`** TEST SUCCEEDED **`。

该结果证明 Phase 4A-4D source contract、recall tool pass-through、BackgroundSource adapter mapping 与现有回归面通过；不能作为 Phase 5/6 worker / packet / prompt switch 完成证据。

Full suite：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

结果：319 tests / 61 suites passed，`** TEST SUCCEEDED **`。

### 未完成边界

- 2026-05-17 后续 Phase 5/6 已完成 `BackgroundWorker` / `BackgroundPacket` / `BackgroundManager` / `BackgroundAssembler` 与 Chat/Prompt compatible switch。以下新增段为当前状态。

## Background Worker / Prompt Switch Phase 5/6 增量传播审计（2026-05-17）

范围：`OpenChat/Core/Background/*`、`OpenChat/Core/PromptEngine/PromptAssembler.swift`、`OpenChat/App/DependencyContainer.swift`、`OpenChat/ContentView.swift`、`OpenChat/Features/Chat/ViewModels/ChatViewModel.swift`、`OpenChat/Features/Chat/ViewModels/ChatViewModel+Support.swift`、`OpenChat/Features/Chat/Views/ChatView.swift`、Background / Prompt / Chat focused tests、相关 arch/harness 写回。

审计模式：窄范围增量审计。OpenChat 当前没有 Magnum Agent 的静态 import 图脚本，本轮继续使用 `rg` 引用面 + live Swift 行为链路复核；静态传播面和行为传播结论分开记录。

### 静态传播面

新增 / 修改 runtime surface：

- `OpenChat/Core/Background/BackgroundPolicy.swift`
- `OpenChat/Core/Background/BackgroundPacket.swift`
- `OpenChat/Core/Background/BackgroundDiagnostics.swift`
- `OpenChat/Core/Background/BackgroundWorker.swift`
- `OpenChat/Core/Background/BackgroundManager.swift`
- `OpenChat/Core/Background/BackgroundAssembler.swift`
- `OpenChat/Core/Background/BackgroundSourceTool.swift`：`BackgroundSourceType` 增加 `CaseIterable` / `Hashable` conformance，source cases 仍只有 `.memory` / `.worldBook`。
- `OpenChat/Core/PromptEngine/PromptAssembler.swift`：新增 packet-aware preview/assemble overload，旧 direct overload 保留。
- `OpenChat/App/DependencyContainer.swift`：装配 `BackgroundManager`。
- `OpenChat/ContentView.swift`、`OpenChat/Features/Chat/Views/ChatView.swift`：向 `ChatViewModel` 注入 manager。
- `OpenChat/Features/Chat/ViewModels/ChatViewModel.swift`：新增可选 `backgroundManager` 依赖。
- `OpenChat/Features/Chat/ViewModels/ChatViewModel+Support.swift`：主生成链路调用 `BackgroundManager.prepare(...)`，bounded worldBook rebuild 留在 Chat pre-source stage。

新增 / 修改测试 surface：

- `OpenChatTests/Core/BackgroundTests/BackgroundPacketTests.swift`
- `OpenChatTests/Core/BackgroundTests/BackgroundWorkerTests.swift`
- `OpenChatTests/Core/BackgroundTests/BackgroundDiagnosticsTests.swift`
- `OpenChatTests/Core/BackgroundTests/BackgroundManagerTests.swift`
- `OpenChatTests/Core/PromptEngineTests/PromptAssemblerTests.swift`
- `OpenChatTests/Features/ChatTests/ChatViewModelPromptAssemblyTests.swift`

未修改面：

- 未新增 DB migration。
- 未修改 `OpenChat/Core/WorldBook/WorldBookEmbeddingIndexer.swift`。
- 未修改 `OpenChat/Core/Networking/*`。
- 未修改 `scripts/generate_xcodeproj.rb` 或签名配置；新增 Swift 文件通过 `ruby scripts/generate_xcodeproj.rb` 进入 target。

### 行为传播结论

主聊天链路已从 direct Memory / WorldBook final injection 切换为 packet-compatible path：

```text
ChatViewModel.generateResponse
  -> persist / filter current user message
  -> pre-response Memory extraction remains Chat-owned
  -> bounded WorldBookEmbeddingIndexer.rebuildMissingOrStale(...) remains Chat-owned
  -> BackgroundManager.prepare(...)
       -> MemoryBackgroundSource / WorldBookBackgroundSource
       -> BackgroundWorker.run(...)
       -> BackgroundPacket
  -> PromptAssembler.preview(... backgroundPacket:)
  -> ContextManager.prepareHistory(...)
  -> PromptAssembler.assemble(... backgroundPacket:)
  -> APIClient.streamMessage(...)
```

Boundary conclusions:

- `BackgroundWorker` only consumes `[BackgroundCandidate]`; it does not call LLM, network, DB write/read APIs, MemoryManager, WorldBookSource, WorldBookEmbeddingIndexer, or create assistant messages.
- `BackgroundPolicy.tokenBudget` is the worker candidate selection ceiling; final inclusion into request body remains `PromptAssembler` token-budget trimming.
- `BackgroundManager` handles single-source failure with diagnostics warnings. For worldBook source failure, it preserves the old keyword fallback by creating `.worldBook` candidates from `BackgroundRequest.worldBookEntries` + recent context + current input.
- `BackgroundAssembler` keeps compatibility output: `[World Book Entries]` before `[Memories]`. `BackgroundPacket.diagnostics`, score, and omission reasons do not enter prompt content.
- Bounded worldBook rebuild remains in `ChatViewModel+Support.swift` before manager prepare; it is not a worker/source side effect.
- `makePromptHistoryMessages(...)` remains the guard preventing current input duplication.
- Unified `[Background]` block remains unimplemented and requires separate request-shape tests / user confirmation.

### 验证

Phase 5/6 focused command：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/BackgroundPacketTests' '-only-testing:OpenChatTests/BackgroundWorkerTests' '-only-testing:OpenChatTests/BackgroundDiagnosticsTests' '-only-testing:OpenChatTests/BackgroundManagerTests' '-only-testing:OpenChatTests/PromptAssemblerTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests'
```

结果：40 tests / 6 suites passed，`** TEST SUCCEEDED **`。

Broader source / AgentCore regression command：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MemoryRecallToolTests' '-only-testing:OpenChatTests/WorldBookRecallToolTests' '-only-testing:OpenChatTests/BackgroundSourceTests' '-only-testing:OpenChatTests/MemoryManagerRetrievalTests' '-only-testing:OpenChatTests/WorldBookSourceTests' '-only-testing:OpenChatTests/AgentPolicyTests' '-only-testing:OpenChatTests/DeterministicAgentExecutorTests'
```

结果：45 tests / 7 suites passed，`** TEST SUCCEEDED **`。

`git diff --check`：通过，无 whitespace errors。

### 未完成边界

- 统一 `[Background]` block 未默认启用。
- CharacterBackgroundSource / ConversationStateBackgroundSource 未实现；当前 `BackgroundSourceType` 只有 `.memory` / `.worldBook`。
- LibMan / Exa / LLM-assisted selector / synthesis worker 未实现。
- bounded worldBook rebuild 尚未迁移进 manager pre-source stage；当前仍由 ChatViewModel 负责。

## Memory Reflect Observation Synthesis Phase 5 增量传播审计（2026-05-18）

范围：`OpenChat/Core/Database/Migrations.swift`、`DatabaseManager+Memory.swift`、`MemoryEntryProvenanceRecord.swift`、`OpenChat/Core/Memory/MemoryReflectModels.swift`、`MemoryManager.swift`、`VectorStore.swift`、`MemoryDependencies.swift`、`MemoryError.swift`、`OpenChat/Core/AgentCore/AgentPolicy.swift`、`OpenChat/App/DependencyContainer.swift`、`OpenChat/Features/CharacterCard/*MemoryList*`、`OpenChat/Resources/Localizable.xcstrings`、Memory / DB / AgentPolicy focused tests、相关 arch/harness 写回。

审计模式：窄范围增量审计。修改前已按计划拆成 DB/VectorStore、parser/executor/API、UI/docs 三条只读 lane，确认 `memory_entry_link` 不存在、最新 migration 为 v16、executor 可复用 `APIClient.sendMessage(...)` 且无需修改 Chat/Prompt/provider request shape，UI 需要新增 selection/draft/apply/error state。

### 静态传播面

新增 / 修改 runtime surface：

- `Migrations.swift`：只追加 `v17_create_memory_entry_link`；v1-v16 未修改。
- `MemoryEntryProvenanceRecord.swift`：追加 target-backed `MemoryEntryLinkRecord`，避免 Xcode project membership churn。
- `DatabaseManager+Memory.swift`：新增 link save/fetch/validation，按 `from/to/relation` 去重。
- `MemoryReflectModels.swift`：新增 prompt builder、single-object JSON parser、executor、result/diagnostics；executor 只产出 draft，不写 DB。
- `MemoryManager.swift`：新增 `applyReflectObservation(...)`，只支持 `.insertObservation`。
- `VectorStore.swift` / `MemoryDependencies.swift`：新增 entry + embedding + links 原子写入协议与实现。
- `AgentPolicy.swift`：新增 `reflectDefault()`，允许 LLM / DB read / diagnostics，禁止 web / DB write。
- `DependencyContainer.swift`、`CharacterCardDetailView.swift`、`MemoryListViewModel.swift`、`MemoryListView.swift`、`Localizable.xcstrings`：新增手动整理入口、2-5 选择、draft preview、Apply/Cancel 和可见错误。

未修改面：

- 未修改 `ChatViewModel+Support.swift`、`PromptAssembler.swift`、`BackgroundWorker.swift`、`MemoryBackgroundSource.swift`、`WorldBookBackgroundSource.swift`。
- 未修改 `ResponsesAPIRequest.swift` 或 provider request shape。
- 未修改 `scripts/generate_xcodeproj.rb`、签名配置或新增 Swift 文件 target membership。
- 未接 Exa / LibMan / web search；reflect 未进入每轮 Chat send path。

### 行为传播结论

手动 reflect 链路：

```text
MemoryListView
  -> MemoryListViewModel selectedMemoryIds (2...5)
  -> MemoryReflectExecutor.reflect(...)
       -> fetchMemories(ids:)
       -> preserve request source order
       -> reject missing / cross-character sources
       -> APIClient.sendMessage(...)
       -> MemoryReflectParser.parse(...)
  -> reflectDraft visible in MemoryListView
  -> MemoryManager.applyReflectObservation(...)
       -> validate basedOn source ids and character boundary
       -> embed new observation
       -> VectorStore.insert(entry:embedding:links:)
       -> memory_entry + memory_embedding + memory_entry_link(relation = summarizes)
```

Boundary conclusions:

- Reflect executor does not write DB and does not create assistant messages.
- Confirmed apply writes a new observation memory with `sourceConversationId = nil` and conservative importance 60; original source memories are retained.
- `.markDuplicate` and `.needsUserReview` are rejected for automatic apply; duplicate deletion / conflict resolution remains a future review flow.
- `memory_entry_link` from/to FKs cascade on memory deletion, and link/FK/embedding failure rolls back the observation write.
- Parser requires one JSON object and validates `content` / `type` / `basedOn` / `confidence` / `suggestedAction`; unknown `basedOn` ids are rejected before apply.
- Current implementation is a manual Memory management entry only; idle/background automatic reflect is not enabled.

### 验证

Lead focused closeout command：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MemoryReflectModelsTests' '-only-testing:OpenChatTests/VectorStoreTests' '-only-testing:OpenChatTests/DatabaseManagerMemoryTests' '-only-testing:OpenChatTests/MigrationTests' '-only-testing:OpenChatTests/AgentPolicyTests'
```

结果：84 tests / 5 suites passed，`** TEST SUCCEEDED **`。xcresult：`/Users/fukujusou/Library/Developer/Xcode/DerivedData/OpenChat-fiicdnsnwoygvnahvbxvezbhtsfy/Logs/Test/Test-OpenChat-2026.05.18_01-21-54-+0800.xcresult`。

其他检查：

- `git diff --check`：通过。
- `python3 -m json.tool OpenChat/Resources/Localizable.xcstrings >/dev/null`：通过。
- 默认 iOS 26.5 `iPhone 17 Pro` destination full suite 在启动测试 runner 前遇到 simulator Busy：`Application failed preflight checks`。改用 alternate simulator `id=F8D0D88B-71FD-471F-855A-B2B5D8267117` 后 full suite 通过 360 tests / 66 suites，`** TEST SUCCEEDED **`。xcresult：`/Users/fukujusou/Library/Developer/Xcode/DerivedData/OpenChat-fiicdnsnwoygvnahvbxvezbhtsfy/Logs/Test/Test-OpenChat-2026.05.18_01-42-36-+0800.xcresult`。

### 未完成边界

- idle/background 自动 reflect 未实现。
- duplicate/conflict 用户审阅专页和自动合并策略未实现。
- 统一 `[Background]` block 与 Background request-shape audit 未实现。
- Memory reflect UI 尚无 XCUITest 端到端点击覆盖。

## Director Mode Foundation Phase 6 增量传播审计（2026-05-19）

范围：`OpenChat/Core/Stage/*`、`OpenChatTests/Core/StageTests/DirectorContractTests.swift`、`OpenChatTests/Core/AgentCoreTests/AgentPolicyTests.swift`、Xcode project target membership、Stage / Director arch 文档、PLANING、harness closeout。

审计模式：窄范围增量审计。该轮只落 Director / 导演模式 contract foundation，不接入 Chat 主链路，不新增 DB migration，不修改 UI / InputBar / production `PromptAssembler` / Background runtime。

### 静态传播面

新增 production surface：

- `OpenChat/Core/Stage/DirectorMode.swift`
- `OpenChat/Core/Stage/StageInstruction.swift`
- `OpenChat/Core/Stage/DirectorPlan.swift`
- `OpenChat/Core/Stage/DirectorDiagnostics.swift`

新增 / 修改 test surface：

- `OpenChatTests/Core/StageTests/DirectorContractTests.swift`
- `OpenChatTests/Core/AgentCoreTests/AgentPolicyTests.swift`

Xcode project：

- 已运行 `ruby scripts/generate_xcodeproj.rb`，新增 Stage source/test 进入 target。
- `scripts/generate_xcodeproj.rb` 未修改。
- `PRODUCT_BUNDLE_IDENTIFIER = fukujusou.openchat.com`、`DEVELOPMENT_TEAM = GZAC7644XS`、`CODE_SIGN_STYLE = Automatic` 保持脚本既有值；test bundle id 仍为 `com.openchat.app.tests`。

未修改面：

- 未修改 `OpenChat/Core/Database/Migrations.swift`、`ConversationRecord.swift`、`MessageRecord.swift`。
- 未修改 `OpenChat/Features/Chat/Views/InputBarView.swift` 或 Chat UI。
- 未修改 `OpenChat/Features/Chat/ViewModels/ChatViewModel+Support.swift`。
- 未修改 `OpenChat/Core/PromptEngine/PromptAssembler.swift` 生产链路。
- 未修改 `OpenChat/Core/Background/*` 生产行为。
- 未修改 `OpenChat/Resources/Localizable.xcstrings`。

### 行为传播结论

新增 contract data flow：

```text
future chat/stage snapshot
  -> DirectorInput
  -> DirectorPlan
       -> stageInstructions
       -> speakerPlan hints
       -> diagnostics
  -> future Stage prompt/runtime
```

结论：

- `DirectorMode` 固化 `silent` / `agent` / `userControlled` raw value、Codable、CaseIterable contract。
- `StageInputRole.director` 是 input semantics，不是 `MessageRecord.role == "user"` 的普通角色台词映射。
- `StageInstruction` 默认 `hiddenFromCharacters`，空白 content 会抛出 typed `StageInstructionError.emptyContent`。
- `SpeakerTurn` 只是 Phase 6 hint，允许 participant / character id 为空，不表示 multi-character output 已实现。
- `DirectorPlan` 只包含 mode、stageInstructions、speakerPlan、diagnostics，不包含 assistant text、API messages 或 persistence operation。
- `StagePromptLayerPlan` 只表达 future prompt order，测试锁定 `directorInstructions` 位于 `currentBackground` 之后、`currentTurn` 之前；未接入 production request shape。
- `AgentPolicy.directorDefault(allowsLLM:)` 仍允许可选 `.llm`，但不开放 web search、network tools、database write 或 user-visible draft。

### 验证

Focused Director / AgentPolicy command：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/DirectorContractTests' '-only-testing:OpenChatTests/AgentPolicyTests'
```

结果：16 tests / 2 suites passed，`** TEST SUCCEEDED **`。xcresult：`/Users/fukujusou/Library/Developer/Xcode/DerivedData/OpenChat-fiicdnsnwoygvnahvbxvezbhtsfy/Logs/Test/Test-OpenChat-2026.05.19_09-16-00-+0800.xcresult`。

Prompt / Chat / Background regression command：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,id=F8D0D88B-71FD-471F-855A-B2B5D8267117' '-only-testing:OpenChatTests/PromptAssemblerTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests' '-only-testing:OpenChatTests/BackgroundManagerTests' '-only-testing:OpenChatTests/AgentPolicyTests'
```

结果：40 tests / 4 suites passed，`** TEST SUCCEEDED **`。默认 name-based `iPhone 17 Pro` regression attempt 先遇到 simulator Busy / preflight launch failure，未进入测试体；换用明确 UDID 后通过。

Full suite command：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,id=F8D0D88B-71FD-471F-855A-B2B5D8267117'
```

结果：372 tests / 67 suites passed，`** TEST SUCCEEDED **`。xcresult：`/Users/fukujusou/Library/Developer/Xcode/DerivedData/OpenChat-fiicdnsnwoygvnahvbxvezbhtsfy/Logs/Test/Test-OpenChat-2026.05.19_09-23-28-+0800.xcresult`。

Whitespace check：`git diff --check` 通过。

### 当时未完成边界

以下是 Director contract foundation closeout 当时的边界；其中 Stage runtime / DB / UI / prompt 接入已由下一节 `Stage Runtime Foundation 增量传播审计（2026-05-19）` 关闭，LLM Director agent、多 speaker parser、Responses Stage snapshot 和 XCUITest 已由 `Stage / Background Midstage Completion 增量传播审计（2026-05-20）` 关闭。

- Director executor/controller/runtime 未实现。
- Stage runtime、Stage DB schema、Stage persistence、Stage UI 未实现。
- 输入栏“作为用户 / 作为导演”切换未实现。
- Multi-character participant binding、speaker metadata、多 speaker output parser 未实现。
- DirectorPlan 未注入 `ChatViewModel.generateResponse(...)` 当前主链路。
- Director Instructions 未注入 production `PromptAssembler` request body。
- Responses API Stage request-shape guarantees 未实现。
- Exa / LibMan / web search 未接入。
- 普通角色仍不是 AgentCore agent，也没有 tool call 权限。

## Stage Runtime Foundation 增量传播审计（2026-05-19）

范围：Stage DB schema、Director deterministic runtime、Chat/Prompt 主链路接入、Stage Chat UI、speaker metadata、director input history isolation、Stage arch / harness 写回。

审计模式：窄范围增量审计。该轮把上一节未完成的 Stage runtime / DB / UI foundation 补齐；LLM Director agent、多 speaker parser、Responses API Stage snapshot、Stage -> Background filter、XCUITest 和独立 Stage 列表页由后续 `Stage / Background Midstage Completion 增量传播审计（2026-05-20）` 关闭。

### 静态传播面

新增 production surface：

- `OpenChat/Core/Database/DatabaseManager+Stage.swift`
- `OpenChat/Core/Database/Records/StageRecord.swift`
- `OpenChat/Core/Database/Records/StageParticipantRecord.swift`
- `OpenChat/Core/Database/Records/StageInstructionRecord.swift`
- `OpenChat/Core/Stage/StageModels.swift`
- `OpenChat/Core/Stage/DirectorController.swift`
- `OpenChat/Core/Stage/DirectorExecutor.swift`

修改 production surface：

- `OpenChat/Core/Database/Migrations.swift` 追加 `v18_create_stage_tables`。
- `OpenChat/Core/Database/Records/ConversationRecord.swift` 追加 stage relation。
- `OpenChat/Core/Database/Records/MessageRecord.swift` 追加 stage / speaker metadata。
- `OpenChat/Core/PromptEngine/PromptAssembler.swift` 追加 `stageTurnPlan` 兼容参数和 Stage system blocks。
- `OpenChat/Features/Chat/ViewModels/ChatViewModel.swift` 管理 Stage state、DirectorMode、participants 和 input role。
- `OpenChat/Features/Chat/ViewModels/ChatViewModel+Support.swift` 在 generateResponse 前执行 Director，并保存 speaker metadata。
- `OpenChat/Features/Chat/Views/InputBarView.swift` 显示 participant / director segmented picker。
- `OpenChat/Features/Chat/Views/ChatSettingsSheet.swift` 提供 Stage enable、DirectorMode、participants add/remove。
- `OpenChat/Features/Chat/Views/MessageBubbleView.swift` 优先显示 speakerName。
- `OpenChat/Resources/Localizable.xcstrings` 补齐新增 Stage UI key。

测试传播面：

- `OpenChatTests/Core/DatabaseTests/MigrationTests.swift`
- `OpenChatTests/Core/StageTests/DirectorContractTests.swift`
- `OpenChatTests/Features/ChatTests/ChatViewModelPromptAssemblyTests.swift`
- `OpenChatTests/Core/TestHelpers.swift`
- `OpenChatTests/Features/ChatTests/StreamingRenderSegmentationTests.swift`

### 行为传播结论

主链路：

```text
ChatViewModel.sendMessage
  -> participant input: generateResponse
       -> DatabaseManager.fetchStageContext
       -> DeterministicDirectorExecutor.execute
       -> DirectorController.planTurn
       -> BackgroundManager.prepare
       -> PromptAssembler.preview(stageTurnPlan:)
       -> ContextManager.prepareHistory
       -> PromptAssembler.assemble(stageTurnPlan:)
       -> APIClient.streamMessage
       -> MessageRecord(stageId/speakerKind/speakerId/speakerName)
  -> director input: saveDirectorInstruction
       -> stage_instruction
       -> no ordinary user message
       -> no API request
```

结论：

- Stage persistence 已通过 `stage` / `stage_participant` / `stage_instruction` 和 `message` speaker metadata 落地。
- Stage UI 当前内嵌于 Chat Settings，不是独立 Stage management surface。
- 多角色同场当前只决定一个 active speaker；不会让多个角色同轮连续输出。
- Director runtime 当前 deterministic，不调用 LLM，也不复用 AgentCore executor。
- `agent` DirectorMode 当前只是持久化 mode 值；行为仍走 deterministic controller。
- Director input 作为 stage instruction 写库，不作为普通 `message.role == user` 进入历史。
- Stage prompt 通过 `StageTurnPlan` 注入 `[Stage]`、`[Stage Participants]`、`[Director Instructions]`。
- Background request 尚未消费 Stage participant / instruction 作为 source filter；Background 仍沿用当前 Memory / WorldBook candidate 规则。

### 验证

Focused Stage / migration / chat command：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests' '-only-testing:OpenChatTests/DirectorContractTests' '-only-testing:OpenChatTests/MigrationTests'
```

结果：68 tests / 3 suites passed，`** TEST SUCCEEDED **`。xcresult：`/Users/fukujusou/Library/Developer/Xcode/DerivedData/OpenChat-fiicdnsnwoygvnahvbxvezbhtsfy/Logs/Test/Test-OpenChat-2026.05.19_20-41-58-+0800.xcresult`。

最终 full-suite、`git diff --check` 和 `Localizable.xcstrings` JSON parse 结果见 `harness/2026.05.19/stage-runtime-foundation/evidence.txt`。

### 未完成边界

以下是 2026-05-19 Stage runtime foundation closeout 当时的边界；其中 LLM Director agent、多 speaker parser、Responses Stage snapshot、Stage XCUITest、Stage -> Background filter 和独立 Stage 管理页已由 2026-05-20 后续增量关闭。

- LLM Director agent / AgentCore executor wiring 未实现。
- `agent` mode 未生成 LLM `DirectorPlan`。
- 多 speaker output parser、speaker block schema、parser diagnostics 和一轮多 assistant message 拆分未实现。
- Responses API Stage request-shape folding snapshot 未实现。
- Stage 创建/participant/director UI 尚无 XCUITest 自动化。
- Stage participant / director instruction 尚未传入 `BackgroundManager` source request。
- 角色仍不是 AgentCore agent，也没有 tool call 权限。

## Stage / Background Midstage Completion 增量传播审计（2026-05-20）

范围：Stage UI automation baseline、Responses API Stage snapshot、Stage -> Background filter、LLM Director agent、multi-speaker output parser、CharacterState / ConversationState Background sources、LibMan offline draft runtime、idle/background reflect draft worker、retrieval trace UI、独立 Stage management page。

审计模式：窄范围增量审计。该轮关闭上一节 Stage runtime foundation 的后续项，并补齐 Background / Memory 中期 source 与 diagnostics surface；仍不实现普通角色 tool call、Exa ToolBroker、统一 `[Background]` block、LibMan apply UI、自动 synthesis 写入、duplicate/conflict review 或完整 Stage CRUD editor。

### 静态传播面

新增 production surface：

- `OpenChat/App/UITestingSupport.swift`
- `OpenChat/Core/AgentCore/LLMAgentExecutor.swift`
- `OpenChat/Core/Background/CharacterStateBackgroundSource.swift`
- `OpenChat/Core/Background/ConversationStateBackgroundSource.swift`
- `OpenChat/Core/Background/LibrarianDraftTask.swift`
- `OpenChat/Core/Memory/MemoryReflectBackgroundWorker.swift`
- `OpenChat/Core/Stage/LLMDirectorTask.swift`
- `OpenChat/Core/Stage/StageSpeakerBlockParser.swift`
- `OpenChat/Features/Chat/Views/RetrievalTraceView.swift`
- `OpenChat/Features/Stage/StageManagementView.swift`
- `OpenChat/Features/Stage/StageManagementViewModel.swift`
- `OpenChatUITests/StageUITests.swift`

修改 production surface：

- `OpenChat/App/DependencyContainer.swift` 装配 CharacterState / ConversationState sources 与 idle reflect worker。
- `OpenChat/Core/AgentCore/AgentPolicy.swift` 追加 offline LibMan policy。
- `OpenChat/Core/Background/BackgroundSourceTool.swift` 扩展 source type、`StageBackgroundContext` 和 `BackgroundRequest.stageContext`。
- `OpenChat/Core/Background/MemoryBackgroundSource.swift` / `WorldBookBackgroundSource.swift` 用 Stage participants、active speaker 和 director instructions enrich query 并写入 metadata。
- `OpenChat/Core/Background/BackgroundAssembler.swift` / `BackgroundPolicy.swift` 支持 characterState / conversationState entries。
- `OpenChat/Core/Stage/DirectorExecutor.swift` 追加 `LLMDirectorExecutor`。
- `OpenChat/Core/Database/DatabaseManager+Stage.swift` 追加 Stage list item 查询。
- `OpenChat/Features/Chat/ViewModels/ChatViewModel+Support.swift` 在 `DirectorMode.agent` 下调用 LLM Director，构造 `StageBackgroundContext` 传入 BackgroundManager，并在 assistant 完整输出后执行 multi-speaker split。
- `OpenChat/Features/Chat/ViewModels/ChatViewModel.swift` 暴露 `backgroundDiagnostics`。
- `OpenChat/Features/Chat/Views/ChatView.swift` 在 detailed stats 下展示 `RetrievalTraceView`。
- `OpenChat/Features/Support/SidebarView.swift` 增加独立 Stage management sheet 入口。

测试传播面：

- `OpenChatTests/Core/BackgroundTests/BackgroundSourceTests.swift`
- `OpenChatTests/Core/BackgroundTests/LibrarianDraftTaskTests.swift`
- `OpenChatTests/Core/MemoryTests/MemoryReflectBackgroundWorkerTests.swift`
- `OpenChatTests/Core/PromptEngineTests/PromptAssemblerTests.swift`
- `OpenChatTests/Core/StageTests/LLMDirectorExecutorTests.swift`
- `OpenChatTests/Core/StageTests/StageSpeakerBlockParserTests.swift`
- `OpenChatTests/Core/NetworkingTests/ResponsesAPITests.swift`
- `OpenChatTests/Features/ChatTests/ChatViewModelPromptAssemblyTests.swift`
- `OpenChatTests/Features/StageTests/StageManagementViewModelTests.swift`
- `OpenChatUITests/StageUITests.swift`

### 行为传播结论

- Stage UI automation baseline 已有 `OpenChatUITests/StageUITests.swift`，配套 `UITestingSupport`、mock API、seed data 和 accessibility identifiers，覆盖 Stage 创建、DirectorMode、participant add/remove 和 director input 隔离。
- Responses API Stage snapshot 已覆盖 `[Stage]` / `[Director Instructions]` 在 Responses mode 下 folding 到 `instructions`，且不进入 user input。
- Stage -> Background filter 已把 active participants、active speaker 和 director instructions 传入 `BackgroundRequest.stageContext`；Memory / WorldBook source 使用 enriched query，Character / ConversationState source 产出 stage-aware candidates。
- `DirectorMode.agent` 已走 `LLMDirectorExecutor -> LLMAgentExecutor -> LLMDirectorTask`，LLM 输出非法时 fallback 到 deterministic plan；Director 不替角色写最终台词、不写数据库、不启用 tool。
- Multi-speaker parser 当前在 assistant 完整输出后解析 `[Speaker: ...]` / `Name:` / `<speaker name="">` blocks，并拆成多条 staged assistant messages；尚不是 streaming parser。
- LibMan 当前是 offline cited draft runtime：使用用户提供 source materials + LLM，产出用户可见草稿，不联网、不写 DB；Exa ToolBroker / apply UI 仍是后续范围。
- Idle/background reflect 当前是 draft-only worker，不自动 apply/write memory；duplicate/conflict 自动 review / merge / delete 仍是后续范围。
- Retrieval trace UI 当前只在 Chat detailed stats 下展示 Background diagnostics。
- Stage management page 当前是独立列表 / 打开 conversation 入口，不是完整 CRUD Stage editor。

### 验证

已通过的 focused 增量：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/BackgroundSourceTests' '-only-testing:OpenChatTests/BackgroundManagerTests' '-only-testing:OpenChatTests/PromptAssemblerTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests' '-only-testing:OpenChatTests/LLMDirectorExecutorTests' '-only-testing:OpenChatTests/StageSpeakerBlockParserTests' '-only-testing:OpenChatTests/ResponsesAPITests'
```

结果：54 tests / 6 suites passed，`** TEST SUCCEEDED **`。

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/LibrarianDraftTaskTests' '-only-testing:OpenChatTests/MemoryReflectBackgroundWorkerTests' '-only-testing:OpenChatTests/StageManagementViewModelTests' '-only-testing:OpenChatTests/AgentPolicyTests'
```

结果：13 tests / 4 suites passed，`** TEST SUCCEEDED **`。

最终验证：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/BackgroundSourceTests' '-only-testing:OpenChatTests/BackgroundManagerTests' '-only-testing:OpenChatTests/PromptAssemblerTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests' '-only-testing:OpenChatTests/LLMDirectorExecutorTests' '-only-testing:OpenChatTests/StageSpeakerBlockParserTests' '-only-testing:OpenChatTests/ResponsesAPITests' '-only-testing:OpenChatTests/LibrarianDraftTaskTests' '-only-testing:OpenChatTests/MemoryReflectBackgroundWorkerTests' '-only-testing:OpenChatTests/StageManagementViewModelTests' '-only-testing:OpenChatTests/AgentPolicyTests'
```

结果：67 tests / 10 suites passed，`** TEST SUCCEEDED **`。

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatUITests/StageUITests'
```

结果：1 UI test passed，`** TEST SUCCEEDED **`。

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

结果：Swift Testing 397 tests / 72 suites passed；`OpenChatUITests/StageUITests` 1 XCTest passed；`** TEST SUCCEEDED **`。xcresult：`/Users/fukujusou/Library/Developer/Xcode/DerivedData/OpenChat-fiicdnsnwoygvnahvbxvezbhtsfy/Logs/Test/Test-OpenChat-2026.05.20_12-23-59-+0800.xcresult`。

Other checks：

- `git diff --check` passed。
- `python3 -m json.tool OpenChat/Resources/Localizable.xcstrings` passed。

### 当前未完成边界

- 统一 `[Background]` block 未默认启用。
- Exa ToolBroker / ToolExecutor、LibMan web search、UI preview/apply 和 confirmed persistent write 未实现。
- Idle reflect 不自动 apply/write；duplicate/conflict review、自动合并 / 删除 / 覆盖策略未实现。
- Multi-speaker parser 非流式，parser diagnostics / schema repair 仍是基础版。
- Stage management page 不是完整 CRUD editor。
- 普通角色仍不是 AgentCore agent，也没有 tool call 权限。
