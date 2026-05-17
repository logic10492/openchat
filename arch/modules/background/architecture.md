# Background 架构

> 状态：部分实现。AgentCore foundation 已存在；Phase 4A-4D source tool contract、MemoryRecallTool、WorldBookRecallTool、MemoryBackgroundSource、WorldBookBackgroundSource 已落地并通过 focused tests。Background runtime / worker / packet / prompt switch 尚未实现。

## 1. 模块定位

Background 层负责“本轮给主聊天模型看什么背景”。它不负责生成 assistant 回复，也不直接持久化用户可见内容。

目标模块：

```text
Core/AgentCore/
  AgentDescriptor
  AgentCapability
  AgentPolicy
  AgentTask
  AgentDiagnostics
  AgentExecutor
  AgentExecutionResult

Core/Background/
  BackgroundManager
  BackgroundWorker
  BackgroundSource
  BackgroundSourceTool
  BackgroundCandidate
  BackgroundPacket
  BackgroundAssembler
  BackgroundDiagnostics
```

目标来源适配：

```text
Core/Memory/
  MemoryRecallTool
  MemoryBackgroundSource

Core/WorldBook/
  WorldBookRecallTool
  WorldBookBackgroundSource
  WorldBookEmbeddingIndexer

Core/Character/
  CharacterBackgroundSource

Core/ConversationState/
  ConversationStateBackgroundSource
```

`Core/Character` 与 `Core/ConversationState` 是目标边界名，不代表当前已有对应源码目录。

顺序要求：

```text
AgentCore foundation
  -> MemoryRecallTool / WorldBookRecallTool
  -> MemoryBackgroundSource / WorldBookBackgroundSource
  -> Core/Background DTO
  -> deterministic BackgroundWorker
  -> Chat / Prompt switch to BackgroundPacket
```

`MemoryRecallTool` / `WorldBookRecallTool` 是内部 read-only source tool：它们包装当前已经存在的 recall result，不向普通角色开放 tool call，不触发用户可见输出，不写数据库。

2026-05-17 Phase 4A-4D 当前实现证据：

- `OpenChat/Core/Background/BackgroundSourceTool.swift`：`BackgroundSourceType`、`BackgroundSourceTool`、`BackgroundRequest`、`BackgroundSource`、`BackgroundCandidate` 已进入 Xcode target。
- `OpenChat/Core/Memory/MemoryRecallTool.swift`：`MemoryRecallTool` 符合 `BackgroundSourceTool`，只转发到 `MemoryManager.recallMemories(...)`。
- `OpenChat/Core/WorldBook/WorldBookRecallTool.swift`：`WorldBookRecallTool` 符合 `BackgroundSourceTool`，只转发到 `WorldBookSource.recallEntries(...)`。
- `OpenChat/Core/Background/MemoryBackgroundSource.swift` / `WorldBookBackgroundSource.swift`：只把 recall result 映射为 `BackgroundCandidate`，不复制 source 内部排序，不裁剪 token budget。
- `OpenChatTests/Core/MemoryTests/MemoryRecallToolTests.swift`、`OpenChatTests/Core/WorldBookTests/WorldBookRecallToolTests.swift`：focused pass-through tests 覆盖顺序、rank/reason/trace/omission 透传。
- `OpenChatTests/Core/BackgroundTests/BackgroundSourceTests.swift`：focused adapter tests 覆盖 candidate id prefix、顺序、metadata、request 边界和不按 token budget 裁剪。

## 2. 当前实现与目标差异

| 领域 | 当前源码 | Background 目标 |
|---|---|---|
| WorldBook | `WorldBookSource.recallEntries(...)` 预选 keyword + semantic 条目，`PromptAssembler` 注入 `[World Book Entries]` | `WorldBookRecallTool` 包装 recall result，`WorldBookBackgroundSource` 产出 candidates，BackgroundWorker 统一选择 |
| Memory | `ChatViewModel` 调 `MemoryManager.retrieveMemories`，`PromptAssembler` 注入 `[Memories]` | `MemoryRecallTool` 包装 `MemoryManager.recallMemories(...)` result，`MemoryBackgroundSource` 产出 candidates，BackgroundWorker 与世界书统一排序 |
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
  -> Core/AgentCore

Core/PromptEngine
  -> Core/Background DTO
  -> Core/Database Records
```

约束：

- `Core/Background` 不依赖 `Features`。
- `Core/Background` 可以依赖 `Core/AgentCore` 的 identity / policy / diagnostics / execution result，但 Background 的业务 DTO 仍保留在 `Core/Background`。
- `Core/Background` 不复制 Memory / WorldBook 的排序算法；Memory / WorldBook source tool 只把各自 recall result 结构化暴露给 adapter。
- `BackgroundWorker` 不调用 UI，也不产生 `ChatMessage(role: "assistant")`。
- `BackgroundWorker` 第一阶段只启用 deterministic capability，不调用 LLM、不联网、不写数据库。
- `BackgroundWorker` 不直接调用 raw DB 写入或索引 rebuild；WorldBook bounded rebuild 仍属于既有 Chat / lifecycle 兼容链路，后续如迁移必须单独设计 side-effect boundary。
- 2026-05-17 AgentCore closeout 已验证 `AgentPolicy.backgroundWorkerDefault()`、`AgentDiagnostics` 和 `DeterministicAgentExecutor`；AgentCore focused tests 12 tests / 4 suites passed，当时 full suite 303 tests / 58 suites passed。Background Source Tools Phase 4A-4D 之后，当前全局 full-suite 基线已更新为 319 tests / 61 suites passed。这些可作为后续 `Core/Background` 的前置 contract。
- `PromptAssembler` 可以消费 `BackgroundPacket` 或 `BackgroundPromptBlock`，但不负责召回和排序。
- `WorldBook` 与 `Memory` 不再分别拥有最终 prompt 注入权。

## 4. 目标接口草案

```swift
struct BackgroundRequest: Sendable {
    let conversation: ConversationRecord
    let characterCard: CharacterCardRecord?
    let worldBook: WorldBookRecord?
    let worldBookEntries: [WorldBookEntryRecord]
    let recentMessages: [MessageRecord]
    let currentInput: String
    let tokenBudget: Int
    let memoryLimit: Int
    let worldBookLimit: Int
}

protocol BackgroundSource: Sendable {
    var sourceType: BackgroundSourceType { get }
    func candidates(for request: BackgroundRequest) async throws -> [BackgroundCandidate]
}

protocol BackgroundSourceTool: Sendable {
    associatedtype Input: Sendable
    associatedtype Output: Sendable

    var sourceType: BackgroundSourceType { get }
    func call(_ input: Input) async throws -> Output
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

`BackgroundDiagnostics` 可以包装或投影 `AgentDiagnostics`。Background 专有字段（source counts、omitted reason、fallback tier、selected ids）留在 Background 层，不塞回 AgentCore。

Memory / WorldBook adapter 草案：

```text
MemoryRecallTool
  -> MemoryManager.recallMemories(...)
  -> MemoryRecallResult
  -> MemoryBackgroundSource maps result.entries / trace to BackgroundCandidate metadata

WorldBookRecallTool
  -> WorldBookSource.recallEntries(...)
  -> WorldBookRecallResult
  -> WorldBookBackgroundSource maps result.entries / trace to BackgroundCandidate metadata
```

这一步只转换边界，不改变 Memory 或 WorldBook 内部 rank fusion。

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
