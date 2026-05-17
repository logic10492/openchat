# Background Source Tools Phase 4 Closeout

> 日期：2026-05-17
> 范围：`docs/superpowers/plans/2026-05-17-background-source-tools/`
> 结论：Phase 4A-4D source tool contract、Memory / WorldBook read-only recall tools、BackgroundSource adapters 已进入 Xcode target 并通过 focused verification。Phase 5/6 继续后置，未实现 BackgroundWorker / BackgroundPacket / Chat-Prompt switch。

## 1. 执行范围

本轮执行限定为 Phase 4A / 4D runtime contracts / adapters，并兼容并发 source worker 已落地的 Phase 4B / 4C recall tool 文件。已读取：

- `AGENTS.md`
- `docs/superpowers/plans/2026-05-17-background-source-tools/*.md`
- `arch/modules/background/*`
- `arch/modules/memory/index.md`
- `arch/modules/memory/retrieval-prompt.md`
- `arch/modules/world-book.md`
- live Swift anchors：`MemoryManager.swift`、`MemoryRecallModels.swift`、`WorldBookSource.swift`、`WorldBookRecallModels.swift`、`AgentPolicy.swift`、`DeterministicAgentExecutor.swift`、`ChatViewModel+Support.swift`、`PromptAssembler.swift`

本轮没有修改：

- `OpenChat/Features/Chat/ViewModels/ChatViewModel+Support.swift`
- `OpenChat/Core/PromptEngine/PromptAssembler.swift`
- `OpenChat/Core/Database/Migrations.swift`
- `OpenChat/Core/WorldBook/WorldBookEmbeddingIndexer.swift`
- `scripts/generate_xcodeproj.rb`

## 2. 当前源码事实

- `OpenChat/Core/Background/BackgroundSourceTool.swift` 定义 `BackgroundSourceType`、`BackgroundSourceTool`、`BackgroundToolDiagnostics`、`BackgroundRequest`、`BackgroundSource`、`BackgroundCandidate`。
- `BackgroundRequest` 包含 `worldBookEntries`，因为当前 `WorldBookSource.recallEntries(...)` 是 read-only source API，条目由 caller 提供而不是由 Background 层直接查库。
- `OpenChat/Core/Memory/MemoryRecallTool.swift` 符合 `BackgroundSourceTool`，只通过 `MemoryRecallProviding.recallMemories(for:query:limit:)` 转发。
- `OpenChat/Core/WorldBook/WorldBookRecallTool.swift` 符合 `BackgroundSourceTool`，只通过 `WorldBookRecallSource.recallEntries(...)` 转发。
- `OpenChat/Core/Background/MemoryBackgroundSource.swift` / `WorldBookBackgroundSource.swift` 已进入 Xcode target，只把 recall result 映射为 `BackgroundCandidate`。
- `OpenChatTests/Core/BackgroundTests/BackgroundSourceTests.swift` 已进入 test target，覆盖 adapter 顺序、source-prefixed ids、metadata、request 边界和不按 token budget 裁剪。
- `ChatViewModel+Support` 当前仍直接调用 `memoryManager.retrieveMemories(...)` 与 `worldBookSource.recallEntries(...)`，并在世界书召回前执行 bounded `rebuildMissingOrStale(worldBookId:limit:)`。
- `PromptAssembler` 仍直接生成 `[Memories]` / `[World Book Entries]` 兼容 block；未消费 `BackgroundPacket`。

## 3. Phase 4 状态

| 阶段 | 状态 | 证据 |
|---|---|---|
| S0 baseline read + propagation audit | 已完成 | 本文件、`evidence.txt`、`arch/AntiEntropy/propagation-audit.md` |
| 4A source tool contract | 已落地 / 已 target 验证 | `BackgroundSourceTool.swift`；Phase 4 closeout focused tests 通过 |
| 4B MemoryRecallTool | 已落地 / 已测试 | `MemoryRecallTool.swift`、`MemoryRecallToolTests.swift`；顺序和 trace metadata pass-through tests 通过 |
| 4C WorldBookRecallTool | 已落地 / 已测试 | `WorldBookRecallTool.swift`、`WorldBookRecallToolTests.swift`；keyword / semantic / hybrid / omission pass-through tests 通过 |
| 4D BackgroundSource adapters | 已落地 / 已测试 | `MemoryBackgroundSource.swift`、`WorldBookBackgroundSource.swift`、`BackgroundSourceTests.swift`；candidate mapping focused tests 通过 |
| Lead closeout | 已完成 Phase 4 focused closeout | 74 tests / 9 suites passed；见 `evidence.txt` |

## 4. 验证记录

Baseline focused command：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MemoryManagerRetrievalTests' '-only-testing:OpenChatTests/WorldBookSourceTests' '-only-testing:OpenChatTests/PromptAssemblerTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests' '-only-testing:OpenChatTests/AgentPolicyTests' '-only-testing:OpenChatTests/DeterministicAgentExecutorTests'
```

结果：

- Swift Testing：58 tests / 6 suites passed。
- `xcodebuild`：`** TEST SUCCEEDED **`。
- xcresult：`/Users/fukujusou/Library/Developer/Xcode/DerivedData/OpenChat-fiicdnsnwoygvnahvbxvezbhtsfy/Logs/Test/Test-OpenChat-2026.05.17_03-23-27-+0800.xcresult`

Adapter focused command：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'id=F8D0D88B-71FD-471F-855A-B2B5D8267117' '-only-testing:OpenChatTests/BackgroundSourceTests'
```

结果：

- 第一次按 device name `iPhone 17 Pro` 启动时，simulator preflight 返回 `Busy ("Application failed preflight checks")`，测试体未执行；随后用显式 UDID `F8D0D88B-71FD-471F-855A-B2B5D8267117` 重跑。
- Swift Testing：6 tests / 1 suite passed。
- `xcodebuild`：`** TEST SUCCEEDED **`。
- xcresult：`/Users/fukujusou/Library/Developer/Xcode/DerivedData/OpenChat-fiicdnsnwoygvnahvbxvezbhtsfy/Logs/Test/Test-OpenChat-2026.05.17_03-33-58-+0800.xcresult`

Phase 4 closeout focused command：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'id=F8D0D88B-71FD-471F-855A-B2B5D8267117' '-only-testing:OpenChatTests/MemoryRecallToolTests' '-only-testing:OpenChatTests/WorldBookRecallToolTests' '-only-testing:OpenChatTests/BackgroundSourceTests' '-only-testing:OpenChatTests/MemoryManagerRetrievalTests' '-only-testing:OpenChatTests/WorldBookSourceTests' '-only-testing:OpenChatTests/PromptAssemblerTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests' '-only-testing:OpenChatTests/AgentPolicyTests' '-only-testing:OpenChatTests/DeterministicAgentExecutorTests'
```

结果：

- Swift Testing：74 tests / 9 suites passed。
- `xcodebuild`：`** TEST SUCCEEDED **`。
- xcresult：`/Users/fukujusou/Library/Developer/Xcode/DerivedData/OpenChat-fiicdnsnwoygvnahvbxvezbhtsfy/Logs/Test/Test-OpenChat-2026.05.17_03-34-38-+0800.xcresult`

Full suite：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

结果：

- Swift Testing：319 tests / 61 suites passed。
- `xcodebuild`：`** TEST SUCCEEDED **`。
- xcresult：`/Users/fukujusou/Library/Developer/Xcode/DerivedData/OpenChat-fiicdnsnwoygvnahvbxvezbhtsfy/Logs/Test/Test-OpenChat-2026.05.17_03-38-59-+0800.xcresult`

## 5. 传播审计

新增 / target-backed runtime surface：

- `OpenChat/Core/Background/BackgroundSourceTool.swift`
- `OpenChat/Core/Background/MemoryBackgroundSource.swift`
- `OpenChat/Core/Background/WorldBookBackgroundSource.swift`
- `OpenChat/Core/Memory/MemoryRecallTool.swift`
- `OpenChat/Core/WorldBook/WorldBookRecallTool.swift`
- `OpenChatTests/Core/BackgroundTests/BackgroundSourceTests.swift`
- `OpenChatTests/Core/MemoryTests/MemoryRecallToolTests.swift`
- `OpenChatTests/Core/WorldBookTests/WorldBookRecallToolTests.swift`

未传播到 runtime behavior：

- Chat 主链路未切换到 `BackgroundManager.prepare(...)`。
- `PromptAssembler` 未消费 `BackgroundPacket`。
- `BackgroundWorker` / `BackgroundPacket` / `BackgroundManager` / `BackgroundAssembler` 未实现。
- 世界书 embedding rebuild 仍属于既有 Chat / lifecycle 兼容链路，不是 BackgroundSource adapter 或后续 BackgroundWorker 的 side effect。

行为结论：当前主聊天路径仍是：

```text
ChatViewModel.generateResponse
  -> MemoryManager.retrieveMemories(...)
  -> WorldBookSource.recallEntries(...)
  -> PromptAssembler.preview / assemble
  -> ContextManager.prepareHistory
  -> APIClient.streamMessage
```

## 6. Phase 5/6 后置边界

继续后置，不得写成已实现：

- `BackgroundWorker`
- `BackgroundPacket`
- `BackgroundManager`
- `BackgroundAssembler`
- Chat / Prompt switch to `BackgroundPacket`
- `[Memories]` / `[World Book Entries]` 输出格式迁移
- LLM-assisted selector / synthesis / LibMan / Exa runtime

Phase 5/6 启动门槛：以本 Phase 4A-4D source tool / adapter contract 为输入，先实现 deterministic worker，只消费 `BackgroundCandidate`，并继续复用 `AgentPolicy.backgroundWorkerDefault()` 的 no-LLM / no-network / no-DB-write boundary。

## 7. 签名与项目配置

- 运行了 `ruby scripts/generate_xcodeproj.rb` 以加入新增 Swift source/test membership。
- `PRODUCT_BUNDLE_IDENTIFIER` 仍为 app `fukujusou.openchat.com`、tests `com.openchat.app.tests`。
- `DEVELOPMENT_TEAM` 仍为 `GZAC7644XS`。
- `CODE_SIGN_STYLE` 仍为 `Automatic`。
- `scripts/generate_xcodeproj.rb` 未修改。

## 8. Drift Audit 复查（2026-05-17）

本轮复查结论：

- 未发现 Phase 5/6 runtime 越界实现：`OpenChat/` 与 `OpenChatTests/` 中仍无 `BackgroundWorker` / `BackgroundPacket` / `BackgroundManager` / `BackgroundAssembler` Swift 定义。
- 未发现 forbidden source surface diff：`ChatViewModel+Support.swift`、`PromptAssembler.swift`、`WorldBookEmbeddingIndexer.swift`、`Migrations.swift`、`Core/Networking`、`Features/Settings`、`Features/WorldBook` 无本轮 diff。
- 发现并修复文档漂移：计划包 README、`arch/modules/background/index.md`、`arch/modules/background/background-worker.md`、`arch/modules/background/sources.md`、`arch/modules/memory/architecture.md`、`arch/AntiEntropy/triangle-consistency.md`、`arch/AntiEntropy/index.md`、`arch/index.md`、`arch/roadmap.md`、`arch/AntiEntropy/propagation-audit.md` 中的 Phase 4 状态 / full-suite 证据已同步到当前事实：Phase 4A-4D 已完成，Phase 5/6 未实现，当前 full suite 为 319 tests / 61 suites。

本轮重跑验证：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MemoryRecallToolTests' '-only-testing:OpenChatTests/WorldBookRecallToolTests' '-only-testing:OpenChatTests/BackgroundSourceTests' '-only-testing:OpenChatTests/MemoryManagerRetrievalTests' '-only-testing:OpenChatTests/WorldBookSourceTests' '-only-testing:OpenChatTests/PromptAssemblerTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests' '-only-testing:OpenChatTests/AgentPolicyTests' '-only-testing:OpenChatTests/DeterministicAgentExecutorTests'
```

结果：

- Swift Testing：74 tests / 9 suites passed。
- `xcodebuild`：`** TEST SUCCEEDED **`。
- xcresult：`/Users/fukujusou/Library/Developer/Xcode/DerivedData/OpenChat-fiicdnsnwoygvnahvbxvezbhtsfy/Logs/Test/Test-OpenChat-2026.05.17_04-22-06-+0800.xcresult`
