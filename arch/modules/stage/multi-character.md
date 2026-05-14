# 多角色 Stage

> 状态：目标架构规划，尚未实现。

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

目标数据结构：

```swift
struct StageParticipant: Identifiable, Sendable {
    let id: String
    let characterCardId: String
    let displayName: String
    let participationState: ParticipationState
}

enum ParticipationState: String, Codable, Sendable {
    case active
    case presentButSilent
    case offStage
}
```

语义：

- `active`：本轮可发言。
- `presentButSilent`：在场但默认不发言，可被提及或观察。
- `offStage`：不在当前场景，不参与本轮 prompt。

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

存储上建议保留 speaker metadata：

```swift
struct StageMessageMetadata: Codable, Sendable {
    let speakerType: StageSpeakerType
    let characterCardId: String?
    let directorMode: DirectorMode?
}
```

如果沿用 `message.role == assistant`，需要额外字段区分具体角色。该 schema 改动应通过新 migration 追加，不能修改旧 migration。

## 5. 默认发言策略

没有 Director agent 或用户导演指令时：

- 优先当前用户直接点名的角色。
- 其次最近活跃角色。
- 若多个角色都相关，选择一个主回复角色，其他角色保持 silent。
- 不自动让所有 active 角色每轮都说话，避免输出臃肿。
