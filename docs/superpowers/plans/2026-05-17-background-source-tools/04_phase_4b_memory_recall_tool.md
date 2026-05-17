# 04. Phase 4B - MemoryRecallTool

## 目标

新增 `MemoryRecallTool`，只包装当前 `MemoryManager.recallMemories(...)`。

目标链路：

```text
MemoryRecallTool.call(input)
  -> MemoryManager.recallMemories(for:query:limit:)
  -> MemoryRecallResult
```

## 建议文件

```text
OpenChat/Core/Memory/MemoryRecallTool.swift
OpenChatTests/Core/MemoryTests/MemoryRecallToolTests.swift
```

## 建议 input

```swift
struct MemoryRecallToolInput: Sendable {
    let characterCardId: String
    let query: String
    let limit: Int
}
```

output 可以直接是 `MemoryRecallResult`。如需要统一 tool envelope，可用：

```swift
struct MemoryRecallToolOutput: Sendable {
    let result: MemoryRecallResult
    let diagnostics: BackgroundToolDiagnostics
}
```

不要为了统一 envelope 改 `MemoryRecallResult` 本身，除非有明确必要。

## 实现要求

- 调用 `MemoryManager.recallMemories(...)`。
- 保持 `MemoryRecallResult.entries` 顺序。
- 保持 `trace.selectedIds`、`trace.omitted`、`trace.fallback`。
- 不调用 `retrieveMemories(...)`，因为它丢失 trace。
- 不重新计算 embedding。
- 不重新排序。
- 不按 importance 裁剪。
- 不写数据库。
- 不生成 prompt text。

## 测试要求

focused tests 至少覆盖：

- tool 调用后 entries 顺序等于 fake / stub `MemoryRecallResult.entries` 顺序。
- `semanticRank`、`semanticDistance`、`keywordRank`、`recencyRank`、`reasons` 保留。
- `trace.fallback`、`trace.omitted`、candidate counts 保留。
- limit 为 0 时透传当前 `recallMemories(...)` 的 empty result 行为。
- tool 本身没有 DB write / extraction / retain side effect。

测试实现可以优先用一个轻量 protocol seam 包装 `MemoryManager.recallMemories(...)`，避免真实 embedding / sqlite-vec 让工具测试变慢。不要为了测试重写 MemoryManager 的排序逻辑。

## 验收命令

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MemoryRecallToolTests' '-only-testing:OpenChatTests/MemoryManagerRetrievalTests'
```

如果 suite discovery 名称不匹配，记录实际命令。

## 文档写回

更新：

- `arch/modules/background/migration-plan.md`
- `arch/modules/background/architecture.md`
- `arch/modules/memory/index.md`
- `arch/modules/memory/retrieval-prompt.md` 如涉及 recall contract

必须明确：

- MemoryRecallTool 已实现时，只代表 source tool 暴露完成。
- BackgroundWorker / BackgroundPacket / prompt switch 仍未实现。
