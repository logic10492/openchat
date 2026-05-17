# 05. Phase 4C - WorldBookRecallTool

## 目标

新增 `WorldBookRecallTool`，只包装当前 `WorldBookSource.recallEntries(...)`。

目标链路：

```text
WorldBookRecallTool.call(input)
  -> WorldBookSource.recallEntries(...)
  -> WorldBookRecallResult
```

## 建议文件

```text
OpenChat/Core/WorldBook/WorldBookRecallTool.swift
OpenChatTests/Core/WorldBookTests/WorldBookRecallToolTests.swift
```

## 建议 input

```swift
struct WorldBookRecallToolInput: Sendable {
    let worldBook: WorldBookRecord?
    let entries: [WorldBookEntryRecord]
    let recentMessages: [MessageRecord]
    let currentInput: String
    let limit: Int
}
```

output 可以直接是 `WorldBookRecallResult`。如需要统一 envelope，可用：

```swift
struct WorldBookRecallToolOutput: Sendable {
    let result: WorldBookRecallResult
    let diagnostics: BackgroundToolDiagnostics
}
```

## 实现要求

- 调用 `WorldBookSource.recallEntries(...)`。
- 保持 `WorldBookRecallResult.entries` 顺序。
- 保持 keyword / semantic rank、distance、hits、reasons。
- 保持 `trace.omissions`，包括 `semanticUnavailable`、`duplicate`、`staleEmbedding`、`disabled`、`limitExceeded`。
- 不调用 `WorldBookEmbeddingIndexer`。
- 不触发 missing/stale rebuild。
- 不复制 `WorldBookSource` 的 keyword + semantic fusion。
- 不改 `[World Book Entries]` block。

## 世界书 rebuild 边界

当前世界书 rebuild 属于这些路径：

- CRUD / import 后 index。
- delete / eraseAllData 时清理 vector/meta。
- Settings 手动 rebuild。
- 当前 Chat 召回前的 bounded lazy rebuild 兼容链路。

`WorldBookRecallTool` 不新增 rebuild 行为。后续如要迁移 bounded lazy rebuild 到 BackgroundManager，必须单独设计 side-effect boundary，不能让 BackgroundWorker 自己触发。

## 测试要求

focused tests 至少覆盖：

- keyword-only result 顺序透传。
- semantic-only result 顺序透传。
- keyword + semantic hybrid result 顺序透传。
- disabled world book / disabled entry 行为透传。
- semantic unavailable fallback trace 透传。
- stale embedding omission 透传。
- tool 不调用 indexer / rebuild。

测试实现可用 fake `WorldBookSource` protocol seam，避免工具测试依赖真实 CoreML embedding。不要把 fusion 逻辑搬进 fake 后再测 fake 的排序。

## 验收命令

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/WorldBookRecallToolTests' '-only-testing:OpenChatTests/WorldBookSourceTests'
```

## 文档写回

更新：

- `arch/modules/background/migration-plan.md`
- `arch/modules/background/world-book-vectorization.md`
- `arch/modules/world-book.md`

必须明确：

- WorldBookRecallTool 已实现时，只代表 source tool 暴露完成。
- BackgroundWorker 统一调度仍未实现，prompt 兼容输出仍不变。
