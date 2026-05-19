# 多角色 Stage

> 状态：多角色同场 foundation 已落地；当前只支持一轮一个 active speaker 输出，不支持多 speaker 连续输出 parser。

2026-05-19 closeout：`stage_participant` 表、`StageParticipantRecord`、`StageParticipantVisibility`、`MessageSpeakerKind`、`StageTurnPlan` 已落地。Chat Settings 可为当前 Stage 添加多个角色；`DirectorController` 当前默认策略为“输入点名优先，否则选择 sortOrder 最小的 active present participant”。assistant message 会保存 `stageId`、`speakerKind`、`speakerId`、`speakerName`。

## 1. 角色边界

Stage 支持多个角色共同参与，但每个角色仍是 persona，不是 agent。

角色的输入来源：

- `CharacterCardRecord`
- 与该角色相关的 Memory
- 绑定世界书和 Background
- Stage / ConversationState
- DirectorPlan 中的舞台指令

角色不拥有：

- 工具调用权。
- 自治任务队列。
- 静默写数据库权限。
- 独立长期规划器。

## 2. Stage 参与者

当前数据结构：

```swift
struct StageParticipant: Identifiable, Sendable {
    let id: String
    let characterCardId: String
    let displayName: String
    let visibility: StageParticipantVisibility
    let isActive: Bool
    let sortOrder: Int
}

enum StageParticipantVisibility: String, Codable, Sendable {
    case present
    case hidden
}
```

语义：

- `present + isActive`：本轮可作为 speaker。
- `hidden` 或 `isActive == false`：当前 deterministic selector 不会选作 speaker。
- 当前没有单独 `offStage` 状态；需要退场语义时应后续扩展 visibility / participation state，而不是复用 message role。

## 3. 发言计划

Director 或默认策略可以生成：

```swift
struct SpeakerTurn: Sendable {
    let participantId: String
    let intent: SpeakerIntent
    let maxTokens: Int?
}

enum SpeakerIntent: String, Codable, Sendable {
    case respondToUser
    case react
    case advanceScene
    case remainSilent
}
```

第一阶段可以只允许一轮一个角色回复；后续再扩展为多角色连续输出。

## 4. 多角色输出格式

目标 UI 可以把 staged assistant messages 拆成多条：

```text
艾拉: ...
卡伦: ...
```

存储上已追加 speaker metadata：

```swift
var stageId: String?
var speakerKind: String?
var speakerId: String?
var speakerName: String?
```

当前沿用 `message.role == assistant`，通过 v18 追加字段区分具体角色。`speakerName` 是显示快照；`speakerId` 当前保存 `stage_participant.id`，不是 `character_card.id`。

## 5. 默认发言策略

没有 Director agent 或用户导演指令时：

- 优先当前用户直接点名的角色。
- 其次选择 sortOrder 最小的 active present participant。
- 若多个角色都相关，选择一个主回复角色，其他角色保持 silent。
- 不自动让所有 active 角色每轮都说话，避免输出臃肿。

尚未实现：

- 最近活跃角色选择。
- 多角色 persona 摘要 block；当前 active speaker persona 仍通过既有 `CharacterCardRecord` 注入。
- 多 speaker output parser 和一轮多 assistant message 拆分。
