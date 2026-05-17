# 05. Phase 5C - Diagnostics 与 Tests

## 目标

完善 Background 专属 diagnostics，确保 worker 选择过程可审计，但不把 diagnostics 注入 prompt。

建议文件：

```text
OpenChat/Core/Background/BackgroundDiagnostics.swift
OpenChatTests/Core/BackgroundTests/BackgroundDiagnosticsTests.swift
```

## Diagnostics 字段

至少记录：

- `requestId`
- `startedAt`
- `endedAt`
- `elapsedMilliseconds`
- `policyProfile`
- `agentPolicySummary`
- `sourceSummaries`
- `inputCandidateCount`
- `selectedIds`
- `omitted`
- `fallbacks`
- `warnings`

建议：

```swift
struct BackgroundDiagnostics: Sendable, Equatable {
    let requestId: String
    let startedAt: Date
    let endedAt: Date?
    let elapsedMilliseconds: Double?
    let policyProfile: [String: String]
    let agentPolicySummary: [String: String]
    let sourceSummaries: [BackgroundSourceSummary]
    let inputCandidateCount: Int
    let selectedIds: [String]
    let omitted: [BackgroundOmission]
    let fallbacks: [String]
    let warnings: [String]
}

struct BackgroundSourceSummary: Sendable, Equatable {
    let sourceType: BackgroundSourceType
    let candidateCount: Int
    let selectedCount: Int
    let omittedCount: Int
    let fallback: String?
}
```

## 与 AgentCore 的关系

Background diagnostics 可以引用或投影 `AgentDiagnostics`，但不应把 Background 业务字段硬塞进 AgentCore。

原则：

- AgentCore 记录通用 task / policy / executor 信息。
- BackgroundDiagnostics 记录 source counts、selected / omitted、fallback tiers、budget details。
- Manager 后续可合并 source tool diagnostics 和 worker diagnostics。

## 测试重点

- diagnostics selected ids 与 packet entries 一致。
- omitted reason 与 worker 决策一致。
- source summary 按 `.memory` / `.worldBook` 分组。
- elapsed time 可注入 deterministic clock 或允许非负断言。
- diagnostics 不出现在 prompt content。
- policy denial 也能返回可审计错误或 diagnostics snapshot。

## Phase 5 Closeout

Phase 5 完成时必须记录：

- DTO 文件列表。
- Worker 文件列表。
- Diagnostics 文件列表。
- Focused tests 结果。
- 明确未接入 Chat / Prompt。
- 明确 worldBook rebuild 未迁移、未触发。

## 完成定义

- Diagnostics tests 覆盖 source summary、selected / omitted、fallback、elapsed、policy summary。
- Worker tests 更新为断言 diagnostics。
- Phase 5 closeout harness 中没有 Phase 6 runtime claim。
- `PromptAssemblerTests` 和 `ChatViewModelPromptAssemblyTests` 可作为 regression guard 跑过或记录未运行原因。

## 测试命令

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/BackgroundDiagnosticsTests' '-only-testing:OpenChatTests/BackgroundWorkerTests'
```

Phase 5 closeout focused：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/BackgroundPacketTests' '-only-testing:OpenChatTests/BackgroundWorkerTests' '-only-testing:OpenChatTests/BackgroundDiagnosticsTests' '-only-testing:OpenChatTests/BackgroundSourceTests' '-only-testing:OpenChatTests/AgentPolicyTests' '-only-testing:OpenChatTests/DeterministicAgentExecutorTests'
```

## 写回要求

- Source：`Core/Background` diagnostics + tests only。
- Docs：更新 `arch/modules/background/architecture.md`、`background-worker.md`、`migration-plan.md` 的 Phase 5 当前状态。
- Harness：新增或更新 `harness/<date>/background-worker-prompt-switch/index.md`，记录 Phase 5 完成证据和 Phase 6 未完成项。
