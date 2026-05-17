# 00. Source Baseline

## 当前事实

Phase 4A-4D 已完成，但 Phase 5/6 尚未实现。

已存在的前置源码：

- `OpenChat/Core/Background/BackgroundSourceTool.swift`
  - 定义 `BackgroundSourceType`、`BackgroundSourceTool`、`BackgroundToolDiagnostics`、`BackgroundRequest`、`BackgroundSource`、`BackgroundCandidate`。
  - 当前 `BackgroundSourceType` 只有 `.memory` / `.worldBook`。
- `OpenChat/Core/Memory/MemoryRecallTool.swift`
  - 只转发到 `MemoryManager.recallMemories(for:query:limit:)`。
- `OpenChat/Core/WorldBook/WorldBookRecallTool.swift`
  - 只转发到 `WorldBookSource.recallEntries(...)`。
- `OpenChat/Core/Background/MemoryBackgroundSource.swift`
  - 把 `MemoryRecallResult` 映射成 `BackgroundCandidate`。
- `OpenChat/Core/Background/WorldBookBackgroundSource.swift`
  - 把 `WorldBookRecallResult` 映射成 `BackgroundCandidate`。
- `OpenChat/Core/AgentCore/AgentPolicy.swift`
  - 已提供 `AgentPolicy.backgroundWorkerDefault()`。
- `OpenChat/Core/AgentCore/DeterministicAgentExecutor.swift`
  - 已有 deterministic executor 和 capability / side-effect denial 测试基础。

当前主聊天路径仍是：

```text
ChatViewModel.generateResponse
  -> MemoryManager.retrieveMemories(...)
  -> WorldBookSource.recallEntries(...)
  -> PromptAssembler.preview / assemble
  -> ContextManager.prepareHistory
  -> APIClient.streamMessage
```

当前 `ChatViewModel+Support.swift` 在世界书召回前执行 bounded `rebuildMissingOrStale(worldBookId:limit:)` side-effect。该 side-effect 是兼容链路遗留边界，不属于 `BackgroundWorker`。

当前 `PromptAssembler.swift` 仍直接产出：

```text
[World Book Entries]
...
[/World Book Entries]

[Memories]
...
[/Memories]
```

Phase 6 切换时，建议先保持这些文本 block 名称，来源从 direct Memory / WorldBook arrays 切到 `BackgroundPacket`。

## 必须读取文件

执行前必须重新读取当前文件，不可只按本计划假设接口：

- `AGENTS.md`
- `arch/modules/background/index.md`
- `arch/modules/background/architecture.md`
- `arch/modules/background/sources.md`
- `arch/modules/background/background-worker.md`
- `arch/modules/background/migration-plan.md`
- `arch/modules/agent-core.md`
- `arch/modules/memory/retrieval-prompt.md`
- `arch/modules/world-book.md`
- `arch/modules/prompt-assembly.md`
- `arch/modules/chat.md`
- `OpenChat/Core/Background/BackgroundSourceTool.swift`
- `OpenChat/Core/Background/MemoryBackgroundSource.swift`
- `OpenChat/Core/Background/WorldBookBackgroundSource.swift`
- `OpenChat/Core/Memory/MemoryRecallTool.swift`
- `OpenChat/Core/WorldBook/WorldBookRecallTool.swift`
- `OpenChat/Core/AgentCore/AgentPolicy.swift`
- `OpenChat/Core/AgentCore/DeterministicAgentExecutor.swift`
- `OpenChat/App/DependencyContainer.swift`
- `OpenChat/Features/Chat/ViewModels/ChatViewModel+Support.swift`
- `OpenChat/Core/PromptEngine/PromptAssembler.swift`
- `OpenChatTests/Core/BackgroundTests/BackgroundSourceTests.swift`
- `OpenChatTests/Core/MemoryTests/MemoryRecallToolTests.swift`
- `OpenChatTests/Core/WorldBookTests/WorldBookRecallToolTests.swift`
- `OpenChatTests/Core/AgentCoreTests/AgentPolicyTests.swift`
- `OpenChatTests/Core/AgentCoreTests/DeterministicAgentExecutorTests.swift`
- `OpenChatTests/Core/PromptEngineTests/PromptAssemblerTests.swift`
- `OpenChatTests/Features/ChatTests/ChatViewModelPromptAssemblyTests.swift`

## Drift 风险

- `BackgroundRequest` 已经存在，Phase 5 不应重复定义同名字段造成迁移震荡。
- `BackgroundCandidate` 已经存在，Phase 5 应扩展或新增 packet DTO，而不是绕过 candidate。
- `MemoryBackgroundSource` 与 `WorldBookBackgroundSource` 当前不按 token budget 裁剪；预算裁剪属于 worker。
- `WorldBookBackgroundSource` 不触发 rebuild；不要把当前 Chat bounded rebuild 搬进 source adapter 或 worker。
- `PromptAssembler.previewWithPreselectedWorldBookEntries(...)` 当前是世界书 semantic-only 兼容入口；Phase 6 改动需要保留 semantic-only entries 不被 keyword 二次过滤。
- `ChatViewModel.generateResponse(...)` 先持久化用户消息，再过滤 prompt history，避免 current input 重复；Phase 6 必须保留该防线。

## 完成定义

- Phase 5 开始前，执行者已确认上述文件与当前代码一致。
- 记录当前 `git status --short`，区分用户已有改动、本计划改动和生成器改动。
- 在 harness 或 result 中明确：Phase 4 已完成，Phase 5/6 未实现。

## 测试命令

基线 focused：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MemoryRecallToolTests' '-only-testing:OpenChatTests/WorldBookRecallToolTests' '-only-testing:OpenChatTests/BackgroundSourceTests' '-only-testing:OpenChatTests/AgentPolicyTests' '-only-testing:OpenChatTests/DeterministicAgentExecutorTests'
```

主链路 guard：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/PromptAssemblerTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests'
```

## 写回要求

- Source：本 baseline 阶段不改 source。
- Docs：实施后如果发现 arch 当前事实漂移，写回 `arch/modules/background/*`，但不能把计划写成已实现。
- Harness：记录基线命令、结果、xcresult 路径、当前 side-effect 边界和未实现面。
