# 00. Source Baseline

## 必读文件

实施前必须读当前源码，而不是只按计划书想象接口：

- `AGENTS.md`
- `arch/modules/background/background-worker.md`
- `arch/modules/background/migration-plan.md`
- `arch/modules/background/architecture.md`
- `arch/modules/background/world-book-vectorization.md`
- `arch/modules/memory/index.md`
- `arch/modules/memory/retrieval-prompt.md`
- `arch/modules/world-book.md`
- `arch/modules/agent-core.md`
- `OpenChat/Core/Memory/MemoryManager.swift`
- `OpenChat/Core/Memory/MemoryRecallModels.swift`
- `OpenChat/Core/WorldBook/WorldBookSource.swift`
- `OpenChat/Core/WorldBook/WorldBookRecallModels.swift`
- `OpenChat/Core/AgentCore/AgentPolicy.swift`
- `OpenChat/Core/AgentCore/DeterministicAgentExecutor.swift`
- `OpenChat/Features/Chat/ViewModels/ChatViewModel+Support.swift`
- `OpenChat/Core/PromptEngine/PromptAssembler.swift`

## 当前实现事实

Memory 当前事实：

- `MemoryManager.retrieveMemories(...)` 是旧兼容入口，返回 `[MemoryEntryRecord]`。
- `MemoryManager.recallMemories(...)` 是 tool 应包装的结构化入口，返回 `MemoryRecallResult`。
- `MemoryRecallResult.entries` 已包含 `finalRank`、semantic / keyword / recency rank、semantic distance 和 reasons。
- `MemoryRecallTrace` 已包含 query、candidate counts、selected ids、omitted 和 fallback。
- Background 接入时必须继续要求 MemorySource candidate order 保持 semantic relevance；importance 不能覆盖当前相关性。

WorldBook 当前事实：

- `WorldBookSource.recallEntries(...)` 是 tool 应包装的结构化入口，返回 `WorldBookRecallResult`。
- `WorldBookRecallResult.entries` 已包含 final rank、keyword rank、semantic rank、semantic distance、keyword hits 和 reasons。
- `WorldBookRecallTrace` 已包含 query summary、candidate counts、selected ids 和 omissions。
- 世界书向量化、CRUD/import/delete 维护和手动 rebuild 已完成。
- 当前 Chat 主链路仍输出 `[World Book Entries]` block。

AgentCore 当前事实：

- `AgentPolicy.backgroundWorkerDefault()` 已存在。
- deterministic executor 已能拒绝 LLM、network / web、database write 等越权能力。
- AgentCore 当前是 foundation，不是 Background runtime。

Prompt 当前事实：

- 当前主路径仍是 `ChatViewModel.generateResponse -> PromptAssembler.preview/assemble -> APIClient.streamMessage`。
- PromptAssembler 仍直接消费 world book entries 和 memories 的兼容输入。
- Phase 4 不允许改 prompt 注入。

## 实施前 propagation audit

开始写 Swift 前先记录一次轻量传播审计，至少回答：

- 新增 tool contract 会影响哪些 Core 文件？
- Memory tool 是否只依赖 `MemoryManager.recallMemories(...)`？
- WorldBook tool 是否只依赖 `WorldBookSource.recallEntries(...)`？
- 是否有任何计划会提前碰 `PromptAssembler` 或 `ChatViewModel+Support`？
- 是否有任何计划会让 BackgroundWorker 或 tool 触发 DB write / rebuild / network？

如果审计发现需要提前改 Chat / Prompt，停止并拆出新计划，不把该改动塞进 Phase 4。

## 工作区边界

实施前运行：

```bash
git status --short
```

当前可能存在与本计划无关的未跟踪 `comp_swap/`。不要因为本计划清理、移动或提交它，除非用户明确要求。
