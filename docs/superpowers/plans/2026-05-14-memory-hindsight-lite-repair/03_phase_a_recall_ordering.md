# 03. Phase A：Recall Ordering

> 执行状态：已于 2026-05-14 落地并验证。源码证据为 `OpenChat/Core/PromptEngine/PromptAssembler.swift`，测试证据为 `OpenChatTests/Core/PromptEngineTests/PromptAssemblerTests.swift` 中的 `test_memory_trim_preserves_retrieval_order_when_budget_drops_high_importance_memory`。

## 目标

关闭 AE P1：语义检索顺序在 Prompt 注入前被 `importance` 重排。

## Baseline 问题

实施前链路：

```text
MemoryManager.retrieveMemories
  -> KNN ids
  -> fetch memories
  -> orderedEntries 按 KNN id 顺序恢复
  -> PromptAssembler.preview / assemble
  -> trim(memories:) 按 importance DESC 重排
```

这会在 memory budget 不足时让高 importance 但低相关的旧记忆挤掉当前输入更相关的记忆。Phase A 已将该行为改为按输入 retrieval order 裁剪。

## 修改点

- `OpenChat/Core/PromptEngine/PromptAssembler.swift`
  - `trim(memories:within:)` 删除 `memories.sorted(by: { $0.importance > $1.importance })`。
  - 改为按输入数组顺序累积 token。
  - 保留“至少保留第一条”的现有行为。

建议实现：

```swift
private static func trim(memories: [MemoryEntryRecord], within budget: Int) -> [MemoryEntryRecord] {
    guard !memories.isEmpty else { return [] }
    var result: [MemoryEntryRecord] = []
    var used = 0
    for entry in memories {
        let tokens = TokenCounter.count(message: ChatMessage(role: "system", content: makeMemoryMessageContent(entry)))
        guard used + tokens <= budget || result.isEmpty else { break }
        result.append(entry)
        used += tokens
    }
    return result
}
```

## 测试

新增或补强 `OpenChatTests/Core/PromptEngineTests/PromptAssemblerTests.swift`：

- 构造 memories `[A, B, C]`，importance 为 `C > B > A`。
- endpoint context budget 让 memory budget 只能容纳两条。
- 断言 `[Memories]` 中出现 A、B，不出现 C。
- 断言 A 在 B 之前。

可选 Feature 级测试：

- 在 `ChatViewModelPromptAssemblyTests` 中用 fake vector store 返回 KNN order，捕获 API request，断言 request 中 `[Memories]` 不被 importance 重排。

## 验收

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/PromptAssemblerTests'
```

完成后更新：

- `arch/modules/memory/retrieval-prompt.md`：把“当前排序风险”改为已修复证据。
- `arch/modules/memory/testing.md`：补上 order-preserving trim 测试。
- `arch/AntiEntropy/problem.md`：P1 标记 Closed，写明源码和测试证据。

执行结果：

- `PromptAssemblerTests`：14 tests / 1 suite passed。
- Memory/Vector/Prompt/Chat focused suite：35 tests / 4 suites passed。
- Full suite：219 tests / 45 suites passed。
