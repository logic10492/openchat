# 06. Phase 4D - BackgroundSource Adapters

## 目标

在 source tools 完成后，把 Memory / WorldBook result 转为统一 `BackgroundCandidate`。

这一步仍不实现 worker，不切 prompt。

目标链路：

```text
MemoryRecallTool
  -> MemoryRecallResult
  -> MemoryBackgroundSource
  -> [BackgroundCandidate]

WorldBookRecallTool
  -> WorldBookRecallResult
  -> WorldBookBackgroundSource
  -> [BackgroundCandidate]
```

## 建议文件

```text
OpenChat/Core/Background/BackgroundRequest.swift
OpenChat/Core/Background/BackgroundCandidate.swift
OpenChat/Core/Background/BackgroundSource.swift
OpenChat/Core/Background/MemoryBackgroundSource.swift
OpenChat/Core/Background/WorldBookBackgroundSource.swift
OpenChatTests/Core/BackgroundTests/BackgroundSourceTests.swift
```

如果为了保持 source ownership，也可以把 adapter 放在：

```text
OpenChat/Core/Memory/MemoryBackgroundSource.swift
OpenChat/Core/WorldBook/WorldBookBackgroundSource.swift
```

但协议和 shared DTO 应留在 `Core/Background`，避免 Feature 层参与。

## 建议 DTO

```swift
struct BackgroundRequest: Sendable {
    let conversation: ConversationRecord
    let characterCard: CharacterCardRecord?
    let worldBook: WorldBookRecord?
    let recentMessages: [MessageRecord]
    let currentInput: String
    let tokenBudget: Int
}

protocol BackgroundSource: Sendable {
    var sourceType: BackgroundSourceType { get }
    func candidates(for request: BackgroundRequest) async throws -> [BackgroundCandidate]
}

struct BackgroundCandidate: Identifiable, Sendable {
    let id: String
    let sourceType: BackgroundSourceType
    let sourceId: String
    let content: String
    let title: String?
    let basePriority: Int
    let relevance: Double?
    let recency: Date?
    let metadata: [String: String]
}
```

## Memory mapping

`MemoryRecallEntry` -> `BackgroundCandidate`：

- `id`: `"memory:\(memory.id)"`
- `sourceType`: `.memory`
- `sourceId`: `memory.id`
- `content`: `memory.content`
- `title`: memory type or nil
- `basePriority`: `memory.importance`
- `relevance`: derived from semantic rank / distance, if present
- `recency`: `memory.updatedAt` or `memory.createdAt`
- `metadata`: finalRank, semanticRank, semanticDistance, keywordRank, recencyRank, reasons, fallback

Adapter 不得按 importance 重排。

## WorldBook mapping

`WorldBookRecallEntry` -> `BackgroundCandidate`：

- `id`: `"worldBook:\(entry.id)"`
- `sourceType`: `.worldBook`
- `sourceId`: `entry.id`
- `content`: `entry.content`
- `title`: `entry.title`
- `basePriority`: `entry.priority`
- `relevance`: derived from semantic rank / distance, if present
- `recency`: `entry.updatedAt`
- `metadata`: finalRank, keywordRank, semanticRank, semanticDistance, keywordHits, reasons, omissions

Adapter 不得按 priority 单独重排。

## 测试要求

focused tests 至少覆盖：

- Memory result 顺序 -> candidates 顺序保持。
- WorldBook result 顺序 -> candidates 顺序保持。
- metadata 包含后续 diagnostics 需要的 rank / reasons / fallback。
- candidate id 带 source prefix，跨 source 不冲突。
- nil worldBook / nil characterCard 的处理与 tool input 边界一致。
- adapter 不做 token budget 裁剪。

## Phase 4 closeout

完成 4D 后，Phase 4 closeout 必须确认：

- Chat prompt 没变。
- `PromptAssembler` 没变，除非只是编译所需 import 且已记录原因。
- `ChatViewModel+Support` 没变。
- tools / adapters focused tests 通过。
- Memory / WorldBook existing focused tests 通过。
- AgentCore policy focused tests 通过。
- 文档写回明确 BackgroundWorker 仍未实现。
