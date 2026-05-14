# OpenChat Planning

> 更新时间：2026-05-13
> 状态：规划入口。本文记录目标架构和落地顺序，不代表当前源码已全部实现。

## 1. 当前重点

OpenChat 下一阶段的重点有两条主线：

1. 把角色扮演所需的背景上下文从“各模块分别注入 prompt”升级为“统一 Background 调度”。
2. 把单角色 Chat 扩展为支持多角色共同参与的 Stage。

```text
WorldBook + Memory + Character State + Conversation State
  -> BackgroundSource candidates
  -> BackgroundWorker / 后台员工
  -> BackgroundPacket
  -> BackgroundAssembler
  -> Main Chat Model
```

核心边界：

- 对话角色不是 agent，而是 persona。
- BackgroundWorker / 后台员工无权直接输出，只能返回要注入的 background 条目。
- LibMan / 图书管理员可以用 Exa 搜索构建素材，但不参与实时 RP 输出。
- Stage 可以有导演 agent，但导演也不替角色发言。
- Prompt 文本最终由确定性 assembler 生成，不能让后台 worker 自由发言。

## 2. 角色不是 Agent

原则：

> 对话角色不是 agent，而是由角色卡、关系状态、长期记忆、世界背景和当前会话状态共同渲染出的 persona。

角色不 agent 化的原因：

- 角色的核心价值是稳定扮演，不是自主完成任务。
- 主聊天模型已经负责角色回复，再包装 `CharacterAgent` 不会自然增加能力。
- agent 化会引入工具权、目标、任务队列和自治行为，容易破坏 RP 沉浸感。
- “血肉感”应来自可维护状态，而不是角色拥有后台权限。

参考文档：

- `arch/modules/background/role-boundary.md`

## 3. BackgroundWorker / 后台员工

职责：

- 汇总 Memory / WorldBook / Character / ConversationState 候选。
- 选择、排序、去重、冲突标记和预算裁剪。
- 返回 `BackgroundPacket`。
- 记录 diagnostics，供调试或详细统计使用。

禁止：

- 生成 assistant 回复。
- 改写用户输入。
- 静默修改角色卡、世界书或记忆。
- 直接拼接最终 prompt 文本。
- 调用 Exa 或其他 web search。

参考文档：

- `arch/modules/background/index.md`
- `arch/modules/background/architecture.md`
- `arch/modules/background/background-worker.md`
- `arch/modules/background/sources.md`

## 4. Memory 与 WorldBook 统一为 BackgroundSource

目标：

- `MemoryBackgroundSource` 负责长期记忆候选。
- `WorldBookBackgroundSource` 负责世界书候选。
- 两者都输出 `BackgroundCandidate`，由 BackgroundWorker 统一调度。
- Memory 和 WorldBook 不再分别拥有最终 prompt 注入权。

当前差异：

- 当前 Memory 仍由 `ChatViewModel` 调 `MemoryManager.retrieveMemories(...)`，再由 `PromptAssembler` 注入 `[Memories]`。
- 当前 WorldBook 仍由 `PromptAssembler` keyword trigger 后注入 `[World Book Entries]`。
- 目标架构会把这两条路径收敛到 Background。

参考文档：

- `arch/modules/memory/index.md`
- `arch/modules/memory/hindsight-lite.md`
- `arch/modules/world-book.md`
- `arch/modules/background/sources.md`

## 5. 世界书向量化

目标：

- 为 `world_book_entry` 建立 embedding 索引。
- 让世界书支持 keyword + semantic 双路召回。
- 让 BackgroundWorker 能公平比较世界书候选和记忆候选。

建议目标表：

```text
world_book_entry_embedding
  entry_id TEXT PRIMARY KEY
  embedding float[384]
```

可选审计表：

```text
world_book_entry_embedding_meta
  entryId TEXT PRIMARY KEY
  contentHash TEXT
  embeddedAt DATETIME
  embeddingModel TEXT
```

参考文档：

- `arch/modules/background/world-book-vectorization.md`

## 6. LibMan / 图书管理员

LibMan 是素材构建 agent，不是聊天 agent。

职责：

- 使用 Exa 搜索公开资料。
- 帮用户生成角色卡草稿。
- 帮用户生成世界书条目草稿。
- 保留 citations / grounding。
- 交给用户审阅确认后再写数据库。

边界：

- LibMan 可以联网；BackgroundWorker 不联网。
- LibMan 输出 draft；主聊天模型输出角色回复。
- LibMan 不参与实时 RP prompt。
- Exa 搜索失败不影响主聊天。
- 未经用户确认，LibMan 不静默写入角色卡或世界书。

参考文档：

- `arch/modules/background/lib-man.md`
- `arch/modules/exa.md`

## 7. Stage / 多角色舞台

Stage 是 Chat 的目标扩展形态。

目标：

- 一个 Stage 可以绑定多个角色卡。
- 多个角色可以在同一场景中共同参与。
- Stage 拥有 Director / 导演。
- 导演有三种工作模式：
  - `silent` / 闭嘴：导演不主动介入。
  - `agent` / agent 模式：导演后台调度场景、节奏、发言顺序和冲突提示。
  - `userControlled` / 用户接管模式：用户以导演身份直接发出舞台指令。
- 不论当前模式如何，用户都可以临时以导演角色说话。

边界：

- 角色仍不是 agent。
- 导演不替角色写最终台词。
- 导演输出是 `DirectorPlan` / stage instructions，不是 assistant message。
- 用户导演输入不应被保存为角色听到的普通台词，除非用户显式要求。

参考文档：

- `arch/modules/stage/index.md`
- `arch/modules/stage/director.md`
- `arch/modules/stage/multi-character.md`
- `arch/modules/stage/prompt-flow.md`
- `arch/modules/stage/migration-plan.md`

## 8. Hindsight-lite 关系

Hindsight-lite 不应替代 Background，而应成为 Background 的一部分：

- retain：Memory 继续负责长期记忆抽取与持久化，下一步补 source range / provenance / dedupe metadata。
- recall：Memory 先输出有序 `MemoryRecallResult`，再作为候选给 BackgroundWorker，而不是直接进 prompt。
- reflect：只做低频整理或显式用户操作，输出带 `basedOn` 的 observation，不进入每轮主聊天链路。

优先顺序：

1. 修复 Memory recall ordering，避免 `importance` 覆盖语义相关性。
2. 增加 `MemoryRecallTrace`，记录 distance、fallback reason、selected ids 和 omitted ids。
3. 将 recent fallback 改为 keyword + recent high-value 分层 fallback。
4. 增加 source range / provenance / dedupe metadata。
5. 将 Memory 输出包装成 `BackgroundCandidate`。
6. 低频 reflect 产出带 `basedOn` 的 observation。

参考文档：

- `arch/modules/memory/hindsight-lite.md`
- `arch/AntiEntropy/problem.md`

## 9. 建议落地顺序

### Phase 0：规划固化

- 保持 `arch/modules/background/*` 为目标架构文档。
- 明确所有 Background / LibMan 内容尚未实现。
- 后续修改源码前先更新对应计划或 issue。

### Phase 1：Background DTO + deterministic worker

- 新增 `Core/Background` DTO。
- 用确定性规则实现 BackgroundWorker。
- 先包装现有 Memory / WorldBook 结果，不改数据库 schema。

### Phase 2：Memory ordering 修复

- `PromptAssembler.trim(memories:)` 不再按 `importance` 覆盖 retrieval order。
- 增加测试锁定语义相关性优先。

### Phase 2.5：Hindsight-lite recall / retain 完善

- 新增内部 `MemoryRecallResult` / `MemoryRecallTrace` contract。
- 把 semantic failure、no hit、empty index、budget dropped 分成不同 fallback tier。
- 追加 provenance companion table，记录 source sortOrder/message ids、confidence、tags、dedupeKey。
- 升级 extraction prompt 到 retain v2，但兼容当前 v1 JSON。

### Phase 3：世界书向量化

- 追加 migration。
- 建立 world book entry embedding。
- WorldBookSource 同时支持 keyword 和 semantic candidates。

### Phase 4：Prompt 切换到 BackgroundPacket

- Chat 链路调用 `BackgroundManager.prepare(...)`。
- `PromptAssembler` 消费 Background packet/block。
- 逐步替换 `[World Book Entries]` + `[Memories]` 直接注入。

### Phase 5：LibMan

- 接入 Exa search。
- 产出 `LibrarianDraft`。
- 用户确认后写入 CharacterCard / WorldBook。
- 写入世界书后触发 embedding rebuild。

### Phase 6：低频 reflect / observation synthesis

- 只在手动整理或后台低频任务中运行。
- 产物必须带 `basedOn` source ids。
- 不直接替代原始记忆。

### Phase 7：Stage 基础 DTO

- 新增 Stage / participant / director DTO。
- 不改变现有 Chat UI。
- 建立导演模式和用户导演输入的测试边界。

### Phase 8：用户导演输入

- 输入栏支持“作为用户说话 / 作为导演说话”。
- 导演输入进入 stage instruction。
- 任意导演模式下用户都能临时接管。

### Phase 9：多角色 Stage

- Stage 绑定多个角色。
- Director/default policy 选择本轮主 speaker。
- 第一阶段只输出一个角色回复，后续再扩展多角色连续输出。

## 10. 当前已知未完成

- Background 系统尚未实现。
- LibMan 尚未实现。
- Stage 系统尚未实现。
- Director agent / 导演模式尚未实现。
- 多角色同场参与尚未实现。
- 世界书尚未向量化。
- Memory recall ordering P1 仍打开。
- Background diagnostics / 检索可观测性尚未实现。
- Responses API system folding 对 Background block 的实际位置仍需单独审计。
