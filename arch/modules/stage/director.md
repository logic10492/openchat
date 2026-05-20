# Director / 导演

> 状态：Director contract foundation、deterministic controller/executor runtime 与 LLM Director agent runtime 已落地；导演调试 UI 仍未实现。

Director 是 Stage 的舞台调度者。它可以影响场景节奏、参与角色和发言计划，但不能替角色成为用户正在对话的 persona。

Director agent 模式复用 `AgentCore`，只输出结构化 `DirectorPlan`。它不能替角色写台词，也不能把内部分析作为主聊天 assistant message。

2026-05-17 closeout：`OpenChat/Core/AgentCore/AgentPolicy.swift` 已提供 `AgentPolicy.directorDefault(allowsLLM:)`，默认不开放 web / database write；AgentCore focused tests 12 tests / 4 suites passed，full suite 303 tests / 58 suites passed。这只是后续 Director 的 policy contract，不代表 Stage / Director runtime 已接入。

2026-05-19 closeout：Director contract foundation 已新增 `OpenChat/Core/Stage/DirectorMode.swift`、`StageInstruction.swift`、`DirectorPlan.swift`、`DirectorDiagnostics.swift`，并由 `OpenChatTests/Core/StageTests/DirectorContractTests.swift` 与 `AgentPolicyTests.swift` 覆盖三种 mode、stage instruction validation、speaker plan hint、diagnostics、prompt-order contract helper 和 Director policy 红线。该 closeout 仍未实现 Director executor/controller、Chat 主链路接入、Stage DB/UI、输入栏导演切换、多角色 participant 绑定或多 speaker output parser。

2026-05-19 runtime closeout：`OpenChat/Core/Stage/DirectorController.swift` 与 `DirectorExecutor.swift` 已接入 `ChatViewModel+Support.generateResponse(...)`。当前 executor 是 deterministic：participant 输入时优先选择被输入文本点名的 active participant，否则选择 sortOrder 最小的 active participant；director 输入时生成隐藏 `StageInstruction`，作为 instruction-only turn，不生成普通 user message、不生成 title、不调用 API。`OpenChatTests/Core/StageTests/DirectorContractTests.swift` 覆盖 controller 选择和 director-only turn；`OpenChatTests/Features/ChatTests/ChatViewModelPromptAssemblyTests.swift` 覆盖 director input history 隔离与 Stage prompt request shape。

2026-05-20 closeout：`OpenChat/Core/Stage/LLMDirectorTask.swift` 与 `LLMDirectorExecutor` 已接入 `DirectorMode.agent`。Chat 主链路在 stage mode 为 `.agent` 时使用 `LLMDirectorExecutor(agentExecutor: directorAgentExecutor, apiClient: endpoint: parameters:)`，并由 `LLMAgentExecutor` 执行 typed `AgentTask`。`LLMDirectorExecutorTests` 覆盖 agent mode 使用 LLM plan、invalid output fallback deterministic plan、policy 不联网不写库。

## 1. 三种工作模式

### 1.1 `silent` / 闭嘴

导演不主动介入。

行为：

- 不生成导演建议。
- 不改变发言计划。
- 只保留用户显式导演指令。
- Stage 按默认策略选择角色回复。

适用：

- 用户只想和角色自然对话。
- 多角色自动调度应尽量少打扰。

### 1.2 `agent` / agent 模式

导演作为后台 agent 参与调度，但不直接对用户输出。

可以：

- 生成 stage instruction。
- 建议哪些角色应参与本轮。
- 建议发言顺序。
- 标记剧情节奏问题。
- 提醒冲突、未完成事件或场景连续性。

不可以：

- 直接生成 assistant 回复。
- 替角色写台词。
- 静默修改角色卡、世界书或长期记忆。
- 把内部分析暴露给主聊天 UI，除非用户打开调试/导演面板。
- 绕过 AgentCore policy 临时获得写库、联网或角色回复权限。

### 1.3 `userControlled` / 用户接管模式

用户显式以导演身份说话，输入被解释为舞台指令。

可以：

- 指定下个发言角色。
- 设置场景变化。
- 调整节奏。
- 要求某角色暂时退场或加入。
- 给角色行动约束。

限制：

- 用户导演指令不应被保存为角色本人说过的话。
- 指令应进入 Stage/ConversationState，而不是直接当作 user-to-character 台词。

## 2. 用户随时以导演身份说话

无论当前模式是 `silent`、`agent` 还是 `userControlled`，用户都可以临时以导演身份说话。

UI/数据层建议：

```swift
enum StageInputRole: String, Codable, Sendable {
    case participant
    case director
}
```

当前 source 已落地 `StageInputRole` 作为输入语义 contract；`StageInputRole.director` 不等于 `MessageRecord.role == "user"`。`InputBarView` 在 Stage enabled 时显示 segmented picker；`ChatViewModel.sendMessage()` 在 `.director` 下调用 `saveDirectorInstruction(_:)`，写入 `stage_instruction` 并清空输入，不保存普通 `message`。

当用户切换为 `director`：

- 本轮输入作为 stage instruction。
- 不当作角色听到的普通台词，除非用户显式要求“让所有角色听到”。
- 可以影响 Background request、speaker plan 和 Stage state。

## 3. Director 输出 contract

```swift
struct DirectorPlan: Sendable {
    let mode: DirectorMode
    let stageInstructions: [StageInstruction]
    let speakerPlan: [SpeakerTurn]
    let diagnostics: DirectorDiagnostics
}

enum DirectorMode: String, Codable, Sendable {
    case silent
    case agent
    case userControlled
}
```

`DirectorPlan` 是结构化计划，不是 chat message。

当前 source contract：

- `DirectorMode`: `silent`、`agent`、`userControlled`，raw value / Codable / CaseIterable 已测试。
- `StageInstruction`: `source` 为 user / director agent / system default；默认 `visibility == hiddenFromCharacters`；空白 content 会抛出 typed `StageInstructionError.emptyContent`。
- `SpeakerTurn`: 仅为 Phase 6 hint，允许 participant / character id 为空，不代表多角色输出已实现。
- `DirectorDiagnostics`: 只承载 warning、omitted instruction ids、policy profile 和 metadata，不承载 assistant draft。
- `StagePromptLayerPlan`: 纯 contract helper，锁定 prompt order 中 `directorInstructions` 位于 `currentBackground` 之后、`currentTurn` 之前。
- `StageTurnPlan`: runtime DTO，提供 `[Stage]`、`[Stage Participants]` 和 `[Director Instructions]` system blocks 给 `PromptAssembler`。

## 4. 当前 runtime 边界

已实现：

- `DirectorController.planTurn(...)` deterministic speaker selection。
- `DeterministicDirectorExecutor.execute(...)`。
- `LLMDirectorExecutor.execute(...)` 与 `LLMDirectorTask`，在 `DirectorMode.agent` 下通过 AgentCore/LLM 生成 `DirectorPlan`。
- `ChatViewModel+Support.generateResponse(...)` 读取 `fetchStageContext(...)`，执行 Director，解析 active speaker 对应 `CharacterCardRecord`，并把 `StageTurnPlan` 传入 `PromptAssembler.preview(...)` / `assemble(...)`。
- user/assistant message 会保存 `stageId`、`speakerKind`、`speakerId`、`speakerName`。

仍未实现：

- Director diagnostics 不进入 UI。
- Director 不写角色卡、世界书或长期记忆。

## 4. 与 BackgroundWorker 的区别

| 项目 | Director | BackgroundWorker |
|---|---|---|
| 关注点 | 舞台调度、角色参与、节奏 | 背景条目选择、排序、裁剪 |
| 是否可输出给用户 | 默认不直接输出；用户可查看导演面板 | 默认不输出 |
| 是否能决定发言角色 | 可以建议 | 不可以 |
| 是否能选择背景条目 | 不直接选择 | 可以 |
| 是否能写角色台词 | 不可以 | 不可以 |
| AgentCore capability | 可选 `llm`，不联网、不写库 | 第一阶段仅 `deterministic` |
