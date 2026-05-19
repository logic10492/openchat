# 00. Source Baseline / 修改前传播审计

## 审计模式

窄范围传播审计。当前任务是计划包整理，不修改 Swift source。审计目标是确认 Phase 6 Director 的影响面，避免把 Stage DB/UI、多角色输出或 Chat 主链路切换提前混入本阶段。

## 必读文档

- `PLANING.md`
- `arch/modules/stage/index.md`
- `arch/modules/stage/director.md`
- `arch/modules/stage/multi-character.md`
- `arch/modules/stage/prompt-flow.md`
- `arch/modules/stage/migration-plan.md`
- `arch/modules/agent-core.md`
- `arch/AntiEntropy/problem.md`
- `arch/AntiEntropy/propagation-audit.md`
- `arch/AntiEntropy/triangle-consistency.md`

## 当前源码事实

### 已实现的前置能力

- `OpenChat/Core/AgentCore/AgentDescriptor.swift`
  - `AgentKind.director = "director"` 已存在。
- `OpenChat/Core/AgentCore/AgentPolicy.swift`
  - `AgentPolicy.directorDefault(allowsLLM:)` 已存在。
  - deterministic director 默认不含 `.llm`。
  - LLM director 可含 `.llm`，但仍不含 `.webSearch` / `.databaseWrite`。
  - `toolUsePolicy` 仍禁用 network。
  - `sideEffectPolicy` 仍禁用 database write。
- `OpenChatTests/Core/AgentCoreTests/AgentPolicyTests.swift`
  - 已覆盖 director policy 可选 LLM 但禁止 web / database write。

### 尚未实现的能力

- 没有 `OpenChat/Core/Stage/` 或 `OpenChat/Core/Director/` runtime 目录。
- 没有 `DirectorPlan` / `DirectorInput` / `StageInstruction` / `DirectorDiagnostics` Swift type。
- 没有 Director executor / controller。
- 没有 Stage persistence table。
- `ConversationRecord` 仍是单主角色会话，字段包括 `characterCardId`、`customScenario`、`slowPlotMode` 等；没有 director mode / stage id / participant metadata。
- `MessageRecord` 仍用 `role` + `content` + `reasoningContent` 表示消息；没有 speaker metadata 或 stage input role。
- 当前 `ChatViewModel.generateResponse(...)` 仍保存普通 user message，再走 BackgroundManager / PromptAssembler / APIClient 主链路；没有区分 user speaking as participant vs director。
- `PromptAssembler` 已支持 `BackgroundPacket` compatible blocks，但没有 Stage Identity / Director Instructions block。

## 行为传播链路

当前生产主链路：

```text
ChatViewModel.generateResponse
  -> save MessageRecord(role: "user")
  -> optional memory extraction
  -> bounded WorldBookEmbeddingIndexer.rebuildMissingOrStale(...)
  -> BackgroundManager.prepare(...)
  -> PromptAssembler.preview(... backgroundPacket:)
  -> ContextManager.prepareHistory(...)
  -> PromptAssembler.assemble(... backgroundPacket:)
  -> APIClient.streamMessage(...)
  -> save MessageRecord(role: "assistant")
```

Phase 6 Director contract 不应直接改这条链路。只有后续 Stage prompt integration 才允许把 Director Instructions 接入 request body。

## 预计影响面

Phase 6 contract 可能新增：

- `OpenChat/Core/Stage/DirectorMode.swift`
- `OpenChat/Core/Stage/DirectorPlan.swift`
- `OpenChat/Core/Stage/StageInstruction.swift`
- `OpenChat/Core/Stage/DirectorDiagnostics.swift`
- `OpenChatTests/Core/StageTests/DirectorContractTests.swift`
- `OpenChatTests/Core/AgentCoreTests/AgentPolicyTests.swift` 小幅补充

文档写回：

- `arch/modules/stage/director.md`
- `arch/modules/stage/prompt-flow.md`
- `arch/modules/stage/migration-plan.md`
- `PLANING.md`
- `arch/AntiEntropy/propagation-audit.md`
- `arch/AntiEntropy/triangle-consistency.md`
- `harness/<date>/director-mode-foundation/`

## 禁止提前传播的范围

- `OpenChat/Core/Database/Migrations.swift`
- `OpenChat/Core/Database/Records/ConversationRecord.swift`
- `OpenChat/Core/Database/Records/MessageRecord.swift`
- `OpenChat/Features/Chat/Views/InputBarView.swift`
- `OpenChat/Features/Chat/ViewModels/ChatViewModel+Support.swift`
- `OpenChat/Core/PromptEngine/PromptAssembler.swift`
- `OpenChat/Core/Background/*`
- `OpenChat/Resources/Localizable.xcstrings`

这些文件可在后续 Phase 7/8/9/10 被计划化处理；Phase 6 第一版只建立 contract 和测试边界。

## Drift 风险

| 风险 | 触发方式 | 计划包约束 |
|---|---|---|
| Director 被当成 assistant | 把 `DirectorPlan` 存成 `MessageRecord(role: "assistant")` | 明确 DirectorPlan 是 stage control，不是 chat message |
| 用户导演输入污染角色听到的台词 | 把 director input 直接保存为普通 `role == "user"` message | Phase 6 先建 `StageInputRole` / `StageInstruction` contract，UI/DB 留后续 |
| 角色被 agent 化 | 给普通角色 tool / task queue / AgentCore runtime | Phase 6 只建 Director contract，不改角色回复 runtime |
| 提前引入 Stage schema | 为 director mode 修改 conversation/message migration | Phase 6 禁止 DB migration |
| Prompt shape 漂移 | 直接把 Director Instructions 注入现有 Chat prompt | Phase 6 只建 prompt boundary contract，不切主链路 |

## 结论

Phase 6 应作为 Director contract foundation。当前只整理计划包，不需要代码改动。后续实施时，第一批 source 修改应限于 Core 层 contract types 与 focused tests。
