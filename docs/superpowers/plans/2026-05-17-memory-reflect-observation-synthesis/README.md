# OpenChat Phase 5 Memory Reflect / Observation Synthesis 计划包

> 生成日期：2026-05-17
> 范围：Phase 5 低频 reflect / observation synthesis 计划与执行记录。
> 状态：2026-05-18 已完成手动入口、reflect executor、`memory_entry_link` 持久化和 review/apply focused closeout；idle/background 自动整理仍未实现。

## 目标

本计划包把 Phase 5 限定为 Memory 层的低频整理能力：

```text
source memories
  -> MemoryReflectRequest
  -> LLM structured synthesis
  -> MemoryReflectObservation draft
  -> user-reviewed or audited apply
  -> memory_entry + memory_embedding + memory_entry_link
```

Phase 5 的核心不是把聊天主链路变复杂，而是让已有长期记忆可以被低频整理、总结、去重和关系观察，同时保留来源证据。

## 硬性边界

- 不在每轮 `ChatViewModel.generateResponse(...)` 中调用 reflect。
- 不让 reflect 生成 assistant message。
- 不让 reflect 静默覆盖、删除或替代原始 memory。
- 不修改 `PromptAssembler` 默认 prompt block。
- 不迁移到统一 `[Background]` block。
- 不实现 Director、Stage、多角色同场或 UI 自动化。
- 不接 Exa / LibMan / web search。
- 不改签名配置。
- 需要 schema 时只追加新 migration，不修改既有 migration。

## 当前已存在能力

- `OpenChat/Core/Memory/MemoryReflectModels.swift`
  - `MemoryReflectRequest`
  - `MemoryReflectObservation`
  - `MemoryReflectTask`
  - `MemoryReflectAction`
  - `MemoryEntryLinkRelation`
- `OpenChatTests/Core/MemoryTests/MemoryReflectModelsTests.swift`
  - 已覆盖 source ids / basedOn ids 非空、confidence clamp、task/action/relation raw values。
- `memory_entry_provenance` 已存在，记录 retain v2 source metadata。
- `MemoryRecallTool` / `MemoryBackgroundSource` / `BackgroundWorker` / `BackgroundPacket` 已让 Memory recall 进入当前 Chat-Prompt 兼容链路。

## 本计划包新增范围与当前状态

1. `memory_entry_link` 持久化：已追加 `v17_create_memory_entry_link`，记录 observation 与原始 memory 的 `summarizes` / `duplicates` / `reinforces` 关系。
2. Reflect executor：已用现有 API endpoint 低频调用 LLM，输出结构化 `MemoryReflectObservation` draft，不写 DB。
3. Apply / review flow：已实现手动入口，允许用户确认后写入新 observation；`.markDuplicate` / `.needsUserReview` 默认拒绝自动 apply，不自动破坏历史证据。

## 计划文件

1. `00_source_baseline.md`：当前事实、必须读取文件、drift 风险。
2. `01_target_architecture.md`：目标架构、数据流、错误处理和非目标。
3. `02_dag_and_file_ownership.md`：DAG、文件归属、禁改面、需审批面。
4. `03_phase_5a_link_persistence.md`：`memory_entry_link` migration / record / DB API。
5. `04_phase_5b_reflect_executor.md`：LLM executor、schema parsing、diagnostics。
6. `05_phase_5c_low_frequency_entry_review.md`：手动/低频入口、review apply、UI 文案边界。
7. `06_testing_acceptance.md`：focused tests、full suite、closeout 验收。
8. `07_new_thread_handoff.md`：新 thread 交接入口。

## 推荐执行顺序

```text
S0 baseline read + dirty worktree inventory
  -> 5A memory_entry_link persistence
  -> 5B reflect executor + structured parser
  -> 5C manual/low-frequency entry + review apply
  -> docs/harness closeout
```

5A 先做，因为没有 `basedOn` 持久化就不应该让 observation 写入。5B 只产出 draft，不写库。5C 才允许把用户确认后的 draft 写成新的 memory entry 和 link。

## 基线命令

OpenChat 是 Xcode project，不是 Swift Package：

```bash
git status --short
```

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MemoryReflectModelsTests' '-only-testing:OpenChatTests/MigrationTests' '-only-testing:OpenChatTests/DatabaseManagerMemoryTests' '-only-testing:OpenChatTests/MemoryManagerRetrievalTests' '-only-testing:OpenChatTests/VectorStoreTests'
```

如果 simulator 名称不可用：

```bash
xcrun simctl list devices available | rg 'iPhone'
```

新增 Swift 文件后，如果 Xcode target membership 未更新：

```bash
ruby scripts/generate_xcodeproj.rb
```

不得手工修改签名配置；`PRODUCT_BUNDLE_IDENTIFIER`、`DEVELOPMENT_TEAM`、`CODE_SIGN_STYLE` 必须继续由 `scripts/generate_xcodeproj.rb` 管理。

## 完成定义

- `memory_entry_link` 只能追加 migration，且删除 memory 时 link 通过 FK cascade 清理。
- reflect executor 不进入每轮聊天主链路。
- LLM 输出必须经过 structured parser 和 contract validation。
- apply observation 必须写入 `memory_entry`、`memory_embedding` 和 `memory_entry_link`，不能留下半索引记忆。
- 原始 memories 默认保留； destructive change 需要 review / confirmation。
- docs / tests / harness 都明确 Phase 5 当前实现事实和未完成项。

## Closeout 结果

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MemoryReflectModelsTests' '-only-testing:OpenChatTests/VectorStoreTests' '-only-testing:OpenChatTests/DatabaseManagerMemoryTests' '-only-testing:OpenChatTests/MigrationTests' '-only-testing:OpenChatTests/AgentPolicyTests'
```

结果：84 tests / 5 suites passed。`git diff --check` 和 `Localizable.xcstrings` JSON parse 均通过。

Full suite：默认 iOS 26.5 `iPhone 17 Pro` destination 在 launch 阶段遇到 `FBSOpenApplicationServiceErrorDomain` / `Application failed preflight checks` Busy；改用 alternate simulator `id=F8D0D88B-71FD-471F-855A-B2B5D8267117` 后通过 360 tests / 66 suites。

## 写回要求

- Source：实施阶段按 `02_dag_and_file_ownership.md` 控制文件归属。
- Docs：完成后同步 `arch/modules/memory/index.md`、`data-model.md`、`hindsight-lite.md`、`testing.md`，必要时更新 `PLANING.md`。
- Harness：实施阶段新增 `harness/<date>/memory-reflect-observation-synthesis/`，记录命令、结果、xcresult、未完成项和用户确认边界。
