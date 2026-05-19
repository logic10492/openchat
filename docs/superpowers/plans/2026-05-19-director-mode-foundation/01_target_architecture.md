# 01. Target Architecture

## Phase 6 边界

Phase 6 只建立 Director / 导演模式的最小 contract：

- `DirectorMode`
- `StageInputRole`
- `StageInstruction`
- `SpeakerTurn`
- `DirectorInput`
- `DirectorPlan`
- `DirectorDiagnostics`

这些类型为后续 Stage / Prompt / UI 提供稳定边界，但不代表 Director runtime 已接入生产聊天。

## 核心数据流

```text
Stage or Chat context snapshot
  -> DirectorInput
  -> Director policy / deterministic default
  -> DirectorPlan
       -> stageInstructions
       -> speakerPlan
       -> diagnostics
  -> later StagePromptAssembler / Background request
```

## 最小 DTO 草案

```swift
enum DirectorMode: String, Codable, Sendable, CaseIterable {
    case silent
    case agent
    case userControlled
}

enum StageInputRole: String, Codable, Sendable, CaseIterable {
    case participant
    case director
}

struct StageInstruction: Identifiable, Codable, Sendable, Equatable {
    let id: String
    let source: StageInstructionSource
    let content: String
    let visibility: StageInstructionVisibility
    let createdAt: Date
}

struct DirectorInput: Codable, Sendable, Equatable {
    let mode: DirectorMode
    let userInputRole: StageInputRole
    let currentInput: String
    let recentInstructionIds: [String]
}

struct DirectorPlan: Codable, Sendable, Equatable {
    let mode: DirectorMode
    let stageInstructions: [StageInstruction]
    let speakerPlan: [SpeakerTurn]
    let diagnostics: DirectorDiagnostics
}
```

`SpeakerTurn` 在 Phase 6 只是计划 hint。它不能被解释为多角色连续输出已经实现。

## 三种模式

### silent

- 不主动运行 Director agent。
- 不主动生成 stage instruction。
- 可以保留用户显式导演指令作为 contract 输入。
- 默认 speaker policy 留后续 Stage 阶段实现。

### agent

- 允许 deterministic Director。
- 可选 LLM-assisted Director，但必须使用 `AgentPolicy.directorDefault(allowsLLM:)`。
- 不允许 web search、network tools、database write。
- 输出只允许是 `DirectorPlan`。
- 不生成 assistant message，不替角色写台词。

### userControlled

- 用户本轮输入被解释为 stage instruction。
- 默认不作为普通角色听到的台词。
- 是否让角色听见该指令必须是显式选项，留到 UI/Stage persistence 阶段。
- Phase 6 只锁 contract，不实现输入栏切换 UI。

## DirectorPlan 语义

`DirectorPlan` 是 stage control：

- 可以建议场景节奏。
- 可以建议本轮发言角色。
- 可以提示冲突、连续性或未完成事件。
- 可以携带 diagnostics。

`DirectorPlan` 不是：

- `MessageRecord(role: "assistant")`
- 普通 user message。
- 角色台词。
- 持久化写库命令。
- Background candidate selector。

## 与 Background 的关系

Director 负责“舞台应该怎么走”。Background 负责“本轮 prompt 应该看哪些背景”。

后续 Stage 阶段可以把 Director 输出投影给 Background：

```swift
struct StageBackgroundContext: Sendable {
    let activeParticipantIds: [String]
    let directorInstructions: [StageInstruction]
    let sceneFocus: String?
}
```

Phase 6 不修改 `BackgroundManager`，只把这个关系写成 contract。

## 与 Prompt 的关系

后续 Stage prompt 可以在 Current Background 之后、Current Turn 之前加入 Director Instructions：

```text
Stage Identity
Character Personas
Stable Conversation State
Current Background
Director Instructions
Current Turn
```

Phase 6 不修改当前生产 `PromptAssembler`。如果后续接入，应新增 request-shape tests，尤其覆盖 Responses API system folding 下 Director Instructions 不被误当成普通 user message。

## 非目标

- Stage DB schema。
- Stage UI。
- 用户导演输入控件。
- 多角色 participant 管理。
- 多 speaker output parser。
- `MessageRecord` speaker metadata。
- Director diagnostics UI。
- LibMan / Exa / web search。
- 强制 JSON / tagged roleplay output。
