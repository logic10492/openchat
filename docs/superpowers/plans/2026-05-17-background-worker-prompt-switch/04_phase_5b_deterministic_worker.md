# 04. Phase 5B - Deterministic BackgroundWorker

## 目标

实现第一版 deterministic `BackgroundWorker`。它只对已给定的 `BackgroundCandidate` 做选择、排序、去重和预算裁剪。

建议新增：

```text
OpenChat/Core/Background/BackgroundWorker.swift
OpenChatTests/Core/BackgroundTests/BackgroundWorkerTests.swift
```

## 输入输出

输入：

```text
BackgroundWorkerInput
  request
  candidates
  background policy
  AgentPolicy.backgroundWorkerDefault()
```

输出：

```text
BackgroundPacket
  entries
  omitted
  diagnostics
```

## 允许使用的信号

- `candidate.relevance`
- `candidate.basePriority`
- `candidate.recency`
- `candidate.sourceType`
- `candidate.metadata["semanticRank"]`
- `candidate.metadata["keywordRank"]`
- `candidate.metadata["priority"]`
- `candidate.metadata["importance"]`
- `candidate.metadata["fallback"]`
- content token estimate
- duplicate text similarity 的轻量 deterministic 规则

建议第一版 score：

```text
score =
  relevanceScore
  + sourceWeight
  + priorityTieBreaker
  + recencyTieBreaker
  - duplicatePenalty
  - fallbackPenalty
```

排序必须稳定：同分时按 source policy、原 candidate order、id 排序。

## 禁止事项

- 不调用 LLM。
- 不联网。
- 不写 DB。
- 不读 Memory / WorldBook DB。
- 不调用 `MemoryManager`。
- 不调用 `WorldBookSource`。
- 不触发 WorldBook rebuild。
- 不生成 `ChatMessage(role: "assistant")`。
- 不拼最终 prompt 文本。
- 不把 Memory / WorldBook 的 source 内部 rank fusion 复制一遍。

## AgentCore policy gate

Worker 入口必须检查 `agentPolicy`：

- 缺少 `.deterministic` 则拒绝。
- 如 policy 暗示 network / db write / llm 权限，不应因此启用这些行为。
- denial 使用 typed error，例如 `AgentError` 或 Background 专属 `LocalizedError`。

如果复用 `DeterministicAgentExecutor`，仍要保持 Background 业务算法在 `Core/Background`，不要把 Background 专属 scoring 塞进 AgentCore。

## 测试重点

- 相同 input 多次运行输出完全一致。
- semantic relevance 强于 memory importance 的不当覆盖。
- world-book priority 只在相关候选之间增强，不让低相关条目吞掉预算。
- per-source limit 生效。
- token budget 至少保留第一条可用候选，或按 policy 明确返回空。
- duplicate candidate 只保留更高分条目，omission reason 为 `duplicate`。
- policy denial 不产生 partial packet。
- worker 不调用任何 source closure；测试中只给 candidates。

## 完成定义

- `BackgroundWorkerTests` 覆盖排序、预算、去重、policy denial、跨源 limit。
- Phase 5 diff 仍不包含 Chat / Prompt / DI。
- Harness 记录 worker 没有 source / DB / network / LLM 依赖。
- Worker 输出只包含 `BackgroundPacket`，不包含 prompt block 字符串。

## 测试命令

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/BackgroundWorkerTests' '-only-testing:OpenChatTests/BackgroundPacketTests' '-only-testing:OpenChatTests/AgentPolicyTests' '-only-testing:OpenChatTests/DeterministicAgentExecutorTests'
```

Regression：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/BackgroundSourceTests' '-only-testing:OpenChatTests/MemoryRecallToolTests' '-only-testing:OpenChatTests/WorldBookRecallToolTests'
```

## 写回要求

- Source：`OpenChat/Core/Background/BackgroundWorker.swift` 和 focused tests。
- Docs：更新 `arch/modules/background/background-worker.md` 的 Level 0 当前实现证据。
- Harness：写明 deterministic scoring 规则、policy denial、禁止 side effects 的证据。
