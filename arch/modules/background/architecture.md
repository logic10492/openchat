# Background 架构

> 状态：目标架构规划，尚未实现。

## 1. 模块定位

Background 层负责“本轮给主聊天模型看什么背景”。它不负责生成 assistant 回复，也不直接持久化用户可见内容。

目标模块：

```text
Core/Background/
  BackgroundManager
  BackgroundWorker
  BackgroundSource
  BackgroundCandidate
  BackgroundPacket
  BackgroundAssembler
  BackgroundDiagnostics
```

目标来源适配：

```text
Core/Memory/
  MemoryBackgroundSource

Core/WorldBook/
  WorldBookBackgroundSource
  WorldBookEmbeddingIndexer

Core/Character/
  CharacterBackgroundSource

Core/ConversationState/
  ConversationStateBackgroundSource
```

`Core/Character` 与 `Core/ConversationState` 是目标边界名，不代表当前已有对应源码目录。

## 2. 当前实现与目标差异

| 领域 | 当前源码 | Background 目标 |
|---|---|---|
| WorldBook | `PromptAssembler` 内按 keyword 触发并注入 `[World Book Entries]` | `WorldBookBackgroundSource` 产出 candidates，BackgroundWorker 统一选择 |
| Memory | `ChatViewModel` 调 `MemoryManager.retrieveMemories`，`PromptAssembler` 注入 `[Memories]` | `MemoryBackgroundSource` 产出 candidates，BackgroundWorker 与世界书统一排序 |
| 角色卡 | Stable Identity 直接进入 prompt | 稳定身份仍保持独立；可额外产生 character-state candidates |
| Prompt | 多个 labeled blocks 直接组装 | BackgroundAssembler 生成统一 `[Background]` 或一组 background blocks |
| 检索排序 | WorldBook priority / Memory semantic order 分离 | 统一 fusion：relevance、priority、recency、source policy |

## 3. 依赖方向

```text
Features/Chat
  -> Core/Background
  -> Core/Memory
  -> Core/WorldBook
  -> Core/Database

Core/PromptEngine
  -> Core/Background DTO
  -> Core/Database Records
```

约束：

- `Core/Background` 不依赖 `Features`。
- `BackgroundWorker` 不调用 UI，也不产生 `ChatMessage(role: "assistant")`。
- `PromptAssembler` 可以消费 `BackgroundPacket` 或 `BackgroundPromptBlock`，但不负责召回和排序。
- `WorldBook` 与 `Memory` 不再分别拥有最终 prompt 注入权。

## 4. 目标接口草案

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

struct BackgroundPacket: Sendable {
    let entries: [BackgroundEntry]
    let omitted: [BackgroundOmission]
    let diagnostics: BackgroundDiagnostics
}
```

## 5. Prompt 输出形态

默认目标是统一 block：

```text
[Background]
[World]
...

[Memory]
...

[Character State]
...
[/Background]
```

也可以保留多 block 输出，但排序和裁剪权仍来自 `BackgroundPacket`：

```text
[Background: World]
...
[/Background: World]

[Background: Memory]
...
[/Background: Memory]
```

决策原则：先统一调度，后决定文本格式。不要让文本格式反过来决定调度策略。

## 6. 与 ContextManager 的关系

Background 是 current-turn context，不替代历史窗口处理：

- `ContextManager` 仍负责同一 conversation 的历史截断/压缩。
- Memory/WorldBook/CharacterState 进入 Background，不进入 compression checkpoint。
- Background token budget 应从 fixed/context budget 中明确分配，避免挤压当前输入。
