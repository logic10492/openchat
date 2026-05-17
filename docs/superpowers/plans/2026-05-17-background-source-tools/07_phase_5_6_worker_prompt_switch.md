# 07. Phase 5/6 - Worker 与 Prompt Switch 后置计划

> 本文件是后续阶段计划。不要在 Phase 4 未完成时执行本文件的 runtime 修改。

## Phase 5A - Background DTO

新增：

```text
OpenChat/Core/Background/BackgroundPolicy.swift
OpenChat/Core/Background/BackgroundPacket.swift
OpenChat/Core/Background/BackgroundDiagnostics.swift
```

目标 DTO：

```swift
struct BackgroundWorkerInput: Sendable {
    let request: BackgroundRequest
    let candidates: [BackgroundCandidate]
    let policy: BackgroundPolicy
    let agentPolicy: AgentPolicy
}

struct BackgroundPacket: Sendable {
    let entries: [BackgroundEntry]
    let omitted: [BackgroundOmission]
    let diagnostics: BackgroundDiagnostics
}
```

## Phase 5B - Deterministic BackgroundWorker

第一版 worker 只允许 deterministic capability：

- semantic relevance
- keyword hit
- world-book priority
- memory importance
- recency
- source policy
- duplication penalty
- contradiction / low-confidence marker
- token budget trim

必须复用：

```swift
AgentPolicy.backgroundWorkerDefault()
```

禁止：

- 不调用 LLM。
- 不联网。
- 不写 DB。
- 不生成 assistant message。
- 不直接调用 MemoryManager / WorldBookSource。
- 不触发 WorldBook rebuild。

## Phase 5C - Diagnostics

`BackgroundDiagnostics` 至少记录：

- source 调用列表。
- 每个 source 返回 candidate 数。
- selected ids。
- omitted ids + reasons。
- fallback tiers。
- elapsed time。
- policy profile。

Background 专有 diagnostics 留在 Background 层，不硬塞回 AgentCore。

## Phase 6A - BackgroundManager

`BackgroundManager.prepare(...)` 负责：

```text
BackgroundRequest
  -> MemoryBackgroundSource / WorldBookBackgroundSource
  -> candidates
  -> BackgroundWorker
  -> BackgroundPacket
```

Manager 可以协调 source 调用，但不能把 source 内部排序搬出来。

## Phase 6B - BackgroundAssembler

第一阶段输出可保持兼容格式：

```text
[World Book Entries]
...
[/World Book Entries]

[Memories]
...
[/Memories]
```

但 entries 来源必须来自 `BackgroundPacket`。

第二阶段再统一：

```text
[Background]
[World]
...

[Memory]
...
[/Background]
```

## Phase 6C - Chat / Prompt switch

允许修改：

- `OpenChat/App/DependencyContainer.swift`
- `OpenChat/Features/Chat/ViewModels/ChatViewModel+Support.swift`
- `OpenChat/Core/PromptEngine/PromptAssembler.swift`
- matching prompt/chat tests

切换原则：

- `PromptAssembler` 只消费 packet/block，不召回、不排序。
- ChatViewModel 只调用 `BackgroundManager.prepare(...)`，不分别拥有 Memory / WorldBook 最终注入权。
- 当前输入、time context、history compression 顺序必须重新审计，避免重复输入或 block 顺序漂移。

## 后续非默认阶段

不要混入默认 BackgroundWorker：

- Level 1 LLM-assisted selector：只能 JSON 选 candidate ids，不生成新 facts，必须显式启用 llm capability。
- Level 2 synthesis：低频 observation synthesis，必须带 `based_on` ids，默认不进入每轮聊天。
- LibMan / Exa：素材构建 agent，用户确认后才写角色卡 / 世界书；不参与主 RP 每轮输出。
