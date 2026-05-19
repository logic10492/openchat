# Memory Reflect Observation Synthesis

> 日期：2026-05-18
> 范围：`docs/superpowers/plans/2026-05-17-memory-reflect-observation-synthesis/`
> 状态：已完成 Phase 5 focused closeout。本文件记录修改前传播审计、实现证据、验证结果和未完成边界。

## 1. 修改前传播审计

本轮修改源码前已完成三条只读传播审计 lane：

| Lane | 范围 | 结论 |
|---|---|---|
| A | Memory DB / VectorStore 持久化 | `memory_entry_link` 尚不存在；当前最新 migration 是 `v16_create_world_book_entry_embedding_meta`；5A 必须只追加 `v17_create_memory_entry_link`，不改 v1-v16。原子写入应落在 `VectorStore`，避免在 `DatabaseManager` 复制 sqlite-vec blob 细节。 |
| B | Reflect executor / API / parser | 可复用 `APIClient.sendMessage(messages:endpoint:parameters:)`；5B 不需要改 provider request shape、`ResponsesAPIRequest`、Chat 主链路或 Prompt block。`basedOn` 子集验证必须在 parser/executor 层完成。 |
| C | Memory management UI / ViewModel / docs | `MemoryListViewModel` 当前只有 load/delete/deleteAll 状态；5C 若做手动入口，需要新增 selection、draft/apply/error 状态、本地化文案和 ViewModel tests。Docs 不得把 idle/background 自动整理或 duplicate 自动删除写成已实现。 |

## 2. 当前 Dirty Worktree Inventory

实施前已有 unrelated dirty files，本轮不得回滚或混入 Phase 5 逻辑判断：

```text
 M OpenChat.xcodeproj/project.pbxproj
 M OpenChat.xcodeproj/xcshareddata/xcschemes/OpenChat.xcscheme
 M OpenChat/Features/Chat/Models/MessageDisplayItem.swift
 M OpenChat/Features/Chat/ViewModels/ChatViewModel+Support.swift
 M OpenChat/Features/Chat/Views/ChatView.swift
 M OpenChat/Features/Chat/Views/MessageBubbleView.swift
 M OpenChat/Shared/Components/MarkdownTextView.swift
 M PLANING.md
 M arch/modules/chat.md
?? OpenChatTests/Features/ChatTests/StreamingRenderSegmentationTests.swift
?? comp_swap/
?? docs/superpowers/plans/2026-05-17-memory-reflect-observation-synthesis/
```

## 3. 受影响代码块

5A link persistence：

- `OpenChat/Core/Database/Migrations.swift`：只追加 `v17_create_memory_entry_link`。
- `OpenChat/Core/Database/Records/MemoryEntryProvenanceRecord.swift` 或新增 target-backed record 文件：定义 `MemoryEntryLinkRecord`。
- `OpenChat/Core/Database/DatabaseManager+Memory.swift`：link save/fetch/validation API。
- `OpenChatTests/Core/DatabaseTests/MigrationTests.swift`
- `OpenChatTests/Core/DatabaseTests/DatabaseManagerMemoryTests.swift`
- `OpenChatTests/Core/MemoryTests/MemoryReflectModelsTests.swift`

5B reflect executor：

- `OpenChat/Core/Memory/MemoryReflectModels.swift` 或新增 target-backed reflect files：parser / prompt builder / executor / diagnostics。
- `OpenChat/Core/Memory/MemoryError.swift`
- 可选：`OpenChat/Core/AgentCore/AgentPolicy.swift` 与 `AgentPolicyTests.swift`，仅落 policy contract 时修改。
- `OpenChatTests/Core/MemoryTests/MemoryReflectModelsTests.swift` 或新增 target-backed tests。

5C apply / review entry：

- `OpenChat/Core/Memory/VectorStore.swift`：entry + embedding + links 同 transaction 写入。
- `OpenChat/Core/Memory/MemoryManager.swift` 或 target-backed extension：apply confirmed observation。
- `OpenChat/Features/CharacterCard/ViewModels/MemoryListViewModel.swift`
- `OpenChat/Features/CharacterCard/Views/MemoryListView.swift`
- `OpenChat/Features/CharacterCard/Views/CharacterCardDetailView.swift` / `OpenChat/App/DependencyContainer.swift`，仅在需要 DI seam 时修改。
- `OpenChat/Resources/Localizable.xcstrings`
- 实际测试追加到 target-backed `MemoryReflectModelsTests.swift`、`VectorStoreTests.swift` 和 `DatabaseManagerMemoryTests.swift`，未新增独立 `MemoryListViewModelTests` 文件。

## 4. 禁改面

- 不修改 v1-v16 migration。
- 不修改 `ChatViewModel+Support.swift`、`PromptAssembler.swift`、`BackgroundWorker.swift`、`MemoryBackgroundSource.swift`、`WorldBookBackgroundSource.swift`。
- 不修改 `ResponsesAPIRequest.swift` 或 API provider request shape。
- 不接 Exa / LibMan / web search。
- 不让 reflect 进入每轮 Chat send path。
- 不让 reflect 自动删除、覆盖或替代原始 memories。
- 不修改签名配置或 `scripts/generate_xcodeproj.rb`。

## 5. 并行执行窗口

第一波可并行：

- 5A DB/link persistence worker。
- 5B parser/executor worker。

第二波依赖 5A + 5B：

- 5C apply / manual review entry worker。

Lead closeout：

- 合并 worker 结果。
- 更新 `arch/modules/memory/*`、`arch/data-model.md`、`PLANING.md`。
- 记录 focused / full suite 结果到本目录 `evidence.txt`。

## 6. 当前未运行命令

本文件初次写入时尚未运行 Phase 5 baseline / focused tests；实际执行证据已追加到 `evidence.txt`。

## 7. 实施结果

| Phase | 状态 | 实现摘要 |
|---|---|---|
| 5A DB/link persistence | Done | 追加 `v17_create_memory_entry_link`；新增 `MemoryEntryLinkRecord`、link save/fetch/validation、schema/index/cascade/dedupe tests。 |
| 5B reflect executor | Done | 新增 `MemoryReflectPromptBuilder`、`MemoryReflectParser`、`MemoryReflectExecutor`、diagnostics、typed errors 和 `AgentPolicy.reflectDefault()`；executor 只返回 draft，不写 DB。 |
| 5C manual review/apply | Done | 新增 `VectorStore.insert(entry:embedding:links:)`、`MemoryManager.applyReflectObservation(...)`、Memory 管理页选择 2-5 条、draft preview、Apply/Cancel、visible errors 和 Localizable keys。 |
| Docs / harness closeout | Done | 更新 memory arch docs、`arch/data-model.md`、`PLANING.md`、`arch/AntiEntropy/propagation-audit.md` 与本 harness。 |

## 8. 最终验证

Lead focused closeout：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MemoryReflectModelsTests' '-only-testing:OpenChatTests/VectorStoreTests' '-only-testing:OpenChatTests/DatabaseManagerMemoryTests' '-only-testing:OpenChatTests/MigrationTests' '-only-testing:OpenChatTests/AgentPolicyTests'
```

结果：84 tests / 5 suites passed，`** TEST SUCCEEDED **`。

xcresult：

```text
/Users/fukujusou/Library/Developer/Xcode/DerivedData/OpenChat-fiicdnsnwoygvnahvbxvezbhtsfy/Logs/Test/Test-OpenChat-2026.05.18_01-21-54-+0800.xcresult
```

其他检查：

- `git diff --check`：PASS。
- `python3 -m json.tool OpenChat/Resources/Localizable.xcstrings >/dev/null`：PASS。
- Full suite：默认 iOS 26.5 `iPhone 17 Pro` destination 在 launch 阶段遇到 simulator Busy：`Application failed preflight checks`，未进入测试断言。改用 alternate simulator `id=F8D0D88B-71FD-471F-855A-B2B5D8267117` 后通过 360 tests / 66 suites。

## 9. 未完成边界

- 未启用 idle/background 自动 reflect。
- 未实现 duplicate 自动删除、旧记忆覆盖或 conflict 自动解决。
- 未实现 duplicate/conflict 专用 review UI。
- 未启用统一 `[Background]` block。
- 未新增 XCUITest 端到端点击 MemoryList reflect flow。
