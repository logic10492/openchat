# 07. 测试与验收

## Baseline

实施前先确认工作区和当前测试状态：

```bash
git status --short
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MigrationTests' '-only-testing:OpenChatTests/VectorStoreTests' '-only-testing:OpenChatTests/PromptAssemblerTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests'
```

如 `iPhone 17 Pro` 不存在：

```bash
xcrun simctl list devices available | rg 'iPhone'
```

## Phase Focused Tests

| 阶段 | 必跑测试 |
|---|---|
| A | `MigrationTests`, `WorldBookVectorStoreTests` |
| B | `WorldBookEmbeddingTextBuilderTests`, `WorldBookEntryHasherTests`, `WorldBookEmbeddingIndexerTests` |
| C | `WorldBookSourceTests`, `PromptAssemblerTests`, `ChatViewModelPromptAssemblyTests` |
| D | `WorldBookEditorViewModelTests`, `DatabaseManagerWorldBookTests`, `CriticalSaveFlowTests` |
| Closeout | full suite |

## 最终 Focused Command

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MigrationTests' '-only-testing:OpenChatTests/WorldBookVectorStoreTests' '-only-testing:OpenChatTests/WorldBookEmbeddingTextBuilderTests' '-only-testing:OpenChatTests/WorldBookEntryHasherTests' '-only-testing:OpenChatTests/WorldBookEmbeddingIndexerTests' '-only-testing:OpenChatTests/WorldBookSourceTests' '-only-testing:OpenChatTests/PromptAssemblerTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests' '-only-testing:OpenChatTests/WorldBookEditorViewModelTests' '-only-testing:OpenChatTests/DatabaseManagerWorldBookTests' '-only-testing:OpenChatTests/CriticalSaveFlowTests'
```

## Full Suite

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

## 必须覆盖的行为

- v15/v16 migration 创建表和 columns。
- migration 不引用 runtime Record / enum / service 常量。
- `WorldBookVectorStore.search` 只返回当前 worldBook 范围内的 entry。
- embedding text 包含 title、keywords、content。
- content hash 在 title/keywords/content 变化时变化，在 priority/isEnabled/position 变化时不变化。
- migration 后已有 `world_book_entry` 可被 `rebuildAllMissingOrStale` 向量化。
- stale meta 可被 rebuild 更新。
- 单条 embedding 失败不会删除 entry。
- keyword-only、semantic-only、keyword+semantic 都能进入 recall result。
- disabled worldBook / disabled entry 不进入 recall result。
- semantic unavailable fallback 到 keyword-only。
- `[World Book Entries]` block 标签和基本格式保持兼容。
- `preview` 和 `assemble` 使用同一批 worldBook recalled entries。
- save / import 能维护或标记 rebuild embedding。
- delete entry / delete worldBook / eraseAllData 不留下 embedding/meta 残留。

## 文档写回

实施后至少同步：

- `arch/data-model.md`：新增 world book embedding/meta 表。
- `arch/modules/world-book.md`：世界书向量化后的 CRUD/import/rebuild 行为。
- `arch/modules/background/world-book-vectorization.md`：从 target planning 更新为 current source reality + 后续 Background 边界。
- `arch/modules/background/sources.md`：WorldBookSource keyword + semantic 当前契约。
- `arch/modules/prompt-assembly.md`：说明第一阶段仍输出 `[World Book Entries]`，但候选可来自 WorldBookSource。
- `.github/instructions/prompt-engine.instructions.md`：如果 PromptAssembler 不再内部做 keyword-only trigger，必须同步规则，避免未来 agent 按旧约束改回去。
- `arch/AntiEntropy/triangle-consistency.md`：记录 source / arch / test 三边一致性。
- `arch/AntiEntropy/propagation-audit.md`：记录 schema、Core/WorldBook、Chat prompt path 的传播影响。

## Harness Closeout

建议新增：

```text
harness/2026.05.16/world-book-vectorization/index.md
harness/2026.05.16/world-book-vectorization/evidence.txt
```

`index.md` 至少记录：

- 完成部分。
- 实现证据：文件路径 + 关键测试。
- 未完成部分。
- 未完成原因。
- BackgroundWorker 明确未切换。

`evidence.txt` 记录：

- focused test 命令与结果。
- full suite 命令与结果。
- 如有 baseline failure，标明不是本轮回归并附具体失败。

## 完成定义

- 现有已导入世界书可以通过 Core rebuild 或 Data Management 手动入口完成向量化。
- 当前聊天 prompt 可注入 semantic-only 世界书条目。
- Prompt 文本仍兼容 `[World Book Entries]`。
- CRUD/import/delete/eraseAllData 不产生 orphan embedding。
- 文档没有把 Future Background 目标写成已实现。
- focused tests 与 full suite 通过；或 baseline failure 被清晰记录在 harness evidence。
