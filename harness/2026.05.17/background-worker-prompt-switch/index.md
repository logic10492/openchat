# Background Worker / Prompt Switch Closeout

> 日期：2026-05-17
> 范围：`docs/superpowers/plans/2026-05-17-background-worker-prompt-switch/`
> 状态：完成。记录编辑前传播审计、Phase 5/6 实现证据、验证结果、arch/AntiEntropy 写回和剩余边界。

## 1. 编辑前传播审计

审计模式：窄范围增量传播审计。OpenChat 没有 Magnum Agent 的 import 图脚本，因此本轮沿用 `arch/AntiEntropy/propagation-audit.md` 的方法：`rg` 静态引用面 + live Swift 行为链路复核。

### 1.1 工作区基线

编辑前 `git status --short` 显示已有用户改动：

```text
 M docs/superpowers/plans/2026-05-17-background-worker-prompt-switch/02_dag_and_file_ownership.md
 M docs/superpowers/plans/2026-05-17-background-worker-prompt-switch/06_phase_6a_background_manager_integration.md
 M docs/superpowers/plans/2026-05-17-background-worker-prompt-switch/07_phase_6b_prompt_packet_compat_switch.md
 M docs/superpowers/plans/2026-05-17-background-worker-prompt-switch/08_phase_6c_chat_switch.md
 M docs/superpowers/plans/2026-05-17-background-worker-prompt-switch/09_testing_acceptance.md
 M docs/superpowers/plans/2026-05-17-background-worker-prompt-switch/10_new_thread_handoff.md
?? comp_swap/
```

这些计划包 / handoff 改动视为用户已有改动，本轮实现不覆盖。

### 1.2 静态影响面

Phase 5 预计新增 / 修改：

- `OpenChat/Core/Background/BackgroundPolicy.swift`
- `OpenChat/Core/Background/BackgroundPacket.swift`
- `OpenChat/Core/Background/BackgroundDiagnostics.swift`
- `OpenChat/Core/Background/BackgroundWorker.swift`
- `OpenChatTests/Core/BackgroundTests/BackgroundPacketTests.swift`
- `OpenChatTests/Core/BackgroundTests/BackgroundWorkerTests.swift`
- `OpenChatTests/Core/BackgroundTests/BackgroundDiagnosticsTests.swift`

Phase 6 预计新增 / 修改：

- `OpenChat/Core/Background/BackgroundManager.swift`
- `OpenChat/Core/Background/BackgroundAssembler.swift`
- `OpenChat/Core/PromptEngine/PromptAssembler.swift`
- `OpenChat/App/DependencyContainer.swift`
- `OpenChat/Features/Chat/ViewModels/ChatViewModel.swift`
- `OpenChat/Features/Chat/ViewModels/ChatViewModel+Support.swift`
- `OpenChatTests/Core/BackgroundTests/BackgroundManagerTests.swift`
- `OpenChatTests/Core/PromptEngineTests/PromptAssemblerTests.swift`
- `OpenChatTests/Features/ChatTests/ChatViewModelPromptAssemblyTests.swift`

不触碰面：

- 不修改 `OpenChat/Core/Database/Migrations.swift`。
- 不修改 `OpenChat/Core/WorldBook/WorldBookEmbeddingIndexer.swift`。
- 不修改 `OpenChat/Core/Networking/*`。
- 不修改签名配置；如新增 Swift 文件需要 target membership，只运行 `ruby scripts/generate_xcodeproj.rb`。

### 1.3 行为链路基线

当前主聊天链路仍是：

```text
ChatViewModel.generateResponse
  -> MemoryManager.retrieveMemories(...)
  -> WorldBookEmbeddingIndexer.rebuildMissingOrStale(...)
  -> WorldBookSource.recallEntries(...)
  -> PromptAssembler.previewWithPreselectedWorldBookEntries / assembleWithPreselectedWorldBookEntries
  -> ContextManager.prepareHistory
  -> APIClient.streamMessage
```

已确认边界：

- `OpenChat/Core/Background/MemoryBackgroundSource.swift` 和 `WorldBookBackgroundSource.swift` 只把 recall result 映射为 `BackgroundCandidate`，不裁剪 token budget。
- `ChatViewModel+Support.swift` 中的 bounded `WorldBookEmbeddingIndexer.rebuildMissingOrStale(worldBookId:limit:)` 是 Chat 兼容 side effect，本轮按计划保留在 Chat，不能迁入 `BackgroundWorker`。
- `PromptAssembler.swift` 当前直接生成 `[World Book Entries]` 和 `[Memories]` block；Phase 6 只把来源切换到 `BackgroundPacket`，不默认迁移到统一 `[Background]` block。
- `makePromptHistoryMessages(...)` 过滤本轮 user record，Phase 6 需保留 current input 只进入最终 current-turn message 一次。

### 1.4 传播风险

- `BackgroundPolicy.tokenBudget` 是 worker candidate selection ceiling；最终 prompt inclusion 仍由 `PromptAssembler` 的现有 `TokenBudget` 裁剪。
- `BackgroundManager` source failure 应降级为其他 source candidates + diagnostics warning；worker policy denial 应抛错且不返回 partial packet。
- worldBook source failure 不能丢失旧 keyword fallback；Chat switch 需提供 explicit fallback path。
- `BackgroundPacket.diagnostics` 不进入 prompt 文本。
- 新增 `ChatViewModel` 依赖会传播到 `ContentView.swift`、`ChatView.swift` preview 和所有 `ChatViewModelPromptAssemblyTests.swift` 构造点。

## 2. 实现证据

### 2.1 Phase 5：DTO / worker / diagnostics

新增 runtime 文件：

- `OpenChat/Core/Background/BackgroundPolicy.swift`
- `OpenChat/Core/Background/BackgroundPacket.swift`
- `OpenChat/Core/Background/BackgroundDiagnostics.swift`
- `OpenChat/Core/Background/BackgroundWorker.swift`

新增测试：

- `OpenChatTests/Core/BackgroundTests/BackgroundPacketTests.swift`
- `OpenChatTests/Core/BackgroundTests/BackgroundWorkerTests.swift`
- `OpenChatTests/Core/BackgroundTests/BackgroundDiagnosticsTests.swift`

实现结论：

- `BackgroundWorker` 只消费 `[BackgroundCandidate]`，输出 `BackgroundPacket`，不读写 DB、不联网、不调用 LLM、不生成 assistant message、不触发 worldBook rebuild。
- `BackgroundPolicy.compatibilityDefault(...)` 使用 deterministic AgentCore policy；worker 会拒绝非 deterministic / 额外 capability / network / database write 等越界配置。
- `BackgroundPolicy.tokenBudget` 是 worker candidate selection ceiling；最终 request body 是否包含某条 background item 仍由 `PromptAssembler` 的 `TokenBudget` 裁剪。
- `BackgroundPacket.diagnostics` 记录 selected / omitted / fallback / source summaries，但 diagnostics、score 和 omission reason 不进入 prompt 文本。

### 2.2 Phase 6：manager / prompt / chat switch

新增 runtime 文件：

- `OpenChat/Core/Background/BackgroundManager.swift`
- `OpenChat/Core/Background/BackgroundAssembler.swift`

修改 runtime 文件：

- `OpenChat/Core/Background/BackgroundSourceTool.swift`：`BackgroundSourceType` 增加 `CaseIterable` / `Hashable`；live cases 仍只有 `.memory` / `.worldBook`。
- `OpenChat/Core/PromptEngine/PromptAssembler.swift`：新增 packet-aware `preview(... backgroundPacket:)` / `assemble(... backgroundPacket:)`；旧 direct overload 保留作兼容 / rollback。
- `OpenChat/App/DependencyContainer.swift`：装配 `BackgroundManager`，sources 为 `MemoryBackgroundSource(tool: MemoryRecallTool(memoryManager: ...))` 与 `WorldBookBackgroundSource(tool: WorldBookRecallTool(source: ...))`。
- `OpenChat/ContentView.swift` / `OpenChat/Features/Chat/Views/ChatView.swift`：向 `ChatViewModel` 注入 `backgroundManager`。
- `OpenChat/Features/Chat/ViewModels/ChatViewModel.swift`：新增可选 `backgroundManager` 依赖，方便测试和 rollback。
- `OpenChat/Features/Chat/ViewModels/ChatViewModel+Support.swift`：主链路改为 `bounded worldBook rebuild -> BackgroundManager.prepare(...) -> PromptAssembler.preview(... backgroundPacket:) -> ContextManager.prepareHistory(...) -> PromptAssembler.assemble(... backgroundPacket:)`。

新增 / 修改测试：

- `OpenChatTests/Core/BackgroundTests/BackgroundManagerTests.swift`
- `OpenChatTests/Core/PromptEngineTests/PromptAssemblerTests.swift`
- `OpenChatTests/Features/ChatTests/ChatViewModelPromptAssemblyTests.swift`

实现结论：

- Chat 主链路不再直接把 `MemoryManager.retrieveMemories(...)` / `WorldBookSource.recallEntries(...)` 的数组交给 `PromptAssembler`。
- `BackgroundManager` 负责 source orchestration；单 source 失败时记录 diagnostics warning。worldBook source failure 会用 `BackgroundRequest.worldBookEntries + recentMessages + currentInput` 生成旧 keyword fallback `.worldBook` candidates。
- `BackgroundAssembler` 维持兼容输出：`[World Book Entries]` 在 `[Memories]` 之前；统一 `[Background]` block 未启用。
- bounded `WorldBookEmbeddingIndexer.rebuildMissingOrStale(worldBookId:limit:)` 仍保留在 Chat pre-source stage，不属于 `BackgroundWorker` 或 `WorldBookBackgroundSource` side effect。
- `makePromptHistoryMessages(...)` 仍过滤本轮 user record，保持 current input 只进入最终 current-turn message 一次。

## 3. 验证记录

### 3.1 Phase 5/6 focused tests

命令：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/BackgroundPacketTests' '-only-testing:OpenChatTests/BackgroundWorkerTests' '-only-testing:OpenChatTests/BackgroundDiagnosticsTests' '-only-testing:OpenChatTests/BackgroundManagerTests' '-only-testing:OpenChatTests/PromptAssemblerTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests'
```

结果：40 tests / 6 suites passed，`** TEST SUCCEEDED **`。

xcresult：

```text
/Users/fukujusou/Library/Developer/Xcode/DerivedData/OpenChat-fiicdnsnwoygvnahvbxvezbhtsfy/Logs/Test/Test-OpenChat-2026.05.17_16-03-54-+0800.xcresult
```

### 3.2 Source / AgentCore broader regression

命令：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MemoryRecallToolTests' '-only-testing:OpenChatTests/WorldBookRecallToolTests' '-only-testing:OpenChatTests/BackgroundSourceTests' '-only-testing:OpenChatTests/MemoryManagerRetrievalTests' '-only-testing:OpenChatTests/WorldBookSourceTests' '-only-testing:OpenChatTests/AgentPolicyTests' '-only-testing:OpenChatTests/DeterministicAgentExecutorTests'
```

结果：45 tests / 7 suites passed，`** TEST SUCCEEDED **`。

xcresult：

```text
/Users/fukujusou/Library/Developer/Xcode/DerivedData/OpenChat-fiicdnsnwoygvnahvbxvezbhtsfy/Logs/Test/Test-OpenChat-2026.05.17_16-04-31-+0800.xcresult
```

### 3.3 其他验证

- `ruby scripts/generate_xcodeproj.rb` 已运行，使新增 Swift 文件进入 Xcode target；脚本本身未修改。
- `git diff --check`：通过，无 whitespace errors。
- 本轮收尾只改 arch / harness 文档；未在收尾阶段再次改 runtime source。

## 4. Arch / AntiEntropy 写回

已更新当前源码事实的 arch 文档：

- `arch/modules/background/index.md`
- `arch/modules/background/architecture.md`
- `arch/modules/background/background-worker.md`
- `arch/modules/background/migration-plan.md`
- `arch/modules/background/sources.md`
- `arch/modules/background/world-book-vectorization.md`
- `arch/modules/prompt-assembly.md`
- `arch/modules/chat.md`
- `arch/modules/memory/index.md`
- `arch/modules/memory/architecture.md`
- `arch/modules/memory/retrieval-prompt.md`
- `arch/modules/memory/hindsight-lite.md`
- `arch/modules/world-book.md`

已更新 AntiEntropy 文档：

- `arch/AntiEntropy/propagation-audit.md`
- `arch/AntiEntropy/triangle-consistency.md`

写回结论：

- 当前 `BackgroundWorker` / `BackgroundPacket` / `BackgroundManager` / `BackgroundAssembler` 已实现并进入 target。
- 当前 Chat / Prompt 主链路已切到 packet-compatible path。
- 兼容 `[World Book Entries]` / `[Memories]` 输出仍保留；统一 `[Background]` block 未启用。
- Memory / WorldBook source tools 和 adapters 仍只包装既有 recall result，不复制 Memory rank fusion 或 WorldBook keyword+semantic fusion。
- CharacterBackgroundSource、ConversationStateBackgroundSource、LibMan、Exa、LLM-assisted selector、synthesis worker、packet diagnostics UI 仍为后续范围。

## 5. 变更后传播链路

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

## 6. 未完成边界

- 统一 `[Background]` block 未默认启用；需要单独 request-shape audit。
- `BackgroundSourceType` live cases 仍只有 `.memory` / `.worldBook`；Character / ConversationState sources 未实现。
- LibMan / Exa / LLM-assisted selector / synthesis worker 未实现。
- bounded worldBook rebuild 尚未迁移进 manager pre-source stage，当前仍由 ChatViewModel 负责。
- 没有新增 DB migration，没有修改 `Migrations.swift`。
- 没有修改签名配置；`OpenChat.xcodeproj` 仅由 `scripts/generate_xcodeproj.rb` 再生成。
