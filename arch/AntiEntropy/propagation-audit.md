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
- 检索链路从 Chat 层 `try?` 静默吞错，改为 `MemoryManager.retrieveMemories` 内部 fallback 到近期记忆；Chat 层只记录 fallback 仍失败的 warning。
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
- `src-test`：focused suites 与 full suite 均通过，当前基线为 197 tests / 41 suites。

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
- `src-test`：focused compression mode suite 39 tests / 4 suites passed；当前 full suite 197 tests / 41 suites passed，`** TEST SUCCEEDED **`。

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
