# Stage 系统

> 状态：Stage / Director runtime 已落地；LLM Director agent、Responses API Stage snapshot、多 speaker 输出 parser、Stage XCUITest、Stage -> Background filter、retrieval trace UI 与独立 Stage 管理页已完成基础实现。
> 目标：把当前单角色 Chat 扩展为支持多角色共同参与的 Stage，同时引入可控的导演 agent。

2026-05-19 closeout：Stage foundation 已追加 `stage`、`stage_participant`、`stage_instruction` 三张表和 `message` speaker metadata；`ChatViewModel` 已能在 Chat Settings 中启用 Stage、绑定多个角色、切换 DirectorMode，并在输入栏切换 participant / director。正常 participant 输入会经 `DeterministicDirectorExecutor -> DirectorController` 选择一个 active speaker，把 `[Stage]`、`[Stage Participants]`、`[Director Instructions]` 注入当前 `PromptAssembler` 主链路；director 输入保存为隐藏 stage instruction，不保存为普通 user message，也不触发 API 请求。

2026-05-20 closeout：`DirectorMode.agent` 已经在 `ChatViewModel+Support.generateResponse(...)` 中走 `LLMDirectorExecutor -> LLMAgentExecutor -> LLMDirectorTask`，由 LLM 生成结构化 `DirectorPlan`，失败时 fallback 到 deterministic plan。`StageSpeakerBlockParser` 已接入 assistant 完成保存路径，可解析 `[Speaker: ...]` / `Name:` blocks 并拆成多条 staged assistant messages。`OpenChatUITests/StageUITests.swift` 覆盖 Stage 创建、DirectorMode、participant add/remove、director input 隔离。`StageManagementView` / `StageManagementViewModel` 提供独立 Stage 管理入口。

2026-05-20 UI closeout：Stage enabled 后，`ChatSettingsSheet` 不再显示单会话 `Character` picker / World Book 显示项；角色入口只保留 Stage 区域的 `Add Participant`。`ChatViewModel.saveConversationSettings()` 在 Stage 模式下不会通过旧的 `selectedCharacterCardID` 覆盖 `conversation.characterCardId`。`OpenChatUITests/StageUITests.swift` 追加断言防止 `chat.characterPicker` 在 Stage 设置页回归出现。

Stage 是 Chat 的扩展形态，不是把每个角色都 agent 化。角色仍然是 persona；Stage 负责多角色参与、发言顺序、导演介入和舞台级状态管理。

角色回复第一阶段保持自然流式文本。动作感优先依赖模型自然输出的 Markdown 斜体等文本形态，再由 UI 做轻量展示适配；不把角色回复改造成 AgentCore runtime 或 tool call。

## 1. 核心能力

- 一个 Stage 可以绑定多个角色卡。
- 多个角色可以在同一轮对话中共同参与。
- Stage 拥有一个 Director / 导演。
- 导演有三种工作模式：
  - `silent` / 闭嘴：导演不主动介入。
  - `agent` / agent 模式：导演可以后台调度场景、节奏、发言顺序和冲突提示，但不直接取代角色。
  - `userControlled` / 用户接管模式：用户以导演身份直接发出舞台指令。
- 不论当前导演模式如何，用户都可以临时以导演角色说话。

## 2. 非目标

- 不把对话角色改造成 agent。
- 不给普通角色回复开放 tool call；不在 Stage 第一阶段强制动作/台词 tagged schema。
- 不让导演替角色写最终台词。
- 不让导演拥有静默改写角色卡、世界书或记忆的权限。
- 不让多个 agent 在主聊天 UI 中互相暴露内部协商。

## 3. 文档结构

| 文档 | 内容 |
|---|---|
| [director.md](director.md) | 导演职责、三种模式和用户随时接管规则 |
| [multi-character.md](multi-character.md) | 多角色参与、发言选择、角色 persona 边界 |
| [prompt-flow.md](prompt-flow.md) | Stage 与 Background / PromptAssembler 的目标数据流 |
| [migration-plan.md](migration-plan.md) | 从当前 Chat 迁移到 Stage 的阶段计划 |

## 4. 当前最小数据流

```text
User input
  -> ChatViewModel
  -> DirectorExecutor
       -> deterministic speaker plan, or LLM DirectorPlan in agent mode
       -> optional hidden stage instruction
  -> BackgroundManager.prepare(...)
  -> PromptAssembler
       -> [Stage]
       -> [Stage Participants]
       -> character persona
       -> background packet
       -> conversation history
       -> [Director Instructions]
       -> current turn
  -> APIClient.streamMessage(...)
  -> one or more staged assistant messages with speaker metadata
```

当前支持在完整 assistant 输出后解析 speaker blocks 并拆成多条 message；streaming 过程中仍先显示原始增量，schema repair/复杂 parser diagnostics 仍属于后续增强。

## 5. 与 Background 的关系

Stage 负责“谁在场、谁发言、导演是否介入”。Background 负责“本轮给模型看什么背景”。

两者边界：

- Stage 不直接做 Memory/WorldBook 检索。
- Background 不决定最终角色发言内容。
- Director 可以给 BackgroundManager 提供 stage-level request，例如当前场景重点、参与角色、导演指令。
- BackgroundWorker 仍无发言权。

当前实现边界：Stage prompt 已接入 `BackgroundPacket` 后的 `PromptAssembler`；`StageBackgroundContext` 会把 active participant 与 director instructions 传给 `BackgroundManager`，`MemoryBackgroundSource` / `WorldBookBackgroundSource` 会把舞台上下文并入检索 query。Background 仍不决定最终发言内容。
