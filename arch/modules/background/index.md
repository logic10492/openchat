# Background 系统

> 状态：已实现 Phase 4A-4D source tools/adapters、2026-05-17 Phase 5/6 deterministic BackgroundWorker / BackgroundPacket / BackgroundManager / BackgroundAssembler / Chat-Prompt compatible switch，并已追加 CharacterState / ConversationState sources、Stage context filter、LibMan offline draft runtime 和 idle reflect draft worker。统一 `[Background]` block、Exa ToolBroker、LibMan apply UI、自动 synthesis 写入和 duplicate/conflict review 仍未实现。
> 目标：把 WorldBook、Memory、角色卡派生状态和会话状态统一整理为主聊天模型可消费的 background prompt。

Background 系统不是新的对话角色，也不是让多个 agent 轮流发言。它把后台劳动拆给无发言权的 worker：它们只能选择、整理、排序和返回条目，最终回复仍由主聊天模型根据角色卡和当前输入生成。

BackgroundWorker 复用 `AgentCore` 的 identity、policy、diagnostics 和 execution result contract，并只启用 deterministic capability；这不会把对话角色 agent 化。

顺序约束：BackgroundWorker 不直接接 raw Memory / WorldBook 内部实现。2026-05-17 Phase 4A-4D 已先把 Memory 与 WorldBook 的现有召回能力暴露为内部 read-only source tool / adapter，再由 `BackgroundSource` 产出候选；2026-05-17 Phase 5/6 已让 deterministic `BackgroundWorker` 消费候选、输出 `BackgroundPacket`，并由 Chat/Prompt 兼容切换使用 packet 来源。这里的 tool 是后台源码边界，不是普通角色 tool call，也不是用户可见工具。

## 1. 核心原则

1. **角色不是 agent**：对话角色是由角色卡、关系状态、长期记忆、世界背景和当前会话状态共同渲染出的 persona，不拥有工具权、任务队列或自治输出权。
2. **后台员工无发言权**：`BackgroundWorker` 只能返回结构化 background 条目，不能产生 assistant message，不能改写用户输入。
3. **图书管理员不参与 RP 输出**：`LibMan` 当前可用 LLM + 用户提供素材生成带引用的可审阅草稿；目标架构可再接 Exa 搜索，但无论是否联网都不进入主聊天实时链路。
4. **Prompt 文本确定性生成**：worker 返回 `BackgroundPacket`，当前 `BackgroundAssembler` 先生成兼容 `[World Book Entries]` / `[Memories]` block；统一 `[Background]` block 是后续可选迁移。
5. **AgentCore 不等于角色 agent 化**：`AgentCore` 是后台能力共享运行时基座；角色回复第一阶段保持自然流式文本，不给普通角色回复开放 tool call。
6. **事实与计划分离**：当前源码已具备 source tools/adapters、deterministic worker、manager、assembler、Chat/Prompt compatible switch、Character/ConversationState sources、Stage context filter、LibMan offline draft runtime 和 idle reflect draft worker；统一 `[Background]`、Exa ToolBroker、LibMan apply UI、自动 synthesis 写入和 duplicate/conflict review 仍是后续计划。

## 2. 目标数据流

```text
User input
  -> ChatViewModel
  -> BackgroundManager.prepare(...)
	       -> MemoryRecallTool / MemoryBackgroundSource.candidates(...)
	       -> WorldBookRecallTool / WorldBookBackgroundSource.candidates(...)
	       -> CharacterStateBackgroundSource.candidates(...)
	       -> ConversationStateBackgroundSource.candidates(...)
	       -> BackgroundWorker.select(...)
       -> BackgroundPacket
  -> BackgroundAssembler compatible `[World Book Entries]` / `[Memories]` blocks
  -> PromptAssembler.assemble(...)
  -> APIClient.streamMessage(...)
```

## 3. 文档结构

| 文档 | 内容 |
|---|---|
| [../agent-core.md](../agent-core.md) | AgentCore 基座：后台 agent/worker 的 identity、policy、capability、diagnostics、executor 共享骨架 |
| [architecture.md](architecture.md) | Background 层模块边界、依赖方向和与 PromptAssembler 的关系 |
| [background-worker.md](background-worker.md) | 后台员工职责、无输出权约束、选择/排序/裁剪 contract |
| [sources.md](sources.md) | Memory、WorldBook、Character、ConversationState 作为 BackgroundSource 的统一候选接口 |
| [world-book-vectorization.md](world-book-vectorization.md) | 世界书向量化、keyword + semantic 混合召回和迁移建议 |
| [lib-man.md](lib-man.md) | 图书管理员 agent：Exa 搜索、角色卡/世界书草稿生成、引用和用户确认 |
| [role-boundary.md](role-boundary.md) | 为什么对话角色不是 agent，以及角色血肉感应由状态模型承担 |
| [migration-plan.md](migration-plan.md) | 从当前 WorldBook/Memory 直接注入迁移到 BackgroundPacket 的分阶段计划 |

## 4. 名词表

| 名词 | 含义 |
|---|---|
| `Background` | 主模型回复前需要知道的背景上下文，不等同于角色回复 |
| `BackgroundSource` | 候选条目来源，例如 Memory 或 WorldBook |
| `SourceTool` / source tool | 后台 read-only source 暴露层，包装现有 Memory/WorldBook recall result，供 BackgroundSource adapter 消费 |
| `BackgroundCandidate` | 来源返回的可选条目，带 source、id、content、score metadata |
| `BackgroundWorker` / 后台员工 | 无发言权的后台选择器，只能返回 packet |
| `BackgroundPacket` | 本轮要注入 prompt 的最终条目集合和诊断信息 |
| `BackgroundAssembler` | 把 packet 确定性转换成兼容 prompt blocks；统一 `[Background]` block 尚未默认启用 |
| `LibMan` / 图书管理员 | 素材构建 agent，不参与主聊天输出；当前 runtime 为 offline cited draft，Exa web search broker 仍是目标架构 |
| `AgentCore` | 后台 agent/worker 共享的任务、权限、执行和诊断基座，不用于普通角色回复自治 |
