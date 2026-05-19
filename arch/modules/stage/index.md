# Stage 系统

> 状态：Stage / Director 最小运行时已落地；多 speaker 输出 parser、LLM Director agent、独立 Stage 列表页和 UI 自动化仍未实现。
> 目标：把当前单角色 Chat 扩展为支持多角色共同参与的 Stage，同时引入可控的导演 agent。

2026-05-19 closeout：Stage foundation 已追加 `stage`、`stage_participant`、`stage_instruction` 三张表和 `message` speaker metadata；`ChatViewModel` 已能在 Chat Settings 中启用 Stage、绑定多个角色、切换 DirectorMode，并在输入栏切换 participant / director。正常 participant 输入会经 `DeterministicDirectorExecutor -> DirectorController` 选择一个 active speaker，把 `[Stage]`、`[Stage Participants]`、`[Director Instructions]` 注入当前 `PromptAssembler` 主链路；director 输入保存为隐藏 stage instruction，不保存为普通 user message，也不触发 API 请求。

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
  -> DirectorController
       -> deterministic speaker plan
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
  -> one staged assistant message with speaker metadata
```

当前仍只输出一个 assistant message；多角色连续输出、speaker block parser、schema repair 和多 message 拆分属于后续阶段。

## 5. 与 Background 的关系

Stage 负责“谁在场、谁发言、导演是否介入”。Background 负责“本轮给模型看什么背景”。

两者边界：

- Stage 不直接做 Memory/WorldBook 检索。
- Background 不决定最终角色发言内容。
- Director 可以给 BackgroundManager 提供 stage-level request，例如当前场景重点、参与角色、导演指令。
- BackgroundWorker 仍无发言权。

当前实现边界：Stage prompt 已接入 `BackgroundPacket` 后的 `PromptAssembler`，但还没有把 active participant / director instruction 作为 `BackgroundManager` source request 参数传入；背景检索仍沿用既有 Memory / WorldBook / BackgroundSource 规则。
