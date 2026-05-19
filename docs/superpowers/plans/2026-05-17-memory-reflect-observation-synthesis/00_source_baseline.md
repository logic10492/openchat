# 00. Source Baseline

## 当前事实

Phase 5 执行前的前置条件已经部分存在，但还没有可执行的低频 reflect 流程。2026-05-18 执行后状态见本文末尾 closeout note。

已存在：

- `OpenChat/Core/Memory/MemoryReflectModels.swift`
  - 定义 reflect request / observation / task / action / relation contract。
  - `MemoryReflectRequest` 要求 `characterCardId` 与 `sourceMemoryIds` 非空。
  - `MemoryReflectObservation` 要求 `content` 与 `basedOnMemoryIds` 非空，并将 `confidence` clamp 到 `0...1`。
  - `MemoryEntryLinkRelation` 当前最小集合是 `summarizes`、`duplicates`、`reinforces`。
- `OpenChatTests/Core/MemoryTests/MemoryReflectModelsTests.swift`
  - 覆盖上述最小 contract。
- `OpenChat/Core/Database/Migrations.swift`
  - 已有 `v14_create_memory_entry_provenance`。
  - 已有 `v15_create_world_book_entry_embedding`、`v16_create_world_book_entry_embedding_meta`。
  - 执行前 `memory_entry_link` 必须追加 v17+ migration；执行后已追加 `v17_create_memory_entry_link`。
- `OpenChat/Core/Database/DatabaseManager+Memory.swift`
  - 已有 memory CRUD、provenance CRUD 和 high-value recall helper。
- `OpenChat/Core/Memory/VectorStore.swift`
  - 已有 memory entry + embedding + provenance 原子写入路径。
- `OpenChat/Core/Memory/MemoryManager.swift`
  - retain / recall 已实现。
  - `extractMemories(from:)` 已使用 LLM 做结构化 retain；执行后已新增 reflect executor，仍不进入 extraction threshold。
- `OpenChat/Features/CharacterCard/ViewModels/MemoryListViewModel.swift`
  - 执行前已有 memory list / delete / delete all 管理入口。
  - 执行后已有整理记忆、review draft 和 apply observation 状态。

执行前尚未实现：

- `memory_entry_link` table / record / DB API。
- reflect executor / parser / diagnostics。
- observation draft 持久化或 review flow。
- 用户手动整理入口。
- idle / background 低频触发策略。
- reflect 结果进入 Memory recall 排序的明确测试。

## 当前主链路

当前 Chat 主链路已经通过 BackgroundPacket 消费 Memory recall：

```text
MemoryManager.recallMemories
  -> MemoryRecallTool
  -> MemoryBackgroundSource
  -> BackgroundWorker
  -> BackgroundPacket
  -> PromptAssembler(... backgroundPacket:)
  -> [Memories] compatibility block
```

Phase 5 不应改变上面这条每轮聊天路径。Reflect 只能作为手动或低频整理任务，不能阻塞用户发送消息。

## 必须读取文件

执行前必须重新读取当前文件，不可只按本计划假设接口：

- `AGENTS.md`
- `PLANING.md`
- `arch/modules/memory/index.md`
- `arch/modules/memory/data-model.md`
- `arch/modules/memory/hindsight-lite.md`
- `arch/modules/memory/extraction.md`
- `arch/modules/memory/retrieval-prompt.md`
- `arch/modules/memory/testing.md`
- `arch/modules/background/index.md`
- `arch/modules/background/architecture.md`
- `arch/modules/background/background-worker.md`
- `OpenChat/Core/Memory/MemoryReflectModels.swift`
- `OpenChat/Core/Memory/MemoryManager.swift`
- `OpenChat/Core/Memory/MemoryRecallModels.swift`
- `OpenChat/Core/Memory/MemoryRecallTool.swift`
- `OpenChat/Core/Memory/VectorStore.swift`
- `OpenChat/Core/Database/Migrations.swift`
- `OpenChat/Core/Database/DatabaseManager+Memory.swift`
- `OpenChat/Core/Database/Records/MemoryEntryRecord.swift`
- `OpenChat/Core/Database/Records/MemoryEntryProvenanceRecord.swift`
- `OpenChat/Core/Networking/APIClient.swift`
- `OpenChat/App/DependencyContainer.swift`
- `OpenChat/Features/CharacterCard/ViewModels/MemoryListViewModel.swift`
- `OpenChat/Features/CharacterCard/Views/MemoryListView.swift`
- `OpenChat/Resources/Localizable.xcstrings`
- `OpenChatTests/Core/MemoryTests/MemoryReflectModelsTests.swift`
- `OpenChatTests/Core/DatabaseTests/MigrationTests.swift`
- `OpenChatTests/Core/DatabaseTests/DatabaseManagerMemoryTests.swift`
- `OpenChatTests/Core/MemoryTests/MemoryManagerRetrievalTests.swift`
- `OpenChatTests/Core/MemoryTests/VectorStoreTests.swift`

## Drift 风险

- `MemoryEntryLinkRelation` 已有最小 raw values；不要在 migration / parser 中使用不同拼写。
- 当前最新 migration 已到 v16；新增 link table 应使用 v17+。
- `VectorStore.insert(entries:provenances:)` 不知道 link；apply observation 需要新的原子写入 API 或 DB transaction helper。
- `MemoryManager.extractMemories(from:)` 已承担 retain；不要把 reflect 混进 extraction threshold。
- `MemoryListViewModel` 是 `@MainActor` UI 状态入口；后台低频任务不应直接依赖它。
- `DependencyContainer` 当前只有 `memoryManager`，没有独立 reflect service；引入新 service 会触碰 DI 和 preview。
- 当前工作区可能有 unrelated Chat / Xcode dirty files；执行计划前必须记录并隔离 staging。

## 完成定义

- S0 closeout 必须记录当前 `git status --short`。
- 必须区分已有用户改动、本计划改动和 Xcode project 生成器改动。
- 必须确认 `memory_entry_link` 尚不存在，且 migration 只追加。
- 必须确认 Phase 5 不需要修改 Chat prompt switch。

## Baseline 测试

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MemoryReflectModelsTests' '-only-testing:OpenChatTests/MigrationTests' '-only-testing:OpenChatTests/DatabaseManagerMemoryTests' '-only-testing:OpenChatTests/MemoryManagerRetrievalTests' '-only-testing:OpenChatTests/VectorStoreTests'
```

## 写回要求

- Source：baseline 阶段不改 source。
- Docs：如果读取发现 arch 当前事实漂移，实施时写回，但不能把计划写成已实现。
- Harness：记录 baseline 命令、结果、xcresult 路径和 dirty worktree inventory。

## 2026-05-18 Closeout note

- 已实现 `v17_create_memory_entry_link`、`MemoryEntryLinkRecord`、link DB API、reflect parser/executor、manual MemoryList review/apply 和 `MemoryManager.applyReflectObservation(...)`。
- 实际测试落点追加在现有 target-backed suites：`MemoryReflectModelsTests`、`VectorStoreTests`、`DatabaseManagerMemoryTests`、`MigrationTests`、`AgentPolicyTests`。
- Lead focused closeout 结果：84 tests / 5 suites passed；alternate simulator full suite 结果：360 tests / 66 suites passed。
- 仍未实现：idle/background 自动 reflect、duplicate 自动删除、冲突自动解决和 XCUITest 端到端点击路径。
