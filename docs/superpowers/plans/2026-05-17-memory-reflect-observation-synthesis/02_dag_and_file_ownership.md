# 02. DAG 与文件归属

## DAG

```text
S0 baseline read + dirty worktree inventory
  -> 5A memory_entry_link persistence
  -> 5B reflect executor + structured parser
  -> 5C manual/low-frequency entry + review apply
  -> closeout docs + harness + full suite
```

## 并行窗口

可以并行：

- 5A migration / record 草案和 5B parser schema 草案可以并行审阅。
- 5B executor request-shape tests 可以先写 red tests，但 apply 逻辑需等 5A DB API 稳定。
- 5C UI 文案和 ViewModel 状态草案可以先列 key，但不得提前把 UI 写成已实现。

不可并行：

- `memory_entry_link` 未完成前，不实现 apply observation 写库。
- parser validation 未完成前，不接真实 API response。
- apply atomicity 未测试前，不加用户确认入口。
- 手动入口未完成前，不开启 idle/background trigger。

## 文件归属

| 阶段 | 允许 source | 测试 | 文档写回 |
|---|---|---|---|
| 5A Link persistence | 计划：`OpenChat/Core/Database/Migrations.swift`、link record、`OpenChat/Core/Database/DatabaseManager+Memory.swift`；实际：`MemoryEntryLinkRecord` 追加在 `MemoryEntryProvenanceRecord.swift` | `OpenChatTests/Core/DatabaseTests/MigrationTests.swift`、`DatabaseManagerMemoryTests.swift`、`MemoryReflectModelsTests.swift` | `arch/modules/memory/data-model.md`、`hindsight-lite.md` |
| 5B Reflect executor | 计划：独立 executor/parser/prompt builder 文件；实际：为避免 Xcode project churn，追加到 target-backed `OpenChat/Core/Memory/MemoryReflectModels.swift`，并扩展 `MemoryError.swift`、`AgentPolicy.swift` | 实际追加到 `OpenChatTests/Core/MemoryTests/MemoryReflectModelsTests.swift` 和 `AgentPolicyTests.swift` | `arch/modules/memory/hindsight-lite.md`、`testing.md` |
| 5C Entry / review apply | 实际：`MemoryManager.swift`、`VectorStore.swift`、`MemoryDependencies.swift`、`MemoryListViewModel.swift`、`MemoryListView.swift`、`CharacterCardDetailView.swift`、`DependencyContainer.swift`、`Localizable.xcstrings` | 实际追加到 `MemoryReflectModelsTests.swift`、`VectorStoreTests.swift`、`DatabaseManagerMemoryTests.swift` | `arch/modules/memory/ui-management.md`、`index.md`、`PLANING.md` |

## 禁改面

Phase 5 禁止修改：

- `OpenChat/Features/Chat/ViewModels/ChatViewModel+Support.swift`
- `OpenChat/Core/PromptEngine/PromptAssembler.swift`
- `OpenChat/Core/Background/BackgroundWorker.swift`
- `OpenChat/Core/Background/BackgroundAssembler.swift`
- `OpenChat/Core/WorldBook/*`
- `OpenChat/Core/Networking/ResponsesAPIRequest.swift`，除非 executor request-shape 发现真实 bug 且有 focused tests。
- `scripts/generate_xcodeproj.rb`，除非新增 files 没有进入 Xcode target 且用户同意按生成器规则更新。
- 签名配置。

## 需审批面

以下情况必须停下来请用户确认：

- 新增 DB migration 之外还要修改既有 migration。
- 需要让 reflect 自动删除、覆盖或合并原始 memory。
- 需要每轮聊天自动调用 reflect。
- 需要后台 idle trigger 在无用户操作时调用真实 LLM。
- 需要新增 long-running background task / notification 权限。
- 需要修改 `scripts/generate_xcodeproj.rb`。
- 需要改变 API request provider shape。

## Xcode project 规则

新增 Swift 文件后：

1. 优先确认当前 project 是否由脚本生成并已包含 glob。
2. 如 target membership 缺失，运行：

```bash
ruby scripts/generate_xcodeproj.rb
```

3. 生成后的 `OpenChat.xcodeproj` diff 只能包含新文件 target membership / scheme 变化，不得漂移签名配置。

## 完成定义

- 每个阶段只改自己的 ownership 面。
- 5A closeout 前，`MigrationTests` 与 DB memory tests 通过。
- 5B closeout 前，executor 可在 mock API 下返回 validated draft，不写 DB。
- 5C closeout 前，apply observation 原子写入并创建 links；UI 或 ViewModel 能展示失败。
- docs / harness 记录命令、结果、未运行原因和剩余风险。

## 推荐 staging 边界

如果拆 commit：

```text
commit 1: memory_entry_link schema + DB tests
commit 2: reflect executor + parser tests
commit 3: review/apply entry + UI/ViewModel tests + docs
```

如果当前工作区有 unrelated dirty files，只 stage Phase 5 文件。
