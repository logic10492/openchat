# 多角色 Stage

> 状态：多角色同场 foundation 已落地；当前支持一轮两个 responder 独立输出、输入栏导演工具面板覆盖回应角色/顺序，也支持完整输出后的多 speaker block parser 与多条 staged assistant message 拆分。

2026-05-19 closeout：`stage_participant` 表、`StageParticipantRecord`、`StageParticipantVisibility`、`MessageSpeakerKind`、`StageTurnPlan` 已落地。Chat Settings 可为当前 Stage 添加多个角色；`DirectorController` 当前默认策略为“输入点名优先，否则选择 sortOrder 最小的 active present participant”。assistant message 会保存 `stageId`、`speakerKind`、`speakerId`、`speakerName`。

2026-05-20 closeout：`StageSpeakerBlockParser` 支持 `[Speaker: name-or-id]...[/Speaker]` 与 `Name:` 行首 block；`ChatViewModel+Support.persistCompletedAssistantMessages(...)` 会把多个 speaker blocks 拆成多条 `MessageRecord(role: "assistant")`，每条保存对应 `stageId` / `speakerKind` / `speakerId` / `speakerName`。`StageSpeakerBlockParserTests` 与 `ChatViewModelPromptAssemblyTests.test_stageSpeakerBlocksSplitIntoMultipleAssistantMessages` 覆盖 parser 与持久化拆分。

2026-05-21 closeout：Stage participant 输入的默认最小策略改为前两个 active/present participant 都生成回复。`ChatViewModel+Support.generateResponse(...)` 默认按 sortOrder 取 `activeParticipants.prefix(2)`，并为每个 speaker 单独构造 `StageTurnPlan.forSpeaker(...)`、读取该 speaker 的 `CharacterCardRecord`、准备 prompt/context/background，然后分别调用 `APIClient.streamMessage(...)` 保存 assistant message。输入栏的导演工具按钮可展开/折叠回应顺序面板，用户可勾选本轮谁回应并用上下按钮调整顺序；生成链路优先使用 `ChatViewModel.stageResponderIds`。`ChatViewModelPromptAssemblyTests.test_stageTwoParticipantsUseSeparateCharacterPrompts` 覆盖两次请求分别注入 Mara / Io 的角色卡，且第二个角色的 prompt history 能看到第一个角色刚生成的回复；`test_stageResponderOrderOverridesDefaultSpeakers` 覆盖用户指定顺序覆盖默认前两个。

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

当前最小策略不依赖 Director agent：默认取前两个 active/present participant，各自独立生成一条回复；用户在输入栏导演工具面板中调整 responder 后，则按 `stageResponderIds` 的顺序生成。每条回复都使用对应 participant 的角色卡、世界书、记忆和 Background request，避免一个主模型同时扮演多张角色卡导致 persona 串线。当 LLM 仍输出多个 speaker blocks 时，runtime 兼容拆分保存，但这不是当前多角色主路径。

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

- 默认按 sortOrder 取前两个 active present participant。
- 若用户在输入栏导演工具面板中选择 responder，则按用户选择的角色和顺序生成。
- 每个 participant 各自用自己的 `CharacterCardRecord` 独立生成一条 assistant message。
- 若只有一个 active present participant，则只生成一条回复。
- 暂不让所有 active 角色每轮都说话，避免输出无限增长；超过两个角色的调度留给后续 Director speakerPlan。

尚未实现：

- 最近活跃角色选择。
- Director speakerPlan 完整驱动多个角色发言。
- 多角色 persona 摘要 block；当前 active speaker persona 仍通过既有 `CharacterCardRecord` 注入。
- streaming 过程中按 speaker block 实时分流；当前是在完整 assistant 内容可用后拆分。
