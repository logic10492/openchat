# 07. New Thread Handoff

## 当前任务

执行 `PLANING.md` 中 Phase 5：低频 reflect / observation synthesis。2026-05-18 当前 handoff 状态：Phase 5 手动入口、executor、link persistence 和 apply 已完成 focused closeout；本文件保留执行路线和真实 closeout 命令。

计划包：

```text
docs/superpowers/plans/2026-05-17-memory-reflect-observation-synthesis/
```

## 当前边界

只做 Memory 层低频整理，不做：

- Director。
- 多角色同场。
- Stage。
- UI automation target。
- LibMan。
- 每轮 Chat 自动 reflect。
- 统一 `[Background]` block。

## 已知前置事实

- `MemoryReflectModels.swift` 和 `MemoryReflectModelsTests.swift` 已存在，并已承载 parser/executor/apply/ViewModel 测试。
- `memory_entry_provenance` 已存在。
- `memory_entry_link` 已通过 `v17_create_memory_entry_link` 实现。
- BackgroundPacket chat/prompt compatible switch 已完成。
- `PLANING.md` 已将 Phase 5 排在 Director / Stage 之前，LibMan 排到最后。

## 执行顺序

```text
S0 baseline read + dirty worktree inventory
  -> 5A memory_entry_link persistence
  -> 5B reflect executor + structured parser
  -> 5C manual/low-frequency entry + review apply
  -> closeout docs + harness + focused suite
```

## 开始前必须运行

```bash
git status --short --branch
```

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MemoryReflectModelsTests' '-only-testing:OpenChatTests/MigrationTests' '-only-testing:OpenChatTests/DatabaseManagerMemoryTests' '-only-testing:OpenChatTests/MemoryManagerRetrievalTests' '-only-testing:OpenChatTests/VectorStoreTests'
```

## 必须读取

- `AGENTS.md`
- `PLANING.md`
- 本计划包全部文件。
- `arch/modules/memory/index.md`
- `arch/modules/memory/data-model.md`
- `arch/modules/memory/hindsight-lite.md`
- `OpenChat/Core/Memory/MemoryReflectModels.swift`
- `OpenChat/Core/Memory/MemoryManager.swift`
- `OpenChat/Core/Database/Migrations.swift`
- `OpenChat/Core/Database/DatabaseManager+Memory.swift`
- `OpenChat/Core/Memory/VectorStore.swift`
- `OpenChat/App/DependencyContainer.swift`
- `OpenChat/Features/CharacterCard/ViewModels/MemoryListViewModel.swift`

## Dirty worktree 注意

当前交接时工作区可能已有 unrelated Chat / Xcode / test dirty files。执行 Phase 5 时：

- 不要 revert 用户已有改动。
- 不要把 unrelated dirty files 混进 Phase 5 commit。
- 触碰 `OpenChat.xcodeproj` 前确认是否来自生成脚本。
- 如果同一文件已有用户改动，先读 diff 再局部编辑。

## 完成时必须写回

- Source / tests。
- `arch/modules/memory/*` 对应事实。
- `PLANING.md` Phase 5 状态。
- `harness/<date>/memory-reflect-observation-synthesis/index.md`
- `harness/<date>/memory-reflect-observation-synthesis/evidence.txt`

## Closeout 命令

Focused：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MemoryReflectModelsTests' '-only-testing:OpenChatTests/VectorStoreTests' '-only-testing:OpenChatTests/DatabaseManagerMemoryTests' '-only-testing:OpenChatTests/MigrationTests' '-only-testing:OpenChatTests/AgentPolicyTests'
```

2026-05-18 focused 结果：84 tests / 5 suites passed。默认 simulator full suite launch 遇到 Busy，alternate simulator `id=F8D0D88B-71FD-471F-855A-B2B5D8267117` full suite 通过 360 tests / 66 suites。

Full suite：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

If simulator is unavailable：

```bash
xcrun simctl list devices available | rg 'iPhone'
```
