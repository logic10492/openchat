# Stage 迁移计划

> 状态：目标架构规划，尚未实现。

## Phase 0：文档和边界

- 明确 Chat 是当前实现，Stage 是目标扩展。
- 明确角色不是 agent。
- 明确角色回复第一阶段保持自然流式文本，不强制动作/台词 schema，也不开放普通角色 tool call。
- 明确 AgentCore 服务后台 agent/worker，不把普通角色纳入 runtime agent。
- 明确 Director 有三种模式：闭嘴、agent、用户接管。
- 明确用户随时可以以导演身份说话。

## Phase 1：Stage DTO

新增基础类型：

- `StageRecord` 或 conversation 扩展字段。
- `StageParticipant`
- `DirectorMode`
- `StageInputRole`
- `SpeakerTurn`
- `DirectorPlan`

第一阶段不改变现有 Chat UI，只在架构层准备 DTO 和测试。

2026-05-19 计划包入口：顶层路线 Phase 6 先拆出 Director / 导演模式 foundation，见 `docs/superpowers/plans/2026-05-19-director-mode-foundation/README.md`。该计划包只整理 `DirectorPlan`、`DirectorMode`、`StageInstruction`、mode policy 和 prompt boundary contract；不提前实现 Stage DB/UI 或多角色输出。

## Phase 2：用户导演输入

目标：

- 输入栏支持“作为用户说话 / 作为导演说话”切换。
- 导演输入进入 stage instruction，不作为角色台词。
- 任意 DirectorMode 下用户都可以临时导演介入。

测试：

- director input 不进入普通 user message history。
- director input 能影响下一轮 prompt 的 Director Instructions。

## Phase 3：单轮多角色参与但单角色输出

目标：

- Stage 可绑定多个角色。
- Director/default policy 决定本轮主 speaker。
- Prompt 包含 active participants 的 persona 摘要。
- 模型仍只输出一个角色回复。

## Phase 4：Director agent mode

目标：

- Director agent 复用 AgentCore policy / diagnostics。
- Director agent 生成结构化 `DirectorPlan`。
- DirectorPlan 只用于 stage control，不直接显示为 assistant 回复。
- silent mode 下完全跳过 Director agent。

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
