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

结果：成功。Swift Testing 报告 `187 tests in 41 suites passed`，`xcodebuild` 结尾为 `** TEST SUCCEEDED **`。

本次审计还统计到 `OpenChatTests/` 当前有 20+ 个 Swift 测试文件，full suite 为 187 个 Swift Testing 测试。API/Responses/reasoning 相关新增测试已纳入基线；2026-04-30 Memory embedding/vector/retrieval 可靠性测试也已纳入当前基线。

## 总体结论

| 边 | 当前结论 | 说明 |
|---|---|---|
| `src-test` | 通过但不完整 | 全量自动化测试通过；Chat 发送链路当前输入重复风险已有 Feature 级测试覆盖，但仍缺少 UI 自动化测试。 |
| `arch-src` | 局部不一致 | Prompt 时间格式、Memory 目录/触发时机、migration 约束已按当前源码回写；Feature 分层说明仍有漂移，留待 Task 6。 |
| `arch-test` | 基本一致 | 测试数量已回写为 187；Prompt 顺序/时间、migration 源码约束、Chat 当前输入去重、Memory embedding/vector/retrieval 可靠性已补测试，Feature/UI 分层契约仍需后续补强。 |

## 模块矩阵

| 模块 | `arch-src` | `arch-test` | `src-test` |
|---|---|---|---|
| API Client / Networking | 基本一致 | 基本一致 | 通过。当前覆盖 Chat Completions、Responses、reasoning、baseURL 不强拼 `/v1`、model list。 |
| PromptEngine | 基本一致 | 基本一致 | 函数级测试覆盖 ISO8601 时间、before_history -> memory -> exampleDialogs 顺序；Chat 发送链路去重由 Feature 级测试覆盖。 |
| ContextManager | 一致 | 一致 | Truncation、CompressionPolicy、source hash、PreparedHistory、CompressionSummarizer、CheckpointCompactor、checkpoint reuse 与 fallback 均有测试覆盖；Prompt 端到端仍通过 Chat 发送链路测试间接覆盖。 |
| Memory | 一致 | 基本一致 | `EmbeddingServiceTests`、`VectorStoreTests`、`MemoryManagerRetrievalTests`、`ChatViewModelPromptAssemblyTests` 覆盖 bundle 资源、CoreML embedding、sqlite-vec KNN、批量原子写入、fallback 注入；周期阈值 / `ChatView.onDisappear` 自动触发路径仍需端到端测试；full suite 为 187 tests / 41 suites。 |
| Database / Data Model | 基本一致 | 基本一致 | migration/record 测试通过；MigrationTests 保护 migration 源码不引用 runtime Record/enum 符号。 |
| Features / UI | 部分不一致 | 不完整 | 缺少 Feature/ViewModel/UI 路径测试，当前主要靠编译和 Core 测试间接保护。 |
| Settings / Endpoint Model | 部分不一致 | 基本一致 | Endpoint model、API mode、fetch models 测试通过；全局测试基线已更新为 187 tests，Settings UI/manual 覆盖仍需后续验收。 |

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

### 3. Prompt 中 Memory 与 before_history 世界书顺序漂移

结论：Task 3 已统一为 before_history 世界书在记忆前，并补测试锁定相对顺序。

证据：

- `arch/modules/prompt-assembly.md` 的顺序图把世界书 `position=before_history` 放在跨对话记忆之前。
- 源码 `PromptAssembler.preview` 先追加 trimmedBeforeHistoryEntries，再追加 trimmedMemories，最后追加 exampleDialogs。
- `PromptAssemblerTests` 覆盖 `before_history -> memory -> exampleDialogs` 相对顺序。

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
- 当前源码在消息生成完成后按 `messagesSinceLastExtraction >= ChatViewModel.extractionInterval` 周期性触发，`extractionInterval == 10`。
- `ChatView.onDisappear` 当前会调用 `triggerMemoryExtraction()`，因此离开当前聊天视图或切换对话可通过视图消失间接触发；App 进入后台 lifecycle hook 仍属于后续 UX/生命周期增强项。

新增可靠性证据：

- `OpenChat/Resources/Models/MultilingualE5Small.mlpackage` 与 `OpenChat/Resources/Models/tokenizer.json` 由 `scripts/generate_xcodeproj.rb` 加入 App Bundle。
- `EmbeddingService` 使用固定 `1 x 256` CoreML 输入，读取 Float16 / Float32 `embeddings`，输出 384 维归一化向量。
- `VectorStore` 在同一 GRDB transaction 中保存 `memory_entry + memory_embedding`；`insert(entries:)` 为协议必填方法，避免非原子默认实现。
- `MemoryManager.retrieveMemories(...)` 在 embedding/model/vector 异常时 fallback 到近期记忆；`ChatViewModel+Support` 不再用 `try?` 静默吞掉全部记忆。

测试现状：

- `DatabaseManagerMemoryTests`、`MemoryExtractionParsingTests`、`PromptAssemblerTests` 覆盖 DB、JSON 容错、Prompt 注入。
- `EmbeddingServiceTests` 覆盖模型/tokenizer bundle、tokenizer 输出、CoreML 384 维归一化向量。
- `VectorStoreTests` 覆盖 sqlite-vec KNN、角色隔离、删除同步、维度校验、单条和批量事务回滚。
- `MemoryManagerRetrievalTests` 覆盖语义检索失败 fallback、提取向量失败不产生半索引记忆、批次失败整批回滚。
- `ChatViewModelPromptAssemblyTests` 覆盖 fallback 记忆最终注入 API request。
- 周期阈值与 `ChatView.onDisappear` 自动触发路径属于当前源码现实，但尚未由端到端测试锁定；该缺口已保留在 `arch/roadmap.md` Phase 6 验证标准中。

三边判断：

- `arch-src`：一致。
- `arch-test`：Memory vector reliability 一致；自动触发路径端到端测试待补。
- `src-test`：focused memory/prompt suite 27 tests 通过；full suite 为 187 tests / 41 suites。

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

结论：2026-04-30 已把基线回写为 187 tests；API-client 对齐测试和 Memory embedding/vector/retrieval 可靠性测试均纳入当前基线。

证据：

- `arch/index.md` 已回写为“187 个 Swift Testing 测试全部通过”。
- `arch/roadmap.md` 已回写为“当前通过的 Swift Testing 测试（187 个）”。
- `arch/modules/memory/index.md` 已回写 Memory embedding/vector/retrieval 可靠性覆盖与 187-test full suite 结果。
- `arch/modules/settings/api-endpoint.md` 不再作为本轮测试数量来源；全局基线以本文件和 `arch/index.md` 为准。
- `arch/modules/api-client.md` 不在 Task 5 允许编辑范围内，本次不修改。

三边判断：

- `arch-test`：Task 5 允许范围内已一致；`arch/modules/api-client.md` 属于本次前置未提交改动，另行保持最小同步。
- `src-test`：通过。
- `arch-src`：不直接涉及源码。

## 当前可信结论

1. 当前工作区能编译并通过全量 Swift Testing：187 tests passed。
2. API Client / Responses / reasoning / baseURL 行为在当前工作区内有较强测试支撑。
3. Prompt/Context/Memory 的 Core 函数级测试可用，Chat 真实发送链路已有当前输入去重与 checkpoint invalidation 测试；仍缺少 UI 自动化覆盖。
4. arch 已回写 Prompt 时间格式、记忆顺序、Memory 位置与 embedding/vector/retrieval 可靠性、migration 约束、checkpoint compression 语义和 187-test 基线；Feature 边界漂移留待后续分层修复计划。

## 修复顺序状态

| 顺序 | 项目 | 当前状态 |
|---:|---|---|
| 1 | 补 Chat 拼装链路测试，锁定“当前输入只出现一次” | Closed：`ChatViewModelPromptAssemblyTests` 覆盖 request messages 与 DB 存储。 |
| 2 | Prompt 时间格式统一为 ISO8601 | Closed：源码输出 `[Time] <ISO8601> [/Time]`，测试解析验证。 |
| 3 | 明确 Memory 与 before_history 世界书顺序 | Closed：统一为 `before_history -> memory -> exampleDialogs`，PromptAssemblerTests 覆盖。 |
| 4 | 回写 Memory 目录和触发时机现实 | Closed：文档写回周期性触发、onDisappear 触发、增量提取与 15% memory budget。 |
| 5 | 清理测试数量和验证命令说明 | Closed：全局状态统一为 187 tests 基线。 |
| 6 | 分层修复或 App shell 例外归档 | Open：已拆出 `arch/AntiEntropy/layering-repair-plan.md`。 |

## 修复写回（2026-04-27）

- `src-test`：新增 Chat 发送链路测试，锁定当前输入只进入 request messages 一次。
- `arch-src`：Prompt 时间上下文统一为 `[Time] <ISO8601> [/Time]`；Prompt 段顺序统一为 `before_history -> memory -> exampleDialogs`；migration 源码不再引用 runtime Record/enum 符号。
- `arch-test`：PromptAssemblerTests 覆盖 ISO8601 和 memory/world-book 相对顺序；MigrationTests 覆盖 migration 源码约束；EmbeddingServiceTests / VectorStoreTests / MemoryManagerRetrievalTests / ChatViewModelPromptAssemblyTests 覆盖 Memory 可靠性；全量基线更新为 187 tests。
- 分层漂移：Task 6 将单独处理，不在本次 prompt/db/doc 修复中混入跨层搬迁。

## Checkpoint Compression 三边一致性写回（2026-04-30）

范围：`OpenChat/Core/Database/*Compression*`、`OpenChat/Core/ContextManager/*Compression*`、`OpenChat/Core/ContextManager/CheckpointCompactor.swift`、`OpenChat/Features/Chat/ViewModels/ChatViewModel.swift`、`OpenChatTests/Core/ContextManagerTests/*`、`OpenChatTests/Core/DatabaseTests/CompressionCheckpointDatabaseTests.swift`、`OpenChatTests/Features/ChatTests/ChatViewModelPromptAssemblyTests.swift`、`arch/modules/context-manager.md`、`arch/data-model.md`。

### arch-src

- `arch/data-model.md` 已新增 `conversation_compression_checkpoint` 表，字段与 `CompressionCheckpointRecord`、`v11_create_compression_checkpoints` 一致。
- `arch/modules/context-manager.md` 已从“每轮临时摘要”改为 checkpoint compression：复用有效 checkpoint，超过 `CompressionPolicy.autoCompactTokenLimit` 才压缩，成功后保存，失败 fallback truncation。
- `.github/instructions/context-manager.instructions.md` 已同步 `gpt-5.5` effective compact window、90% 阈值、checkpoint invalidation 和不写半成品规则。

### arch-test

- `MigrationTests` 覆盖 v11 表存在、列集合、conversation delete cascade。
- `CompressionCheckpointDatabaseTests` 覆盖 latest checkpoint 查询和受影响 checkpoint 删除。
- `CompressionPolicyTests` 覆盖 `gpt-5.5` 258k effective window、OpenChat 40% cap、大上下文非 GPT-5.5 阈值。
- `CompressionSourceHasherTests`、`PreparedHistoryTests`、`CompressionSummarizerTests` 覆盖 source hash、旧 PromptAssembler 兼容出口和 checkpoint summarizer request。
- `CheckpointCompactorTests` 与 `CompressionCheckpointReuseTests` 覆盖低于阈值不调用网络、超过阈值保存 checkpoint、复用 checkpoint、压缩失败 fallback 且不保存 checkpoint。
- `ChatViewModelPromptAssemblyTests` 覆盖编辑/删除消息时删除受影响 checkpoint。

### src-test

- Focused context/database/chat checkpoint suite 已通过：
  `xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:OpenChatTests/CheckpointCompactorTests -only-testing:OpenChatTests/CompressionCheckpointReuseTests -only-testing:OpenChatTests/CompressionStrategyTests`
- Chat prompt suite 已通过：`xcodebuild test ... -only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests`，7 tests passed。
- Full suite 当前基线：187 tests / 41 suites，`** TEST SUCCEEDED **`。
