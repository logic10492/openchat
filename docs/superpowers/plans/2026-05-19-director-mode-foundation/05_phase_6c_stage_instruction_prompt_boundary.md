# 05. Phase 6C - Stage Instruction / Prompt Boundary

## 目标

定义 Director Instructions 将来如何进入 Stage prompt，同时不改当前 Chat / Prompt production path。

## 目标 prompt 顺序

后续 Stage prompt 应扩展现有四层 prompt，而不是完全推翻：

```text
Stage Identity
Character Personas
Stable Conversation State
Current Background
Director Instructions
Current Turn
```

Director Instructions 位于 Current Background 之后、Current Turn 之前。这样用户导演指令不会混入普通 conversation history，也不会被误当作当前 user-to-character text。

## Phase 6 不做什么

- 不修改 `PromptAssembler.preview(...)` / `assemble(...)` 的生产 overload。
- 不修改 `ChatViewModel.generateResponse(...)`。
- 不新增 `StagePromptAssembler` runtime。
- 不把 Director Instructions 注入当前 API request body。
- 不实现 Responses API request-shape snapshot。

## Contract helper 可选项

如果 Phase 6 实施时需要测试 prompt boundary，可以新增纯 helper：

```swift
struct StagePromptLayerPlan: Sendable, Equatable {
    let stageIdentity: String?
    let characterPersonas: [String]
    let backgroundBlockIds: [String]
    let directorInstructionIds: [String]
}
```

该 helper 只能表达顺序 contract，不能接入 production prompt。

## Responses API 风险

Responses API 会把 system messages fold 到 `instructions`。后续真正接入 Stage prompt 时必须测试：

- Stage Identity 保序。
- Director Instructions 不被拼进 ordinary user input。
- Current Turn user content 只出现一次。
- Background block 仍在 Current Turn 之前。

Phase 6 只记录这些风险，不声称已经解决。

## 与 Background 的关系

Director Instructions 可以作为 future `StageBackgroundContext`：

```swift
struct StageBackgroundContext: Sendable {
    let activeParticipantIds: [String]
    let directorInstructions: [StageInstruction]
    let sceneFocus: String?
}
```

Phase 6 不修改 `BackgroundRequest`。如后续要让 BackgroundManager 消费 Stage context，应另起阶段并补 source / prompt regression tests。

## 验收红线

不能 closeout 的情况：

- Director Instructions 已注入 production prompt，但没有 request-shape tests。
- 用户导演输入作为普通 `role == "user"` message 进入 history。
- Stage prompt 改变 current input 去重防线。
- Prompt 输出被改成强制 JSON / tagged schema。
- DirectorPlan 被保存为 assistant message。

## 完成定义

- 文档明确 Director Instructions 的目标 prompt 位置。
- 当前生产 Chat/Prompt path 未被 Phase 6 文档误写成 Stage 已接入。
- 后续 request-shape 风险被记录到 testing / handoff。
