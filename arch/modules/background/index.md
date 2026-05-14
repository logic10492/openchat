# Background 系统

> 状态：目标架构规划，尚未实现。
> 目标：把 WorldBook、Memory、角色卡派生状态和会话状态统一整理为主聊天模型可消费的 background prompt。

Background 系统不是新的对话角色，也不是让多个 agent 轮流发言。它把后台劳动拆给无发言权的 worker：它们只能选择、整理、排序和返回条目，最终回复仍由主聊天模型根据角色卡和当前输入生成。

## 1. 核心原则

1. **角色不是 agent**：对话角色是由角色卡、关系状态、长期记忆、世界背景和当前会话状态共同渲染出的 persona，不拥有工具权、任务队列或自治输出权。
2. **后台员工无发言权**：`BackgroundWorker` 只能返回结构化 background 条目，不能产生 assistant message，不能改写用户输入。
3. **图书管理员不参与 RP 输出**：`LibMan` 可用 Exa 搜索帮助用户创建角色卡/世界书素材，但输出是可审阅草稿，不进入主聊天实时链路。
4. **Prompt 文本确定性生成**：worker 返回 `BackgroundPacket`，最终 `[Background]` 文本由 deterministic assembler 生成。
5. **事实与计划分离**：当前源码仍是 WorldBook keyword block + Memory block 直接进入 `PromptAssembler`；本目录描述的是下一阶段改造方向。

## 2. 目标数据流

```text
User input
  -> ChatViewModel
  -> BackgroundManager.prepare(...)
       -> MemoryBackgroundSource.candidates(...)
       -> WorldBookBackgroundSource.candidates(...)
       -> CharacterBackgroundSource.candidates(...)
       -> ConversationStateBackgroundSource.candidates(...)
       -> BackgroundWorker.select(...)
       -> BackgroundPacket
  -> BackgroundAssembler.makePromptBlock(packet)
  -> PromptAssembler.assemble(...)
  -> APIClient.streamMessage(...)
```

## 3. 文档结构

| 文档 | 内容 |
|---|---|
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
| `BackgroundCandidate` | 来源返回的可选条目，带 source、id、content、score metadata |
| `BackgroundWorker` / 后台员工 | 无发言权的后台选择器，只能返回 packet |
| `BackgroundPacket` | 本轮要注入 prompt 的最终条目集合和诊断信息 |
| `BackgroundAssembler` | 把 packet 确定性转换成 `[Background]` prompt block |
| `LibMan` / 图书管理员 | 有 web search 工具权的素材构建 agent，不参与主聊天输出 |
