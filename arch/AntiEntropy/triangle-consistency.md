# Triangle-Consistency

> 审计日期：2026-04-27
> 三边：`arch-test`、`arch-src`、`src-test`

## 校验方法

- `arch-src`：核对 `arch/**` 对模块职责、接口、顺序、数据模型、迁移原则的描述是否符合 `OpenChat/**` 当前源码。
- `arch-test`：核对 arch 中声明的验证标准、测试数量、测试文件和行为契约是否被 `OpenChatTests/**` 覆盖。
- `src-test`：运行当前测试，并检查测试是否覆盖关键源码行为。

## 已执行验证

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17'
```

结果：成功。当前审计工作区 Swift Testing 报告 `133 tests in 28 suites passed`，`xcodebuild` 结尾为 `** TEST SUCCEEDED **`。

本次审计还统计到 `OpenChatTests/` 当前有 20 个 Swift 测试文件、133 个 `@Test`。其中 API/Responses/reasoning 相关新增测试来自审计开始前已有未提交改动；本报告记录的是当前工作区现实，不把这些 dirty tests 归入本轮提交。

## 总体结论

| 边 | 当前结论 | 说明 |
|---|---|---|
| `src-test` | 通过但不完整 | 全量自动化测试通过；Chat 发送链路当前输入重复风险已有 Feature 级测试覆盖，但仍缺少 UI 自动化测试。 |
| `arch-src` | 局部不一致 | Prompt 时间格式、Memory 目录/触发时机、migration 约束已按当前源码回写；Feature 分层说明仍有漂移，留待 Task 6。 |
| `arch-test` | 局部不一致 | 测试数量已回写为 133；Prompt 顺序/时间、migration 源码约束、Chat 当前输入去重已补测试，Feature/UI 分层契约仍需后续补强。 |

## 模块矩阵

| 模块 | `arch-src` | `arch-test` | `src-test` |
|---|---|---|---|
| API Client / Networking | 基本一致 | 基本一致 | 通过。当前覆盖 Chat Completions、Responses、reasoning、baseURL 不强拼 `/v1`、model list。 |
| PromptEngine | 基本一致 | 基本一致 | 函数级测试覆盖 ISO8601 时间、before_history -> memory -> exampleDialogs 顺序；Chat 发送链路去重由 Feature 级测试覆盖。 |
| ContextManager | 基本一致 | 部分不一致 | Truncation/Compression 测试通过，但 arch 的 40%链路依赖 Prompt 端到端仍需覆盖。 |
| Memory | 基本一致 | 部分不一致 | DB/解析/Prompt 注入测试通过；EmbeddingService/VectorStore 直接覆盖不足。 |
| Database / Data Model | 基本一致 | 基本一致 | migration/record 测试通过；MigrationTests 保护 migration 源码不引用 runtime Record/enum 符号。 |
| Features / UI | 部分不一致 | 不完整 | 缺少 Feature/ViewModel/UI 路径测试，当前主要靠编译和 Core 测试间接保护。 |
| Settings / Endpoint Model | 部分不一致 | 基本一致 | Endpoint model、API mode、fetch models 测试通过；`arch/modules/settings/api-endpoint.md` 已回写当前审计工作区 133-test 基线，Settings UI/manual 覆盖仍需后续验收。 |

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

### 5. Memory 文档位置和触发时机漂移

结论：Task 5 已回写 Memory 位置和周期性提取触发的当前源码现实。

证据：

- `arch/modules/memory/index.md` 文件清单已写回 `Features/CharacterCard/Views/MemoryListView.swift` 和 `Features/CharacterCard/ViewModels/MemoryListViewModel.swift`。
- 当前源码在消息生成完成后按 `messagesSinceLastExtraction >= ChatViewModel.extractionInterval` 周期性触发，`extractionInterval == 10`。
- `ChatView.onDisappear` 当前会调用 `triggerMemoryExtraction()`，因此离开当前聊天视图或切换对话可通过视图消失间接触发；App 进入后台 lifecycle hook 仍属于后续 UX/生命周期增强项。

测试现状：

- `DatabaseManagerMemoryTests`、`MemoryExtractionParsingTests`、`PromptAssemblerTests` 覆盖 DB、JSON 容错、Prompt 注入。
- 未看到直接覆盖 CoreML embedding 加载、sqlite-vec KNN 行为、App 进入后台 lifecycle 触发记忆提取的测试。

三边判断：

- `arch-src`：一致。
- `arch-test`：覆盖不完整。
- `src-test`：通过。

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

结论：Task 5 已把当前审计工作区基线回写为 133 tests，并标注该基线包含审计开始前已有未提交 networking 测试改动。

证据：

- `arch/index.md` 已回写为“当前审计工作区 133 个 Swift Testing 测试全部通过”。
- `arch/roadmap.md` 已回写为“当前审计工作区通过的 Swift Testing 测试（133 个）”。
- `arch/modules/memory/index.md` 已回写为当前审计工作区 133 tests，并保留 Memory 直接覆盖不足说明。
- `arch/modules/settings/api-endpoint.md` 已回写为当前审计工作区 133 tests。
- `arch/modules/api-client.md` 不在 Task 5 允许编辑范围内，本次不修改。

三边判断：

- `arch-test`：Task 5 允许范围内已一致；`arch/modules/api-client.md` 属于本次前置未提交改动，另行保持最小同步。
- `src-test`：通过。
- `arch-src`：不直接涉及源码。

## 当前可信结论

1. 当前审计工作区能编译并通过全量 Swift Testing：133 tests passed；该计数包含审计开始前已有未提交 networking 测试改动。
2. API Client / Responses / reasoning / baseURL 行为在当前工作区内有较强测试支撑。
3. Prompt/Context/Memory 的 Core 函数级测试可用，Chat 真实发送链路已有当前输入去重测试；仍缺少 UI 自动化覆盖。
4. arch 已回写 Prompt 时间格式、记忆顺序、Memory 位置、migration 约束和当前审计工作区 133-test 基线；Feature 边界漂移留待 Task 6。

## 修复顺序状态

| 顺序 | 项目 | 当前状态 |
|---:|---|---|
| 1 | 补 Chat 拼装链路测试，锁定“当前输入只出现一次” | Closed：`ChatViewModelPromptAssemblyTests` 覆盖 request messages 与 DB 存储。 |
| 2 | Prompt 时间格式统一为 ISO8601 | Closed：源码输出 `[Time] <ISO8601> [/Time]`，测试解析验证。 |
| 3 | 明确 Memory 与 before_history 世界书顺序 | Closed：统一为 `before_history -> memory -> exampleDialogs`，PromptAssemblerTests 覆盖。 |
| 4 | 回写 Memory 目录和触发时机现实 | Closed：文档写回周期性触发、onDisappear 触发、增量提取与 15% memory budget。 |
| 5 | 清理测试数量和验证命令说明 | Closed：全局状态统一为当前审计工作区 133 tests 基线，并标注 dirty-worktree 来源。 |
| 6 | 分层修复或 App shell 例外归档 | Open：已拆出 `arch/AntiEntropy/layering-repair-plan.md`。 |

## 修复写回（2026-04-27）

- `src-test`：新增 Chat 发送链路测试，锁定当前输入只进入 request messages 一次。
- `arch-src`：Prompt 时间上下文统一为 `[Time] <ISO8601> [/Time]`；Prompt 段顺序统一为 `before_history -> memory -> exampleDialogs`；migration 源码不再引用 runtime Record/enum 符号。
- `arch-test`：PromptAssemblerTests 覆盖 ISO8601 和 memory/world-book 相对顺序；MigrationTests 覆盖 migration 源码约束；全量基线更新为当前审计工作区 133 tests。
- 分层漂移：Task 6 将单独处理，不在本次 prompt/db/doc 修复中混入跨层搬迁。
