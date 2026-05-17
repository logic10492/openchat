# 08. Phase 6C - Chat Switch

## 目标

把主聊天链路从 direct Memory / WorldBook 注入切换为 `BackgroundManager.prepare(...) -> BackgroundPacket -> PromptAssembler`。

允许修改：

- `OpenChat/App/DependencyContainer.swift`
- `OpenChat/Features/Chat/ViewModels/ChatViewModel+Support.swift`
- `OpenChat/Core/PromptEngine/PromptAssembler.swift` 的 packet overload 使用面
- matching tests

## 目标链路

```text
ChatViewModel.generateResponse
  -> resolve endpoint
  -> persist current user message if needed
  -> fetch character / worldBook / entries / current messages
  -> memory extraction boundary remains explicit
  -> makePromptHistoryMessages(...)
  -> BackgroundManager.prepare(request, policy)
  -> PromptAssembler.preview/assemble(backgroundPacket:)
  -> ContextManager.prepareHistory(...)
  -> APIClient.streamMessage(...)
```

## 本修订的默认切换策略

Phase 6C 开始前必须确认：

- Phase 5 closeout focused tests 已通过或有明确 NOT RUN / blocked 记录。
- 6A `BackgroundManagerTests` 已覆盖 source merge / fallback / diagnostics。
- 6B `PromptAssemblerTests` 已覆盖 packet-compatible `[Memories]` / `[World Book Entries]` 输出。

第一版 Chat switch 采用 conservative route：

- bounded worldBook rebuild **继续保留在 ChatViewModel**，执行位置仍在 worldBook source recall / manager prepare 前。
- `BackgroundManager.prepare(...)` 接收 Chat 构造的 `BackgroundRequest` 和 `BackgroundPolicy.compatibilityDefault(...)`。
- `BackgroundPolicy.tokenBudget` 是 worker candidate selection ceiling；PromptAssembler 仍做最终 prompt budget trim。
- direct final prompt 注入权从 Memory / WorldBook arrays 转移到 `BackgroundPacket`。
- 旧 direct PromptAssembler overload 暂时保留，作为 regression / rollback 对照。

## 依赖注入

`DependencyContainer` 负责装配：

- `MemoryRecallTool`
- `WorldBookRecallTool`
- `MemoryBackgroundSource`
- `WorldBookBackgroundSource`
- `BackgroundWorker`
- `BackgroundManager`

ViewModel 继续通过 init 接收依赖，不在 View 中创建服务。

如果 `ChatViewModel` initializer 需要新增 `backgroundManager`，必须更新所有 tests / preview factories。

当前已知调用点必须纳入 6C diff review：

- `OpenChat/ContentView.swift` 中的 `ChatDetailContainer`。
- `OpenChat/Features/Chat/Views/ChatView.swift` preview。
- `OpenChatTests/Features/ChatTests/ChatViewModelPromptAssemblyTests.swift` 内所有 `ChatViewModel(...)` 构造。

## Memory extraction 边界

当前 pre-response memory extraction 可以保留在 ChatViewModel 中；它不是 BackgroundWorker 行为。

要求：

- extraction failure 仍不阻断 generation，除非现有行为本来阻断。
- extraction 后 refresh conversation 的逻辑保持。
- `BackgroundManager` 只召回/选择背景，不执行 memory retain / extract。

## WorldBook rebuild 边界

两种可接受路线：

1. 保留在 ChatViewModel：先执行 bounded rebuild，再调用 manager。
2. 迁移到 Manager pre-source stage：Chat 不再直接 rebuild，manager tests 证明 ordering。

本修订默认选择路线 1。路线 2 不是 Phase 6C 默认完成条件，除非用户单独确认。

不可接受路线：

- 放进 `BackgroundWorker`。
- 放进 `WorldBookBackgroundSource`。
- 无测试地删除 rebuild。
- 让 rebuild failure 被无痕吞掉。

## Chat prompt request tests

必须覆盖：

- API request body 仍包含 `[Memories]` 和 `[World Book Entries]` 兼容 block。
- block 内容来自 `BackgroundPacket` selected entries，而不是 direct arrays。
- current user input 不重复。
- semantic-only world book entry 可以进入 prompt。
- memory retrieval failure / worldBook source failure 的 fallback 行为符合 manager policy。
- worldBook source failure 时不得比现有行为更差：如保留 keyword fallback，则通过 explicit fallback source / closure 产出 `.worldBook` candidates；如暂不支持，Phase 6C 不能 closeout，必须记录 blocked。
- Assistant message 只由 streaming response 创建/保存，worker 不创建。

## 完成定义

- Chat 主链路调用 `BackgroundManager.prepare(...)`。
- Direct final prompt 注入权不再分别属于 Memory / WorldBook。
- Current input duplicate guard 仍有效。
- Worker 不生成 assistant message 的边界有 tests 或 clear code evidence。
- Phase 6 closeout 记录 bounded rebuild 的最终归属；本修订默认仍归属 ChatViewModel。
- 所有 `ChatViewModel(...)` 构造点已更新或明确不需要更新。

## 测试命令

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests' '-only-testing:OpenChatTests/PromptAssemblerTests' '-only-testing:OpenChatTests/BackgroundManagerTests'
```

Regression：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MemoryManagerRetrievalTests' '-only-testing:OpenChatTests/WorldBookSourceTests' '-only-testing:OpenChatTests/BackgroundSourceTests' '-only-testing:OpenChatTests/APIClientTests' '-only-testing:OpenChatTests/ResponsesAPITests'
```

## 写回要求

- Source：DI、ChatViewModel support、prompt packet use site、matching tests。
- Docs：更新 `arch/modules/chat.md`、`arch/modules/prompt-assembly.md`、`arch/modules/background/migration-plan.md`、`arch/AntiEntropy/triangle-consistency.md`。
- Harness：记录 main chain before/after、request-shape evidence、bounded rebuild ownership、full focused test result。
