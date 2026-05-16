# 00. 传播审计

## 审计模式

本次为窄范围新增基座审计：

- 新增 Core 层 contract，不改现有 runtime behavior。
- 当前没有可复用的 OpenChat 静态 import graph 脚本，因此采用文件级传播审计 + 行为链路审计。
- 审计目标是确定第一阶段允许修改的代码块，避免 AgentCore 落地时误切 Background 或 Chat prompt 主链路。

## 当前静态传播面

### App / DI

证据：

- `OpenChat/App/DependencyContainer.swift` 当前持有 `databaseManager`、`apiClient`、`contextManager`、`memoryManager`、`worldBookEmbeddingIndexer`、`worldBookSource`、`titleGenerator`。
- `DependencyContainer` 当前没有 agent / background executor 字段。

结论：

- Phase A/B 不修改 `DependencyContainer`。
- 只有 BackgroundWorker 实现阶段才新增 `backgroundManager`、`backgroundWorker` 或 `agentExecutor` 注入。

### Chat 主链路

证据：

- `OpenChat/Features/Chat/ViewModels/ChatViewModel+Support.swift` 中 `generateResponse(...)` 负责保存用户消息、提取记忆、召回世界书、召回记忆、preview、history、assemble、stream。
- 世界书当前通过 `recallWorldBookEntries(...)` 先调用 `WorldBookEmbeddingIndexer.rebuildMissingOrStale(...)`，再调用 `WorldBookSource.recallEntries(...)`。
- 记忆当前通过 `MemoryManager.retrieveMemories(...)` 返回 `[MemoryEntryRecord]`。

结论：

- Phase A/B 不修改 `ChatViewModel.swift` 或 `ChatViewModel+Support.swift`。
- BackgroundWorker 阶段才允许把 `retrieveMemories(...)` / `recallWorldBookEntries(...)` 收敛到 `BackgroundManager.prepareBackground(...)`。
- 任何改动若导致 `APIClient.streamMessage(...)` 入参变化，必须另开 Prompt switch 阶段，不能混入 AgentCore。

### PromptEngine

证据：

- `PromptAssembler.preview(...)` 当前直接计算 world-book / memory / example-dialog budgets。
- `PromptAssembler.assemble(...)` 当前输出顺序是 stable identity -> processed history -> current-turn context blocks -> current turn。
- `PromptAssembler` 仍生成 `[World Book Entries]` 与 `[Memories]` blocks。

结论：

- Phase A/B 不修改 `PromptAssembler.swift` 或 `PromptAssemblyModels.swift`。
- BackgroundPacket 阶段才新增 `BackgroundPacket` 消费入口或 `BackgroundPromptBlock`。
- 不在本计划里调整 Responses API system folding。

### Memory

证据：

- `MemoryManager.recallMemories(...)` 已输出 `MemoryRecallResult` / `MemoryRecallTrace`。
- `MemoryRecallModels.swift` 已有 selected ids、omitted、fallback、semantic / keyword / recent reasons。

结论：

- Phase A/B 不修改 Memory 源码。
- 后续 `MemoryBackgroundSource` 只应包装 `recallMemories(...)`，不复制 recall 排序逻辑。
- Memory retain / reflect / provenance 不属于 AgentCore 第一阶段。

### WorldBook

证据：

- `WorldBookSource.recallEntries(...)` 已输出 `WorldBookRecallResult` / `WorldBookRecallTrace`。
- `WorldBookRecallModels.swift` 已有 selected ids、omissions、semanticUnavailable、staleEmbedding、limitExceeded。

结论：

- Phase A/B 不修改 WorldBook 源码。
- 后续 `WorldBookBackgroundSource` 只应包装 `WorldBookSource.recallEntries(...)`，不复制 semantic + keyword fusion。
- Bounded rebuild 是否继续放在 Chat 或移动到 BackgroundManager，应在 Background 计划包单独审计。

### Database / Networking / UI

结论：

- Phase A/B 不新增 migration，不改 GRDB records，不读写数据库。
- Phase A/B 不改 `APIClient`、`ResponsesAPIRequest`、SSE parser 或 model parameters。
- Phase A/B 不新增 UI 文案，不改 SwiftUI Views。

## 第一阶段允许修改的代码块

允许新增：

```text
OpenChat/Core/AgentCore/
  AgentDescriptor.swift
  AgentCapability.swift
  AgentPolicy.swift
  AgentTask.swift
  AgentExecutionContext.swift
  AgentExecutionResult.swift
  AgentDiagnostics.swift
  AgentExecutor.swift
  DeterministicAgentExecutor.swift
  ToolUsePolicy.swift
  SideEffectPolicy.swift
  SchemaValidation.swift
  AgentError.swift

OpenChatTests/Core/AgentCoreTests/
  AgentDescriptorTests.swift
  AgentPolicyTests.swift
  DeterministicAgentExecutorTests.swift
  AgentDiagnosticsTests.swift
```

允许生成：

```text
OpenChat.xcodeproj/project.pbxproj
```

前提是新增 Swift 文件需要进入 Xcode project，且只能通过 `scripts/generate_xcodeproj.rb` 生成，不手工改签名配置。

允许同步文档：

```text
arch/modules/agent-core.md
arch/modules/background/background-worker.md
arch/modules/background/architecture.md
PLANING.md
docs/superpowers/plans/2026-05-17-agent-core-foundation/*
```

## 第一阶段禁止修改的代码块

```text
OpenChat/App/DependencyContainer.swift
OpenChat/Features/Chat/ViewModels/ChatViewModel.swift
OpenChat/Features/Chat/ViewModels/ChatViewModel+Support.swift
OpenChat/Core/PromptEngine/PromptAssembler.swift
OpenChat/Core/PromptEngine/PromptAssemblyModels.swift
OpenChat/Core/Memory/*
OpenChat/Core/WorldBook/*
OpenChat/Core/Database/*
OpenChat/Core/Networking/*
OpenChat/Features/*/Views/*
OpenChat/Resources/Localizable.xcstrings
```

例外：如果 AgentCore tests 暴露 Xcode project 未包含新文件，只允许 project generation，不允许借机改业务行为。

## 行为传播风险

| 风险 | 触发条件 | 本计划处理 |
|---|---|---|
| AgentCore 偷偷进入 Chat 主链路 | 在 `generateResponse(...)` 注入 executor 或 worker | 禁止，延后到 Background 计划 |
| BackgroundWorker 变成自由 LLM agent | 第一阶段给 worker `llm` / `webSearch` capability | policy profile 中禁止 |
| policy 只是文档没有 enforcement | executor 不校验 capability / side effect policy | Phase B 必测 deterministic executor policy denial |
| diagnostics 泄漏到聊天 UI | diagnostics 被拼入 prompt 或 assistant message | AgentCore diagnostics 默认内部可见 |
| 角色被 agent 化 | 新增 `PersonaRender` 或普通角色 tool call | 明确禁止，本计划不处理 |
| Xcode project 漏文件 | 新 Swift 文件未加入 target | 用 generator 接入并运行 focused tests |

## 审计结论

AgentCore 第一阶段的正确传播面是“新增 Core contract + tests + docs”，不是“接入运行时”。只有当 AgentCore contract 编译并测试通过后，才进入 BackgroundSource / BackgroundWorker 计划包，届时再审计 DI、Chat、Prompt、Memory、WorldBook 的行为传播。
