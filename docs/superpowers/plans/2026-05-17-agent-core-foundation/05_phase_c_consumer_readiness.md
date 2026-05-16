# 05. Phase C：Consumer Readiness

## 目标

完成 AgentCore 与后续 consumer 的接口对齐，但不在本计划里实现 consumer。

重点是确认 BackgroundWorker、Director、LibMan 分别需要什么，避免后续各自重复实现 policy、diagnostics、executor 和 tool boundary。

## Memory / WorldBook source tool 前置条件

下一计划包不应直接实现 BackgroundWorker。先完成内部 read-only source tool：

```swift
struct MemoryRecallTool {
    func call(...) async throws -> MemoryRecallResult
}

struct WorldBookRecallTool {
    func call(...) async throws -> WorldBookRecallResult
}
```

要求：

- `MemoryRecallTool` 只包装 `MemoryManager.recallMemories(...)`。
- `WorldBookRecallTool` 只包装 `WorldBookSource.recallEntries(...)`。
- 不复制 Memory rank fusion 或 WorldBook keyword+semantic fusion。
- 不写 DB、不联网、不拼 prompt、不生成 assistant message。
- 不给普通角色回复开放 tool call。

## BackgroundWorker 接入条件

source tool / adapter 边界完成后，BackgroundWorker 应实现为：

```swift
struct BackgroundWorker: AgentTask {
    typealias Input = BackgroundWorkerInput
    typealias Output = BackgroundPacket
}
```

依赖 AgentCore：

- `AgentDescriptor(kind: .backgroundWorker, ...)`
- `AgentPolicy.backgroundWorkerDefault()`
- `DeterministicAgentExecutor`
- `AgentDiagnostics` selected / omitted / fallback 投影到 `BackgroundDiagnostics`

仍由 Background 层自有：

- `BackgroundRequest`
- `BackgroundCandidate`
- `BackgroundEntry`
- `BackgroundPacket`
- `BackgroundDiagnostics`
- source-specific score / rank / omission reason

禁止：

- BackgroundWorker 调用 LLM。
- BackgroundWorker 联网。
- BackgroundWorker 写 DB。
- BackgroundWorker 拼最终 prompt 文本。

## Director 接入条件

Director 后续可以是 deterministic 或 LLM-assisted，但输出只能是：

```swift
DirectorInput -> DirectorPlan
```

依赖 AgentCore：

- `AgentDescriptor(kind: .director, ...)`
- `AgentPolicy.directorDefault(allowsLLM:)`
- diagnostics 记录 speaker plan、stage instructions、fallback

禁止：

- Director 替角色写最终台词。
- Director 写 DB。
- Director 联网。
- Director 把内部分析作为 assistant message。

## LibMan 接入条件

LibMan 后续可用 LLM + Exa，但写入必须走用户确认后的 app flow：

```swift
LibrarianRequest -> LibrarianDraft
```

依赖 AgentCore：

- `AgentDescriptor(kind: .librarian, ...)`
- `AgentPolicy.librarianDraftDefault()`
- `ToolUsePolicy(allowedToolNames: ["exa"], allowNetwork: true, requireCitations: true)`
- `ConfirmationPolicy(requiredForDraftApply: true, requiredForPersistentWrite: true)`
- diagnostics 记录 citations、tool usage、warnings

禁止：

- LibMan 静默写角色卡或世界书。
- LibMan 参与实时 RP 回复。
- Exa 搜索失败影响主聊天。

## 角色输出适配边界

本计划不实现：

- `PersonaRender`
- 普通角色 tool call
- `[ACTION]` / `[SPEECH]` schema
- JSON / tagged block streaming repair

当前策略：

- 角色回复保持自然流式文本。
- Markdown 斜体动作可继续由现有渲染处理。
- 若未来要做动作/台词拆分，应单独设计 streaming adapter，先证明不会阻塞增量显示。

## 文档写回

Phase C 只把“AgentCore 已可供 consumer 复用”的实现证据写回：

- `arch/modules/agent-core.md`
- `arch/modules/background/background-worker.md`
- `arch/modules/stage/director.md`
- `arch/modules/background/lib-man.md`
- `PLANING.md`

不能把 BackgroundWorker、Director、LibMan 写成已实现。
同时不能把“下一步”写成直接实现 BackgroundWorker；应记录 Memory / WorldBook source tool 暴露是 BackgroundWorker 前置条件。
