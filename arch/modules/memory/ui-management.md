# Memory UI 与管理

## 1. Chat 内联提取状态

Chat 发送链路中的自动提取状态由 `MemoryExtractionPhase` 表示：

```swift
enum MemoryExtractionPhase: Sendable, Equatable {
    case idle
    case extracting
    case completed(count: Int, summaries: [String])
    case skipped
    case failed(description: String)
}
```

`MemoryExtractionIndicator` 渲染规则：

| 状态 | UI 行为 |
|---|---|
| `idle` | 不显示 |
| `skipped` | 不显示 |
| `extracting` | 显示 “Extracting memories…” |
| `completed` | 显示 “Memorized N entries”，可展开查看 summaries，3 秒后 dismiss |
| `failed` | 显示 “Memory extraction failed” 和错误描述，5 秒后 dismiss |

当前实现使用内联状态，不再使用旧的 message marker。

## 2. 角色记忆列表

入口在角色详情页，管理页为 `MemoryListView`。

能力：

- 加载指定 `characterCardId` 的全部记忆。
- 按本地 `searchText` 做 content contains 过滤。
- 展示 memory type badge、content、relative createdAt、importance progress。
- 左滑删除单条。
- toolbar 中 `Clear All` 清空当前角色全部记忆。
- 删除失败或加载失败时在底部显示 error message。

## 3. ViewModel 边界

`MemoryListViewModel` 是 `@Observable @MainActor`：

```swift
final class MemoryListViewModel {
    private let databaseManager: DatabaseManager
    private let memoryManager: MemoryManager
    let characterCardId: String

    private(set) var memories: [MemoryEntryRecord]
    var searchText: String
    var errorMessage: String?

    var filteredMemories: [MemoryEntryRecord]
    func loadMemories() async
    func deleteMemory(_ id: String) async
    func deleteAllMemories() async
}
```

边界：

- View 不直接读写 DB。
- 删除走 `MemoryManager`，确保 entry 与 embedding 同步删除。
- 列表加载走 `DatabaseManager.fetchMemories(characterCardId:)`，按 `createdAt DESC`。

## 4. 当前 UI 缺口

- 检索阶段没有 UI 说明：用户看不到本轮命中了哪些记忆、哪些被 token budget 裁掉。
- fallback 原因只写日志，不展示给用户。
- MemoryListView 目前没有按 type/importance 排序过滤。
- `ProgressView(value:total:)` 当前 total 为 10，而 `importance` 存储语义是 0...100；这属于 UI 显示尺度风险，后续应修正为 total 100 或显示文本分值。
- 自动提取的 `completed` summaries 来自本轮 LLM 输出，没有持久化为单独 UI 事件；刷新后只能从列表查看。

## 5. 实现证据

- `OpenChat/Features/Chat/Models/MemoryExtractionPhase.swift`
- `OpenChat/Features/Chat/Views/MemoryExtractionIndicator.swift`
- `OpenChat/Features/Chat/Views/ChatView.swift`
- `OpenChat/Features/CharacterCard/Views/MemoryListView.swift`
- `OpenChat/Features/CharacterCard/ViewModels/MemoryListViewModel.swift`
- `OpenChatTests/Features/ChatTests/MemoryExtractionPhaseTests.swift`
