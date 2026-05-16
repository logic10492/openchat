# AgentCore Foundation Closeout

> 日期：2026-05-17
> 范围：`docs/superpowers/plans/2026-05-17-agent-core-foundation/`
> 结论：AgentCore foundation 已完成；BackgroundWorker / Director / LibMan runtime 未实现。

## 1. 完成内容

本轮按计划只落地 zero-runtime-consumer 的 Core contract 和 focused tests：

- `OpenChat/Core/AgentCore/AgentDescriptor.swift`
- `OpenChat/Core/AgentCore/AgentCapability.swift`
- `OpenChat/Core/AgentCore/AgentPolicy.swift`
- `OpenChat/Core/AgentCore/ToolUsePolicy.swift`
- `OpenChat/Core/AgentCore/SideEffectPolicy.swift`
- `OpenChat/Core/AgentCore/AgentTask.swift`
- `OpenChat/Core/AgentCore/AgentExecutionContext.swift`
- `OpenChat/Core/AgentCore/AgentExecutionResult.swift`
- `OpenChat/Core/AgentCore/AgentDiagnostics.swift`
- `OpenChat/Core/AgentCore/SchemaValidation.swift`
- `OpenChat/Core/AgentCore/AgentExecutor.swift`
- `OpenChat/Core/AgentCore/DeterministicAgentExecutor.swift`
- `OpenChat/Core/AgentCore/AgentError.swift`

新增 focused tests：

- `OpenChatTests/Core/AgentCoreTests/AgentDescriptorTests.swift`
- `OpenChatTests/Core/AgentCoreTests/AgentPolicyTests.swift`
- `OpenChatTests/Core/AgentCoreTests/DeterministicAgentExecutorTests.swift`
- `OpenChatTests/Core/AgentCoreTests/AgentDiagnosticsTests.swift`

`ruby scripts/generate_xcodeproj.rb` 已运行，使新增 Swift source/test 进入 target。签名关键值保持脚本配置：

- app bundle id：`fukujusou.openchat.com`
- development team：`GZAC7644XS`
- code sign style：`Automatic`
- test bundle id：`com.openchat.app.tests`

## 2. Policy / Executor 证据

`AgentPolicy` 已提供三类首批 consumer profile：

- `backgroundWorkerDefault()`：只允许 `.deterministic` / `.internalDiagnostics`，不含 `.llm`、`.webSearch`、`.databaseWrite`。
- `directorDefault(allowsLLM:)`：可选 `.llm`，不允许 `.webSearch` / `.databaseWrite`。
- `librarianDraftDefault()`：允许 `.llm` / `.webSearch` / `.userVisibleDraft`，tool policy 限定 `exa`，draft apply 和 persistent write 均要求 confirmation。

`DeterministicAgentExecutor` 执行前校验：

- `policy.allowedCapabilities` 必须是 `.deterministic` / `.internalDiagnostics` 子集。
- `toolUsePolicy.allowNetwork == false`。
- `sideEffectPolicy.allowDatabaseWrite == false`。
- 越权时抛出 typed `AgentError: LocalizedError, Sendable, Equatable`。

`AgentDiagnostics` 当前只随 `AgentExecutionResult` 内存返回；它记录 task name、agent、policy、started/ended、input summary、selected/omitted ids、fallback、tool usage、token usage、schema validation 和 diagnostic errors，不写 DB，不进入 prompt。

## 3. 传播审计

审计模式：AgentCore foundation narrow propagation audit。

实际传播面：

- 新增 `OpenChat/Core/AgentCore/*`。
- 新增 `OpenChatTests/Core/AgentCoreTests/*`。
- 运行 generator 更新 `OpenChat.xcodeproj/project.pbxproj` 和 `OpenChat.xcodeproj/xcshareddata/xcschemes/OpenChat.xcscheme` 的 target UUID references。
- 同步 docs / harness / AntiEntropy。

未传播到：

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

行为结论：AgentCore 仍是零运行时 consumer 的 Core contract，没有接入 Chat 主链路。当前主聊天路径仍是 `ChatViewModel.generateResponse -> MemoryManager / WorldBookSource -> PromptAssembler -> ContextManager -> APIClient.streamMessage`。

## 4. 三边一致性

| 边 | 结果 | 证据 |
|---|---|---|
| `arch-src` | 一致 | `arch/modules/agent-core.md` 已从目标架构更新为 AgentCore foundation 已落地，并保留 BackgroundWorker / Director / LibMan runtime 未实现边界。 |
| `arch-test` | 一致 | `arch/modules/agent-core.md`、`06_testing_acceptance.md` 和本 harness 记录 AgentCore focused、主链路 focused、full suite closeout。 |
| `src-test` | 一致 | AgentCore focused 12 tests / 4 suites、主链路 focused 50 tests / 4 suites、full suite 303 tests / 58 suites 均通过。 |

## 5. 计划对比 / 实现漂移

符合计划：

- 只新增 `Core/AgentCore` 和 `OpenChatTests/Core/AgentCoreTests`。
- 未新增 database migration。
- 未修改 Chat / Prompt / Memory / WorldBook / Database / Networking / UI runtime。
- 未实现 BackgroundWorker、BackgroundPacket、Director runtime、LibMan runtime 或 Exa broker。
- `AgentPolicy` profile 和 deterministic executor denial 均有 tests 锁定。

已记录的轻微漂移：

- 计划书只列出允许生成 `OpenChat.xcodeproj/project.pbxproj`；实际 `scripts/generate_xcodeproj.rb` 同时重写了 `OpenChat.xcodeproj/xcshareddata/xcschemes/OpenChat.xcscheme` 中的 target `BlueprintIdentifier`。这是 generator 重建 target UUID 后的 scheme 引用同步，不是签名或行为漂移；full suite 已通过。

修正过的实现细节：

- `ToolUsePolicy.allowedToolNames` 调整为 `Set<String>`，与计划书 contract 一致。
- `SideEffectPolicy` 调整为 `allowDatabaseRead` / `allowDatabaseWrite` / `requiresUserConfirmationForWrite`，与计划书 contract 一致。

## 6. 验证记录

Simulator：

```bash
xcrun simctl list devices available | rg 'iPhone'
```

实际使用：`iPhone 17 Pro`。

主链路 focused baseline / regression：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/PromptAssemblerTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests' '-only-testing:OpenChatTests/MemoryManagerRetrievalTests' '-only-testing:OpenChatTests/WorldBookSourceTests'
```

结果：50 tests / 4 suites passed，`** TEST SUCCEEDED **`。

AgentCore focused：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/AgentDescriptorTests' '-only-testing:OpenChatTests/AgentPolicyTests' '-only-testing:OpenChatTests/DeterministicAgentExecutorTests' '-only-testing:OpenChatTests/AgentDiagnosticsTests'
```

结果：12 tests / 4 suites passed，`** TEST SUCCEEDED **`。

Full suite：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

结果：303 tests / 58 suites passed，`** TEST SUCCEEDED **`。

## 7. 后续边界

下一计划包才允许新增：

- `OpenChat/Core/Background/*`
- `BackgroundWorker`
- `BackgroundPacket`
- `MemoryBackgroundSource`
- `WorldBookBackgroundSource`

届时需要重新审计 DI、Chat、Prompt、Memory、WorldBook 的行为传播。本轮不得被解读为已切换主聊天链路。
