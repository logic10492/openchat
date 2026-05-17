# 02. DAG 与文件归属

## DAG

```text
S0 baseline read + drift audit
  -> 5A DTO contract
  -> 5B deterministic BackgroundWorker
  -> 5C diagnostics + focused tests
  -> Phase 5 closeout
  -> 6A BackgroundManager integration
  -> 6B PromptAssembler compatible packet switch
  -> 6C ChatViewModel switch
  -> Phase 6 closeout
```

## 并行窗口

可以并行：

- 5A DTO 草案和 5C diagnostics schema 草案可以并行审阅，但落地顺序必须先稳定 DTO。
- 6B PromptAssembler tests 可以先写 red/contract tests，但 runtime switch 需等 6A manager API 稳定。
- 文档写回可以由 lead 在每阶段结束后集中做，但不得提前把 planned 写成 implemented。

不可并行：

- 5B worker 未完成前，不改 `PromptAssembler`。
- 5C diagnostics 未完成前，不让 Chat 消费 worker 输出。
- 6A manager 未完成前，不把 `ChatViewModel` 切到 packet。
- bounded worldBook rebuild 的迁移不能和 prompt switch 混在一个无测试改动里。

## Phase 5 文件归属

| 阶段 | 允许 source | 测试 | 文档写回 |
|---|---|---|---|
| 5A DTO | `OpenChat/Core/Background/BackgroundPolicy.swift`、`BackgroundPacket.swift`、必要时扩展 `BackgroundSourceTool.swift` | `OpenChatTests/Core/BackgroundTests/BackgroundPacketTests.swift` | `arch/modules/background/architecture.md`、`background-worker.md` |
| 5B Worker | `OpenChat/Core/Background/BackgroundWorker.swift` | `OpenChatTests/Core/BackgroundTests/BackgroundWorkerTests.swift` | `arch/modules/background/background-worker.md` |
| 5C Diagnostics | `OpenChat/Core/Background/BackgroundDiagnostics.swift`，必要时补充 worker diagnostics hooks | `OpenChatTests/Core/BackgroundTests/BackgroundDiagnosticsTests.swift`、worker tests | `arch/modules/background/architecture.md`、`arch/AntiEntropy/propagation-audit.md` |

Phase 5 禁止修改：

- `OpenChat/App/DependencyContainer.swift`
- `OpenChat/Features/Chat/ViewModels/ChatViewModel+Support.swift`
- `OpenChat/Core/PromptEngine/PromptAssembler.swift`
- `OpenChat/Core/Database/Migrations.swift`
- `OpenChat/Core/WorldBook/WorldBookEmbeddingIndexer.swift`
- `OpenChat/Core/Memory/MemoryManager.swift`
- `OpenChat/Core/WorldBook/WorldBookSource.swift`
- `OpenChat/Core/Networking/*`

## Phase 6 文件归属

| 阶段 | 允许 source | 测试 | 文档写回 |
|---|---|---|---|
| 6A Manager | `OpenChat/Core/Background/BackgroundManager.swift`，必要时 `BackgroundAssembler.swift` contract shell | `OpenChatTests/Core/BackgroundTests/BackgroundManagerTests.swift` | `arch/modules/background/architecture.md`、`sources.md`、`migration-plan.md` |
| 6B Prompt packet switch | `OpenChat/Core/Background/BackgroundAssembler.swift`、`OpenChat/Core/PromptEngine/PromptAssembler.swift` | `OpenChatTests/Core/PromptEngineTests/PromptAssemblerTests.swift` | `arch/modules/prompt-assembly.md` |
| 6C Chat switch | `OpenChat/App/DependencyContainer.swift`、`OpenChat/Features/Chat/ViewModels/ChatViewModel+Support.swift` | `OpenChatTests/Features/ChatTests/ChatViewModelPromptAssemblyTests.swift`、request-shape tests if needed | `arch/modules/chat.md`、`arch/modules/background/migration-plan.md` |

Phase 6 仍禁止：

- 不改签名配置。
- 不新增 DB migration，除非用户批准新的持久化需求。
- 不把 LLM-assisted selector、LibMan、Exa、synthesis 混入主链路。
- 不让普通角色获得 tool 权限。

## 需审批面

以下情况必须停下来请用户确认：

- 需要修改 `scripts/generate_xcodeproj.rb`。
- 需要变更签名配置。
- 需要新增 DB migration。
- 需要让 BackgroundWorker 读 DB、写 DB、联网或调用 LLM。
- 需要把 `[Background]` 统一 block 作为默认输出替代兼容 block。
- 需要迁移 bounded worldBook rebuild 且无法单独测试。

## 完成定义

- 每个阶段只改自己的文件归属面。
- Phase 5 closeout 前，`git diff` 中不得出现 Chat / Prompt / DI 改动。
- Phase 6 closeout 前，所有 Prompt / Chat 行为变化都有 focused tests。
- Xcode project 变更如出现，必须来自 `ruby scripts/generate_xcodeproj.rb`。

## 测试命令

阶段 smoke：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/BackgroundSourceTests' '-only-testing:OpenChatTests/AgentPolicyTests' '-only-testing:OpenChatTests/DeterministicAgentExecutorTests'
```

Phase 6 regression：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/PromptAssemblerTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests' '-only-testing:OpenChatTests/WorldBookSourceTests' '-only-testing:OpenChatTests/MemoryManagerRetrievalTests'
```

## 写回要求

- Source：遵守表格 ownership。
- Docs：每阶段完成后写当前事实，不写目标假装已完成。
- Harness：记录每阶段 diff surface、测试命令、结果、未运行原因和需审批项。
