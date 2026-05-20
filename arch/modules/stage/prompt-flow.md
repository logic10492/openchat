# Stage Prompt Flow

> 状态：Stage prompt runtime 已接入 production `PromptAssembler` / Chat request shape；Responses API Stage snapshot、LLM Director agent prompt 和多 speaker parser 已有基础实现与测试。

2026-05-19 runtime closeout：`PromptAssembler.preview(...)` / `assemble(...)` 新增 `stageTurnPlan: StageTurnPlan?` 兼容参数。Stage enabled 时，`ChatViewModel+Support.generateResponse(...)` 会先执行 `DeterministicDirectorExecutor`，再把 `StageTurnPlan` 传入 Preview / Context / Assemble 链路。Stage blocks 保持现有四层 prompt 结构：Stage Identity 与 participants 属于 Stable Identity；Director Instructions 属于 Current-Turn Context，位于 BackgroundPacket 输出后、Current Turn 前。

2026-05-20 closeout：Stage enabled + Responses API 的 request snapshot 已由 `ChatViewModelPromptAssemblyTests.test_sendMessage_responsesMode_foldsStageBlocksIntoInstructionsInOrder` 覆盖，验证 `[Stage]`、`[Stage Participants]`、`[Director Instructions]` folding 到 `instructions` 后保持顺序，且 director instructions 不进入 `input` user messages。

## 1. 目标 Prompt 层次

Stage prompt 应在现有四层 prompt 基础上扩展，而不是完全推翻。

目标顺序：

1. Stage Identity：舞台规则、导演模式、多角色输出约束。
2. Character Personas：参与角色的 persona 摘要。
3. Stable Conversation State：压缩 checkpoint 或截断后的历史。
4. Current Background：BackgroundPacket 输出的世界书、记忆、角色状态、场景状态。
5. Director Instructions：用户或导演 agent 的本轮舞台指令。
6. Current Turn：用户输入 + 时间。

2026-05-19 Director foundation 先新增 `StagePromptLayerPlan.defaultLayerOrder`，用测试锁定 `Director Instructions` 位于 `Current Background` 之后、`Current Turn` 之前。runtime closeout 随后把同一顺序落到 production `PromptAssembler`：`StageTurnPlan.stageIdentityPrompt` 和 `participantPrompt` 进入 stable identity messages；`directorInstructionPrompt` 进入 current-turn context messages。

## 2. Director 输入位置

用户以导演身份说话时：

- 输入进入 `Director Instructions`。
- 不作为普通 user-to-character 台词。
- 是否让角色“听见”该指令应是显式选项。

当前实现：`StageInstruction.userDirected(...)` 默认 `visibility == hiddenFromCharacters`，但 prompt runtime 会把保存的 stage instructions 注入 `[Director Instructions]`，作为对模型的舞台控制信息；它不以普通 `user` history message 形式出现。后续如果需要“角色可见 / debug only / 完全隐藏”三种效果差异，需要在 prompt policy 中继续拆分 visibility semantics。

Director agent 模式下：

- DirectorPlan 进入 `Director Instructions` 或 hidden stage-control block。
- 不直接作为 assistant message。

## 3. Background 请求

Stage 会影响 Background request：

```swift
struct StageBackgroundContext: Sendable {
    let activeParticipantIds: [String]
    let directorInstructions: [StageInstruction]
    let sceneFocus: String?
}
```

BackgroundManager 可用这些字段筛选：

- 当前在场角色相关 memory。
- 当前场景相关 world book entries。
- 与导演指令相关的背景条目。

## 4. 输出解析

当前默认仍要求模型优先输出单角色回复；当模型输出 speaker blocks 时，完成后会解析并拆分为多条 staged assistant messages。

单角色回复第一阶段保持自然流式文本，不强制动作/台词 schema。模型可以自然使用 Markdown 斜体表现动作：

```text
*她停下脚步，指尖轻轻碰了碰杯沿。*

“你刚才那句话，是认真的吗？”
```

UI 可在完整消息可用后做轻量展示适配，例如把独立斜体段落渲染为动作块。流式过程中以原始文本增量显示为优先，不为了动作/台词拆分阻塞 streaming。普通角色回复不进入 AgentCore runtime，也不开放工具调用。

强制 `[ACTION]` / `[SPEECH]`、JSON schema 或半包 parser repair 暂不进入 Stage 第一阶段；如果后续需要，应作为单独的 streaming parser 计划。

多角色输出支持以下结构化边界：

```text
[Speaker: character-id-a]
...
[/Speaker]

[Speaker: character-id-b]
...
[/Speaker]
```

解析失败 fallback：

- 把全部内容归给主 speaker。
- 记录 diagnostics。
- 不丢失模型输出。

## 5. 与 Responses API 的风险

Responses API 会把 system messages 合并到 `instructions`。Stage 的多层 system block 在 Responses 模式下可能不保持 Chat Completions 的 message 序列形态。

需要单独测试：

- Stage Identity 是否在 instructions 中保序。
- Background block 是否仍在 Current Turn 之前表达。
- Director Instructions 是否不会被误当作普通用户台词。

2026-05-19 runtime closeout 已通过 Chat Completions request capture 覆盖 `[Stage]`、`[Stage Participants]`、`[Director Instructions]` 的生产 request shape。2026-05-20 已补充 Responses API folding snapshot，验证 Stage blocks 不乱序、不变成 user message。
