# 01. Target Architecture

## 目标分层

目标架构保持 OpenChat 的单向依赖：

```text
Features/Chat
  -> Core/Background
  -> Core/Memory / Core/WorldBook / Core/AgentCore
  -> Core/Database / Core/Networking
  -> Shared
```

`Core/Background` 的职责是“本轮给主聊天模型看什么背景”，不是“生成回复”。

目标数据流：

```text
Phase 5:
BackgroundCandidate[]
  -> BackgroundWorkerInput
  -> deterministic BackgroundWorker
  -> BackgroundPacket + BackgroundDiagnostics

Phase 6:
ChatViewModel.generateResponse
  -> BackgroundManager.prepare(...)
  -> MemoryBackgroundSource / WorldBookBackgroundSource
  -> BackgroundWorker
  -> BackgroundPacket
  -> BackgroundAssembler compatible blocks
  -> PromptAssembler.preview / assemble
  -> APIClient.streamMessage
```

## Phase 5 边界

Phase 5 只能落在 `Core/Background` 与 matching tests：

- DTO：`BackgroundPolicy`、`BackgroundWorkerInput`、`BackgroundPacket`、`BackgroundEntry`、`BackgroundOmission`、`BackgroundDiagnostics`。
- Worker：只消费 `[BackgroundCandidate]`，输出 `BackgroundPacket`。
- Diagnostics：记录 selected / omitted / source counts / fallback / elapsed / policy profile。

Phase 5 不允许：

- 不接 `ChatViewModel`。
- 不接 `PromptAssembler`。
- 不改 `DependencyContainer`。
- 不调用 `MemoryManager` / `WorldBookSource`。
- 不触发 WorldBook rebuild。
- 不联网、不调用 LLM、不写 DB、不生成 assistant message。

## Phase 6 边界

Phase 6 才允许把 Phase 5 输出接入主链路：

- `BackgroundManager` 负责 source 协调和 pre-source orchestration。
- `BackgroundAssembler` 把 `BackgroundPacket` 转成兼容 prompt blocks。
- `PromptAssembler` 消费 packet/block，不做 recall、不做 cross-source 排序。
- `ChatViewModel` 调用 `BackgroundManager.prepare(...)`，不再分别拥有 Memory / WorldBook 最终注入权。
- `DependencyContainer` 装配 manager、worker、source adapters。

Phase 6 第一版输出必须优先兼容：

```text
[World Book Entries]
...
[/World Book Entries]

[Memories]
...
[/Memories]
```

统一 `[Background]` 仅作为后续可选：

```text
[Background]
[World]
...
[Memory]
...
[/Background]
```

## WorldBook rebuild side-effect 归属

当前 `ChatViewModel+Support.swift` 中的 bounded worldBook rebuild 是 source 召回前的兼容 side-effect。它不属于 worker。

允许的迁移路径只有一种：

```text
BackgroundManager.prepare(...)
  -> pre-source stage: optionally bounded WorldBook rebuild
  -> WorldBookBackgroundSource.candidates(...)
  -> BackgroundWorker.run(...)
```

要求：

- `BackgroundWorker` 仍不触发 rebuild。
- `WorldBookBackgroundSource` 仍不触发 rebuild。
- 若迁移 rebuild，必须新增独立 tests 证明 rebuild 发生在 manager pre-source stage。
- 若不迁移 rebuild，Chat 兼容 side-effect 可以暂时保留，但需要在 harness 中声明。

## Diagnostics 可观测性

Background diagnostics 不是 prompt 内容。它应支持 debug、harness、测试断言：

- source 调用列表。
- 每个 source candidate count。
- selected ids。
- omitted ids + reasons。
- fallback tiers。
- elapsed time。
- policy profile。
- side-effect stage 记录，特别是 worldBook rebuild 是否执行、由谁执行。

## 完成定义

- Phase 5 可以在不触碰 Chat / Prompt 的情况下通过 focused tests。
- Phase 6 切换后，主 prompt 输出文本保持兼容，行为变化来自 packet source，而不是格式变化。
- `BackgroundWorker` 权限边界由代码和 tests 双重保证。
- worldBook rebuild 边界有明确测试或 harness 说明。

## 测试命令

Phase 5：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/BackgroundWorkerTests' '-only-testing:OpenChatTests/BackgroundDiagnosticsTests' '-only-testing:OpenChatTests/AgentPolicyTests' '-only-testing:OpenChatTests/DeterministicAgentExecutorTests'
```

Phase 6：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/BackgroundManagerTests' '-only-testing:OpenChatTests/PromptAssemblerTests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests'
```

## 写回要求

- Source：Phase 5 写 `Core/Background`；Phase 6 才写 manager / prompt / chat / DI。
- Docs：同步 `arch/modules/background/architecture.md`、`background-worker.md`、`migration-plan.md`、`prompt-assembly.md`、`chat.md`。
- Harness：Phase 5 与 Phase 6 分别记录 completion、tests、未迁移项和 side-effect boundary。
