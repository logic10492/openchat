# 08. 测试与验收

## Baseline

实施前：

```bash
git status --short
```

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MemoryManagerRetrievalTests' '-only-testing:OpenChatTests/WorldBookSourceTests' '-only-testing:OpenChatTests/PromptAssemblerTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests' '-only-testing:OpenChatTests/AgentPolicyTests' '-only-testing:OpenChatTests/DeterministicAgentExecutorTests'
```

如 simulator 不可用：

```bash
xcrun simctl list devices available | rg 'iPhone'
```

## Phase 4 focused tests

Memory tool：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MemoryRecallToolTests' '-only-testing:OpenChatTests/MemoryManagerRetrievalTests'
```

WorldBook tool：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/WorldBookRecallToolTests' '-only-testing:OpenChatTests/WorldBookSourceTests'
```

Adapters：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/BackgroundSourceTests'
```

Phase 4 closeout focused：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MemoryRecallToolTests' '-only-testing:OpenChatTests/WorldBookRecallToolTests' '-only-testing:OpenChatTests/BackgroundSourceTests' '-only-testing:OpenChatTests/MemoryManagerRetrievalTests' '-only-testing:OpenChatTests/WorldBookSourceTests' '-only-testing:OpenChatTests/PromptAssemblerTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests' '-only-testing:OpenChatTests/AgentPolicyTests' '-only-testing:OpenChatTests/DeterministicAgentExecutorTests'
```

## Phase 5/6 后续 tests

Phase 5 worker：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/BackgroundWorkerTests' '-only-testing:OpenChatTests/AgentPolicyTests' '-only-testing:OpenChatTests/DeterministicAgentExecutorTests'
```

Phase 6 prompt switch：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/PromptAssemblerTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests' '-only-testing:OpenChatTests/BackgroundWorkerTests' '-only-testing:OpenChatTests/BackgroundSourceTests'
```

## Full suite

源码实施完成后最终运行：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

如果遇到 simulator `Busy` / preflight failure，换用 `xcrun simctl list devices available | rg 'iPhone'` 中的可用设备，并记录实际 device name / id。

## 文档写回

Phase 4 完成后至少同步：

- `arch/modules/background/migration-plan.md`
- `arch/modules/background/architecture.md`
- `arch/modules/background/background-worker.md`
- `arch/modules/memory/index.md`
- `arch/modules/world-book.md`
- `arch/modules/background/world-book-vectorization.md`
- `harness/<date>/background-source-tools/index.md`

写回必须区分：

- 已实现：Memory / WorldBook read-only source tools。
- 已实现：BackgroundSource adapters，如完成。
- 未实现：BackgroundWorker / BackgroundPacket / prompt switch，除非确实进入 Phase 5/6 并通过测试。

## 完成定义：Phase 4

- `MemoryRecallTool` 只包装 `MemoryManager.recallMemories(...)`。
- `WorldBookRecallTool` 只包装 `WorldBookSource.recallEntries(...)`。
- tools 输出保持原 result 顺序和 trace metadata。
- `MemoryBackgroundSource` / `WorldBookBackgroundSource` 只做 candidate 转换。
- 没有 prompt 注入变化。
- 没有 Chat runtime switch。
- 没有 DB write / network / rebuild side effect。
- focused tool / adapter tests 通过。
- Memory / WorldBook / Prompt / Chat regression focused tests 通过。
- Xcode project membership 已更新且签名配置无手工漂移。
- 文档和 harness evidence 已写回。

## 完成定义：Phase 5/6

Phase 5/6 只有在 Phase 4 完成后才能声明：

- `BackgroundWorker` 只消费 `BackgroundCandidate`。
- worker 使用 `AgentPolicy.backgroundWorkerDefault()`。
- deterministic worker 不调用 LLM、不联网、不写 DB、不生成 assistant message。
- `BackgroundPacket` diagnostics 能记录 selected / omitted / fallback / source counts。
- Prompt switch 后没有重复当前用户输入。
- 兼容 block 或统一 `[Background]` block 的文本输出有 focused tests。
- full suite 通过；如有 baseline failure，必须证明不是本轮回归。
