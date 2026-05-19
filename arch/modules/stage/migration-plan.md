# Stage 迁移计划

> 状态：Director contract foundation、Stage DB、Stage participant binding、用户导演输入 UI 和最小 deterministic Stage runtime 已落地；LLM Director agent、多角色连续输出 parser、独立 Stage 列表页和 UI 自动化仍未实现。

## Phase 0：文档和边界

- 明确 Chat 是当前实现，Stage 是目标扩展。
- 明确角色不是 agent。
- 明确角色回复第一阶段保持自然流式文本，不强制动作/台词 schema，也不开放普通角色 tool call。
- 明确 AgentCore 服务后台 agent/worker，不把普通角色纳入 runtime agent。
- 明确 Director 有三种模式：闭嘴、agent、用户接管。
- 明确用户随时可以以导演身份说话。

## Phase 1：Stage DTO

新增基础类型：

- 已落地：`DirectorMode`
- 已落地：`StageInputRole`
- 已落地：`StageInstruction`
- 已落地：`DirectorInput`
- 已落地：`SpeakerTurn`
- 已落地：`DirectorPlan`
- 已落地：`DirectorDiagnostics`
- 已落地：`StageRecord`
- 已落地：`StageParticipantRecord` / `StageParticipant`
- 已落地：`StageParticipantVisibility`
- 已落地：`MessageSpeakerKind`

第一阶段不改变现有 Chat UI，只在架构层准备 DTO 和测试。

2026-05-19 计划包入口：顶层路线 Phase 6 先拆出 Director / 导演模式 foundation，见 `docs/superpowers/plans/2026-05-19-director-mode-foundation/README.md`。该计划包只整理 `DirectorPlan`、`DirectorMode`、`StageInstruction`、mode policy 和 prompt boundary contract；不提前实现 Stage DB/UI 或多角色输出。

2026-05-19 closeout：上述 Director contract subset 已进入 `OpenChat/Core/Stage/*` 并由 `DirectorContractTests` / `AgentPolicyTests` 覆盖。该 closeout 不新增 DB migration，不修改 `ConversationRecord` / `MessageRecord`，不修改 Chat UI / InputBar，也不把 Director Instructions 注入 production prompt。

2026-05-19 runtime closeout：后续同日增量已追加 `v18_create_stage_tables`、`StageRecord` / `StageParticipantRecord` / `StageInstructionRecord`、`StageModels`、`DirectorController`、`DirectorExecutor`，并把 `StageTurnPlan` 接入 Chat / Prompt 主链路。

## Phase 2：用户导演输入

目标：

- 已落地：输入栏在 Stage enabled 时支持 participant / director segmented picker。
- 已落地：导演输入进入 `stage_instruction`，不作为角色台词。
- 已落地：任意 DirectorMode 下用户都可以临时选择 `.director` 输入。

测试：

- 已覆盖：director input 不进入普通 user message history。
- 已覆盖：stage instruction 能进入后续 prompt 的 `[Director Instructions]`。

## Phase 3：单轮多角色参与但单角色输出

目标：

- 已落地：Stage 可绑定多个角色卡，当前入口在 `ChatSettingsSheet`。
- 已落地：Director/default policy 决定本轮主 speaker，当前 deterministic 策略为“输入点名优先，否则第一个 active participant”。
- 已落地：Prompt 包含 active participants 名称和 active speaker。
- 已落地：模型仍只输出一个角色回复，并保存 speaker metadata。

边界：当前 participant prompt 只包含 display name 与 active speaker，还没有汇总所有参与角色的 persona 摘要；实际回复 persona 由 active speaker 对应的 `CharacterCardRecord` 提供。

## Phase 4：Director agent mode

目标：

- Director agent 复用 AgentCore policy / diagnostics。
- Director agent 生成结构化 `DirectorPlan`。
- DirectorPlan 只用于 stage control，不直接显示为 assistant 回复。
- silent mode 下完全跳过 Director agent。

当前状态：policy 与 DTO contract 已落地；deterministic executor/controller 和 Chat/Stage 调度接入已完成。LLM Director agent、schema repair、timeout behavior 和 AgentCore executor wiring 仍未实现。

## Phase 5：Background 接入 Stage

目标：

- StageBackgroundContext 传给 BackgroundManager。
- Memory / WorldBook candidates 受 active participants 和 scene focus 影响。
- BackgroundPacket 进入 Stage prompt。

## Phase 6：多角色连续输出

目标：

- 支持一轮多个 Speaker blocks。
- UI 按角色拆分 staged assistant messages。
- DB 保存 speaker metadata。

该阶段涉及 schema 变更，应单独设计 migration。

当前备注：v18 已为 `message` 追加 `stageId` / `speakerKind` / `speakerId` / `speakerName`，足够支持单 speaker staged assistant message；真正多 speaker parser 和一轮多 message 拆分仍需单独计划与测试。
