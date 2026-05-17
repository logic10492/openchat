# 02. DAG 与文件归属

## 阶段 DAG

```text
S0 baseline read + propagation audit
  -> 4A source tool contract
  -> 4B MemoryRecallTool + focused tests
  -> 4C WorldBookRecallTool + focused tests
  -> 4D BackgroundSource adapters + focused tests
  -> Lead closeout for Phase 4
  -> 5A Background DTO
  -> 5B deterministic BackgroundWorker
  -> 5C worker diagnostics + tests
  -> 6A BackgroundManager integration
  -> 6B PromptAssembler compatible packet input
  -> 6C ChatViewModel switch
```

Phase 4 是工具阶段。Phase 5 / 6 是后续阶段，不能提前写 runtime integration。

可并行窗口：

- 4B 和 4C 可以并行，前提是 4A contract 已稳定。
- 4D 必须等 4B / 4C result shape 明确后再做。
- Phase 5 文档可以提前草拟，但 Swift runtime 不能早于 Phase 4 closeout。

不可并行：

- 不能在写 RecallTool 的同时改 `PromptAssembler`。
- 不能在写 adapter 的同时把 Chat 切到 `BackgroundPacket`。
- 不能在 worker 尚未通过 tests 时改 prompt 输出格式。

## Phase 4 文件归属

| 阶段 | 主要文件 | 测试文件 | 文档写回 |
|---|---|---|---|
| S0 | docs only | 无 | 本计划包 / `harness/<date>/...` |
| 4A | `OpenChat/Core/Background/BackgroundSourceTool.swift` 或等价 contract 文件；`BackgroundRequest.swift` / `BackgroundCandidate.swift` 可只放最小 DTO | `BackgroundSourceToolTests.swift` 如有行为 | `arch/modules/background/architecture.md` |
| 4B | `OpenChat/Core/Memory/MemoryRecallTool.swift` | `OpenChatTests/Core/MemoryTests/MemoryRecallToolTests.swift` | `arch/modules/memory/*`, `arch/modules/background/migration-plan.md` |
| 4C | `OpenChat/Core/WorldBook/WorldBookRecallTool.swift` | `OpenChatTests/Core/WorldBookTests/WorldBookRecallToolTests.swift` | `arch/modules/world-book.md`, `arch/modules/background/world-book-vectorization.md` |
| 4D | `OpenChat/Core/Background/MemoryBackgroundSource.swift`, `WorldBookBackgroundSource.swift` 或 source-specific adapter files | `OpenChatTests/Core/BackgroundTests/BackgroundSourceTests.swift` | `arch/modules/background/architecture.md`, `background-worker.md` |
| Lead | `OpenChat.xcodeproj/project.pbxproj` only if generated | focused + regression tests | `harness/<date>/background-source-tools/index.md` |

## Phase 5 / 6 文件归属预告

Phase 5 后续文件：

```text
OpenChat/Core/Background/
  BackgroundPolicy.swift
  BackgroundWorker.swift
  BackgroundPacket.swift
  BackgroundDiagnostics.swift
```

Phase 6 后续文件：

```text
OpenChat/Core/Background/
  BackgroundManager.swift
  BackgroundAssembler.swift

OpenChat/App/DependencyContainer.swift
OpenChat/Features/Chat/ViewModels/ChatViewModel+Support.swift
OpenChat/Core/PromptEngine/PromptAssembler.swift
OpenChatTests/Features/ChatTests/ChatViewModelPromptAssemblyTests.swift
OpenChatTests/Core/PromptEngineTests/PromptAssemblerTests.swift
```

以上 Phase 5 / 6 文件不属于 Phase 4 工具优先段。新 thread 执行 Phase 4 时如果需要修改这些文件，必须先停下来重审计划边界。

## Project generation rule

新增 Swift 文件后，如果 `xcodebuild` 不能发现 source/test membership，应运行：

```bash
ruby scripts/generate_xcodeproj.rb
```

约束：

- 不手工修改签名配置。
- `project.pbxproj` 变更必须来自 generator。
- 如果 generator 造成无关漂移，停止并单独审计。

## 禁止文件清单：Phase 4

Phase 4 默认禁止修改：

- `OpenChat/Features/Chat/ViewModels/ChatViewModel+Support.swift`
- `OpenChat/Core/PromptEngine/PromptAssembler.swift`
- `OpenChat/Core/WorldBook/WorldBookEmbeddingIndexer.swift`
- `OpenChat/Core/Database/Migrations.swift`
- `OpenChat/Core/Networking/*`
- `OpenChat/Features/Settings/*`
- `OpenChat/Features/WorldBook/*`

例外：如果 tests 暴露现有 source bug，先记录到 harness / plan appendix，再让用户确认是否扩大范围。
