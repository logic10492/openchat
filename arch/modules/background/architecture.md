# Background 架构

> 状态：已实现 Phase 4A-4D source tool contract、Memory/WorldBook adapters、Phase 5 deterministic BackgroundWorker / BackgroundPacket / diagnostics、Phase 6 BackgroundManager / BackgroundAssembler / Chat-Prompt compatible switch。统一 `[Background]` block、Character/ConversationState sources、LibMan 和 synthesis 尚未实现。

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
  CharacterBackgroundSource        // 目标边界，当前未实现

Core/ConversationState/
  ConversationStateBackgroundSource // 目标边界，当前未实现
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

2026-05-17 Phase 5/6 当前实现证据：

- `OpenChat/Core/Background/BackgroundPolicy.swift`：定义 worker candidate selection ceiling、per-source limits、source weights 和兼容默认策略。
- `OpenChat/Core/Background/BackgroundPacket.swift`：定义 `BackgroundWorkerInput`、`BackgroundPacket`、`BackgroundEntry`、`BackgroundOmission` 与 omission reason。
- `OpenChat/Core/Background/BackgroundDiagnostics.swift`：记录 selected ids、omitted、source summaries、fallbacks、warnings、policy profile 和 agent policy summary。
- `OpenChat/Core/Background/BackgroundWorker.swift`：只消费 `[BackgroundCandidate]`，做 deterministic score/sort/dedupe/budget/per-source limit selection；policy gate 拒绝非 deterministic、network、DB write 等能力。
- `OpenChat/Core/Background/BackgroundManager.swift`：组合 `BackgroundSource` 与 worker；单 source 失败时记录 warning，worldBook source failure 使用旧 keyword fallback 生成 `.worldBook` candidates。
- `OpenChat/Core/Background/BackgroundAssembler.swift`：把 packet entries 转成兼容 `[World Book Entries]` / `[Memories]` prompt items，diagnostics 不进入 prompt。
- `OpenChat/App/DependencyContainer.swift`：装配 `MemoryRecallTool`、`WorldBookRecallTool`、`MemoryBackgroundSource`、`WorldBookBackgroundSource`、`BackgroundWorker` 和 `BackgroundManager`。
- `OpenChat/Features/Chat/ViewModels/ChatViewModel+Support.swift`：主链路调用 `BackgroundManager.prepare(...)` 后交给 packet-aware `PromptAssembler`；bounded worldBook rebuild 仍保留在 Chat 侧、执行于 manager prepare 前。
- `OpenChat/Core/PromptEngine/PromptAssembler.swift`：新增 packet-aware preview/assemble overload，保留旧 direct overload 作为兼容 / rollback；输出格式仍为 `[World Book Entries]` 在前、`[Memories]` 在后。
- Tests：`BackgroundPacketTests`、`BackgroundWorkerTests`、`BackgroundDiagnosticsTests`、`BackgroundManagerTests`、`PromptAssemblerTests`、`ChatViewModelPromptAssemblyTests` 覆盖 DTO、worker selection/denial/diagnostics、manager fallback、packet compatible prompt blocks、budget trim、current input dedupe 和 request-shape switch。

## 2. 当前实现与目标差异

| 领域 | 当前源码 | Background 目标 |
|---|---|---|
| WorldBook | `WorldBookRecallTool` / `WorldBookBackgroundSource` 包装 `WorldBookSource.recallEntries(...)` result，`BackgroundWorker` 统一选择，`BackgroundAssembler` 生成兼容 `[World Book Entries]` | 后续可迁移为统一 `[Background]` block 或新增 Character/ConversationState source |
| Memory | `MemoryRecallTool` / `MemoryBackgroundSource` 包装 `MemoryManager.recallMemories(...)` result，`BackgroundWorker` 统一选择，`BackgroundAssembler` 生成兼容 `[Memories]` | 后续可迁移为统一 `[Background]` block 或新增 Character/ConversationState source |
| 角色卡 | Stable Identity 直接进入 prompt | 稳定身份仍保持独立；可额外产生 character-state candidates |
| Prompt | BackgroundAssembler 生成兼容 `[World Book Entries]` / `[Memories]` blocks | 后续可迁移为统一 `[Background]` block |
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

当前实现先保持兼容 block，来源已切到 `BackgroundPacket`：

```text
[World Book Entries]
...
[/World Book Entries]

[Memories]
...
[/Memories]
```

后续可选目标是统一 block：

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

决策原则：先统一调度，后决定文本格式。2026-05-17 Phase 6 已完成统一调度和兼容 block switch；统一 `[Background]` 需要单独 request-shape 测试和用户确认。

## 6. 与 ContextManager 的关系

Background 是 current-turn context，不替代历史窗口处理：

- `ContextManager` 仍负责同一 conversation 的历史截断/压缩。
- Memory/WorldBook/CharacterState 进入 Background，不进入 compression checkpoint。
- Background token budget 应从 fixed/context budget 中明确分配，避免挤压当前输入。
