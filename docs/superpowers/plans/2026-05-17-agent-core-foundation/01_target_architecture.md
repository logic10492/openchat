# 01. 目标架构

## 目标

AgentCore 是后台 agent / worker 的共享执行基座，第一版必须足够支撑三类 consumer：

- `BackgroundWorker`：确定性后台员工，选择、排序、裁剪 background candidates。
- `DirectorAgent`：后台导演，输出结构化 `DirectorPlan`，不替角色写台词。
- `LibManAgent`：图书管理员，后续可用 LLM + Exa，输出带 citations 的草稿，写库必须经用户确认。

它不是普通角色回复 runtime。角色仍是 persona，由主聊天模型根据角色卡、历史、背景和当前输入生成自然流式回复。

## Core contract

### Identity

```swift
struct AgentDescriptor: Sendable, Codable, Equatable {
    let id: String
    let kind: AgentKind
    let displayName: String
    let version: String
    let purpose: String
}

enum AgentKind: String, Codable, Sendable, CaseIterable {
    case backgroundWorker
    case director
    case librarian
    case reflect
    case relationshipUpdater
    case conversationStateTracker
}
```

### Capability / Policy

`AgentPolicy` 不只记录允许能力，也要包含工具、副作用和确认策略：

```swift
struct AgentPolicy: Sendable, Equatable {
    let allowedCapabilities: Set<AgentCapability>
    let tokenBudget: AgentTokenBudget
    let timeoutSeconds: Double
    let retryPolicy: AgentRetryPolicy
    let schemaRepairPolicy: SchemaRepairPolicy
    let visibilityPolicy: AgentVisibilityPolicy
    let toolUsePolicy: ToolUsePolicy
    let sideEffectPolicy: SideEffectPolicy
    let confirmationPolicy: ConfirmationPolicy
}
```

第一版应提供 policy profile，避免每个 consumer 重复手写：

```swift
extension AgentPolicy {
    static func backgroundWorkerDefault() -> AgentPolicy
    static func directorDefault(allowsLLM: Bool) -> AgentPolicy
    static func librarianDraftDefault() -> AgentPolicy
}
```

### Task / Result

```swift
protocol AgentTask: Sendable {
    associatedtype Input: Sendable
    associatedtype Output: Sendable

    var descriptor: AgentDescriptor { get }
    var policy: AgentPolicy { get }
    func run(input: Input, context: AgentExecutionContext) async throws -> AgentExecutionResult<Output>
}

struct AgentExecutionContext: Sendable, Equatable {
    let requestId: String
    let now: Date
    let localeIdentifier: String
}

struct AgentExecutionResult<Output: Sendable>: Sendable {
    let output: Output
    let diagnostics: AgentDiagnostics
}
```

### Diagnostics

Diagnostics 是审计材料，不是 prompt 内容：

```swift
struct AgentDiagnostics: Sendable {
    let taskName: String
    let agent: AgentDescriptor
    let policy: AgentPolicy
    let startedAt: Date
    let endedAt: Date?
    let inputSummary: [String: String]
    let selectedIds: [String]
    let omittedIds: [String]
    let fallbackReason: String?
    let toolUsage: [AgentToolUsage]
    let tokenUsage: AgentTokenUsage?
    let schemaValidation: SchemaValidationResult?
    let errors: [AgentDiagnosticError]
}
```

第一版 diagnostics 可以只内存返回，不做持久化和 UI 展示。

### Executor

第一版只落地 deterministic executor：

```swift
protocol AgentExecutor: Sendable {
    func execute<Task: AgentTask>(
        task: Task,
        input: Task.Input,
        context: AgentExecutionContext
    ) async throws -> AgentExecutionResult<Task.Output>
}
```

`DeterministicAgentExecutor` 必须校验：

- `policy.allowedCapabilities` 是 executor 支持集合的子集。
- 不允许 `llm`、`webSearch`、`databaseWrite`。
- `sideEffectPolicy.allowDatabaseWrite == false`。
- `toolUsePolicy.allowNetwork == false`。

LLM executor 和 ToolBroker 只设计 contract，不在本计划实现。

## Consumer policy profile

| Consumer | 第一阶段 runtime | allowedCapabilities | Tool / Network | DB write | 用户可见输出 |
|---|---:|---|---|---|---|
| `BackgroundWorker` | 后续 | `.deterministic`, `.internalDiagnostics` | 禁止 | 禁止 | 默认不显示 |
| `DirectorAgent` | 后续 | `.deterministic`, 可选 `.llm`, `.internalDiagnostics` | 禁止 | 禁止 | 仅导演面板/调试 |
| `LibManAgent` | 后续 | `.llm`, `.webSearch`, `.userVisibleDraft`, `.internalDiagnostics` | 仅允许 Exa | 用户确认后 app flow 写 | 草稿可见 |

## 非目标保持

- 不把角色卡角色变成 `AgentTask`。
- 不让普通角色调用工具。
- 不把角色回复强制 JSON / tagged block 化。
- 不把 diagnostics 拼入 prompt。
- 不让 AgentCore 替代 `PromptAssembler`、`ContextManager`、`APIClient`、`DatabaseManager`。
