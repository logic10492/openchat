# 06. Testing Acceptance

## 分阶段测试矩阵

| 阶段 | 必跑 focused tests | 目的 |
|---|---|---|
| S0 | `MemoryReflectModelsTests`、`MigrationTests`、`DatabaseManagerMemoryTests`、`MemoryManagerRetrievalTests`、`VectorStoreTests` | 确认当前 Memory / DB / reflect contract 基线 |
| 5A | `MigrationTests`、`DatabaseManagerMemoryTests`、`MemoryReflectModelsTests` | link schema / FK / DB API |
| 5B | 实际：`MemoryReflectModelsTests`、`AgentPolicyTests` | structured parser / mock API / policy |
| 5C | 实际：`MemoryReflectModelsTests`、`VectorStoreTests`、`DatabaseManagerMemoryTests` | apply atomicity / UI state |
| Closeout | focused Memory / DB / AgentPolicy suite；full suite | 回归验证 |

## Baseline command

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MemoryReflectModelsTests' '-only-testing:OpenChatTests/MigrationTests' '-only-testing:OpenChatTests/DatabaseManagerMemoryTests' '-only-testing:OpenChatTests/MemoryManagerRetrievalTests' '-only-testing:OpenChatTests/VectorStoreTests'
```

## Phase 5A command

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MigrationTests' '-only-testing:OpenChatTests/DatabaseManagerMemoryTests' '-only-testing:OpenChatTests/MemoryReflectModelsTests'
```

## Phase 5B command

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MemoryReflectModelsTests' '-only-testing:OpenChatTests/AgentPolicyTests'
```

## Phase 5C command

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MemoryReflectModelsTests' '-only-testing:OpenChatTests/VectorStoreTests' '-only-testing:OpenChatTests/DatabaseManagerMemoryTests'
```

## Phase 5 closeout focused command

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MemoryReflectModelsTests' '-only-testing:OpenChatTests/VectorStoreTests' '-only-testing:OpenChatTests/DatabaseManagerMemoryTests' '-only-testing:OpenChatTests/MigrationTests' '-only-testing:OpenChatTests/AgentPolicyTests'
```

## Full suite

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

2026-05-18 实际 closeout：focused command 84 tests / 5 suites passed；default simulator full suite launch failed with simulator Busy before tests; alternate simulator full suite passed 360 tests / 66 suites。

Simulator fallback：

```bash
xcrun simctl list devices available | rg 'iPhone'
```

## 必须新增或更新的测试主题

- `memory_entry_link` migration 只追加，不修改旧 migration。
- link FK cascade。
- relation validation。
- fetch links by source and target。
- parser rejects invalid basedOn。
- parser rejects unknown relation/action/type。
- executor rejects source memory from another character。
- executor mock request shape stable。
- executor does not write DB。
- apply observation writes entry + embedding + links atomically。
- embedding failure rolls back。
- duplicate action does not auto delete original memory。
- UI/ViewModel failure visible, if UI phase is implemented.

## 验收红线

以下任一发生即不能 closeout：

- 每轮 Chat 发送触发 reflect。
- LLM output 未经 parser validation 就写库。
- observation 没有 basedOn link。
- 原始 memory 被静默删除、覆盖或替代。
- `memory_entry` 写入成功但 embedding 或 link 缺失。
- 新 migration 修改了 v1-v16。
- UI 文案硬编码到 View。
- 文档把 idle/background 自动整理写成已启用，但源码只做了手动入口。
- Xcode project 签名配置漂移。

## Docs / Harness closeout

完成后同步：

- `arch/modules/memory/index.md`
- `arch/modules/memory/data-model.md`
- `arch/modules/memory/hindsight-lite.md`
- `arch/modules/memory/testing.md`
- `arch/modules/memory/ui-management.md`，如果做了 UI。
- `PLANING.md`
- `harness/<date>/memory-reflect-observation-synthesis/index.md`
- `harness/<date>/memory-reflect-observation-synthesis/evidence.txt`

Harness 必须记录：

- dirty worktree inventory。
- 每条测试命令。
- suite / test count。
- xcresult 路径。
- NOT RUN / blocked 原因。
- 未完成项和用户确认边界。
