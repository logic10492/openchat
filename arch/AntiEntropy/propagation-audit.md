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

`PromptAssembler.preview` 计算固定段与预算 -> `ContextManager.prepareHistory` 按策略处理历史 -> `PromptAssembler.assemble` 输出最终 `[ChatMessage]`。

关键证据：

- 两阶段调用由 `ChatViewModel+Support` 串联：`OpenChat/Features/Chat/ViewModels/ChatViewModel+Support.swift:81`、`OpenChat/Features/Chat/ViewModels/ChatViewModel+Support.swift:92`、`OpenChat/Features/Chat/ViewModels/ChatViewModel+Support.swift:98`
- `PromptAssembler.preview` 使用 40% 总预算：`OpenChat/Core/PromptEngine/PromptAssembler.swift:14`
- `TokenBudget` 分配 example/worldBook/memory/history：`OpenChat/Core/PromptEngine/TokenBudget.swift:18`
- `CompressionStrategy` 失败后由 `ContextManager` fallback 到 truncation：`OpenChat/Core/ContextManager/ContextManager.swift:26`

结论：主链路可运行且有测试覆盖；Task 5 已把 Prompt 时间格式与段顺序回写到 arch，并保留 Chat 当前输入去重修复证据。

- arch 多处声明时间上下文为 `[Time] ISO 8601 含时区 [/Time]`，源码 `PromptAssembler.makeTimeContext()` 当前输出 `[Time] <ISO8601> [/Time]`。
- arch 声明 before_history 世界书条目在记忆前，源码当前顺序为 `before_history -> memory -> exampleDialogs`。

> 修复写回：`docs/superpowers/plans/2026-04-27-triangle-consistency-repair.md` Task 1 已通过 Feature 级测试和 `promptHistoryMessages` 过滤修复当前输入重复注入风险。

### Memory 链路

链路：

`ChatViewModel` 检索记忆 -> `MemoryManager.retrieveMemories` -> `EmbeddingService`/`VectorStore`/`DatabaseManager` -> `PromptAssembler` 注入记忆；生成完成后周期性触发 `MemoryManager.extractMemories`。

关键证据：

- 发送时检索记忆：`OpenChat/Features/Chat/ViewModels/ChatViewModel+Support.swift:72`
- 周期性触发提取：`OpenChat/Features/Chat/ViewModels/ChatViewModel+Support.swift:195`
- `MemoryManager.extractMemories` 使用增量消息和 API 提取：`OpenChat/Core/Memory/MemoryManager.swift:39`
- 向量保存失败只记录 warning，不回滚 memory entry：`OpenChat/Core/Memory/MemoryManager.swift:75`

结论：源码已具备 Memory 主链路；Task 5 已回写命名/触发时机现实：

- `arch/modules/memory/index.md` 的文件清单已写回 `Features/CharacterCard/Views/MemoryListView.swift` 和 `Features/CharacterCard/ViewModels/MemoryListViewModel.swift`。
- 设计文档已说明当前源码是每 10 条 user/assistant 消息周期性触发；`ChatView.onDisappear` 也会触发，因此离开当前聊天视图或切换对话可通过视图消失间接触发。App 进入后台 lifecycle hook 仍属于后续 UX/生命周期增强项。

### Database migration 链路

关键证据：

- 迁移集中在 `OpenChat/Core/Database/Migrations.swift`，当前从 `v1_initial` 到 `v9_add_is_title_generated`。
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
