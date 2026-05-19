# 05. Phase 5C：低频入口、Review 与 Apply

## 目标

把 5B 产生的 observation draft 通过用户确认或 audited apply 写入 Memory，形成可召回、可追踪的新 observation。

第一版以手动入口为主。Idle / background trigger 只做边界，不默认启用真实 LLM。

## Apply 数据流

```text
MemoryReflectObservation draft
  -> user review confirms
  -> create MemoryEntryRecord
  -> embeddingService.embed(observation.content)
  -> create MemoryEntryLinkRecord per basedOn id
  -> atomic write entry + embedding + links
  -> reload memory list
```

原始 memories 默认保留。

## Apply 规则

- `suggestedAction == insertObservation`
  - 允许进入 confirm/apply。
  - 写入 `memory_entry.memoryType` 使用 observation 的 `memoryType`。
  - importance 第一版使用保守默认值，例如 60，或基于 confidence 映射但需要测试。
- `suggestedAction == markDuplicate`
  - 第一版只展示 review，不自动删除。
  - 可以创建 `duplicates` link，但不删除被标记 memory，除非另有用户确认 flow。
- `suggestedAction == needsUserReview`
  - 不自动写 memory。
  - 只显示 draft / error / review 状态。

## 原子写入

必须保证：

```text
memory_entry
memory_embedding
memory_entry_link
```

同一 transaction 成功或失败。不能留下：

- 只有 `memory_entry` 没有 embedding。
- 只有 observation 没有 basedOn link。
- link 指向不存在的 source memory。

## UI / ViewModel

优先落在 memory 管理界面：

- `MemoryListViewModel`
  - reflect state：idle / running / draft / applying / failed。
  - selected source ids 或从当前 filtered list 中选择。
  - `runReflect(task:sourceIds:)`
  - `applyReflectObservation(...)`
- `MemoryListView`
  - “整理记忆”入口。
  - draft preview。
  - confirm / cancel。
  - error visible。

如果第一版不做复杂多选，可以先支持：

```text
用户选中 2-5 条 memory -> 整理 -> 预览 -> 确认写入
```

无 source selection 时不应调用 LLM。

## 本地化

所有新增用户可见文案必须写入：

```text
OpenChat/Resources/Localizable.xcstrings
```

不要在 View 中硬编码中文或英文 UI 文案。

## 低频 trigger 边界

第一版可以只保留 contract：

```text
MemoryReflectScheduler
  -> decides eligible clusters
  -> returns pending task
```

但不要默认后台自动调用真实 LLM。启用条件需要后续单独确认：

- 用户明确打开自动整理。
- 网络 / API key / endpoint 可用。
- App idle。
- 不影响发送消息延迟。
- 可见 diagnostics 或 history。

## Tests

新增或更新：

- `MemoryReflectModelsTests`
  - applies insertObservation atomically。
  - embedding failure rolls back entry and links。
  - link write failure rolls back entry and embedding。
  - rejects basedOn ids outside source ids。
  - rejects markDuplicate auto delete。
- `VectorStoreTests`
  - if vector store gains entry+embedding+links helper。
- `MemoryListViewModel` coverage appended to `MemoryReflectModelsTests`
  - run reflect success -> draft state。
  - parser/executor failure -> visible error state。
  - apply success -> list reload includes observation。
  - apply failure -> error visible and draft retained。

实际实现未新增独立 Swift test file；测试追加在现有 target-backed suites，避免 Xcode project membership churn。

## 红线

- 不让失败被静默吞掉。
- 不在 confirm 前写 DB。
- 不自动删除 duplicates。
- 不在 Chat 发送时触发。
- 不把 draft 当普通 assistant message 存入 `message` table。
- 不为了 UI 方便绕过 `MemoryManager` / service 注入。

## 验收命令

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MemoryReflectModelsTests' '-only-testing:OpenChatTests/VectorStoreTests' '-only-testing:OpenChatTests/DatabaseManagerMemoryTests'
```

## 写回要求

- `arch/modules/memory/ui-management.md` 记录手动整理入口和 review 边界。
- `arch/modules/memory/index.md` 更新当前 Memory 流程。
- `arch/modules/memory/hindsight-lite.md` 更新 reflect executor / apply 实现证据。
- `PLANING.md` Phase 5 状态只在完成并验证后改为已完成。
