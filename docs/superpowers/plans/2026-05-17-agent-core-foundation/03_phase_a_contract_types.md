# 03. Phase A：Contract Types

## 目标

落地 AgentCore 的类型骨架，使后台 worker / agent 可以共享同一套身份、权限、任务外壳和执行上下文。

Phase A 不实现业务 consumer，不接入 DI，不改 Chat。

## 实现内容

新增目录：

```text
OpenChat/Core/AgentCore/
```

建议文件：

```text
AgentDescriptor.swift
AgentCapability.swift
AgentPolicy.swift
ToolUsePolicy.swift
SideEffectPolicy.swift
AgentTask.swift
AgentExecutionContext.swift
AgentExecutionResult.swift
```

## 类型要求

### AgentDescriptor

- `Sendable`
- `Codable`
- `Equatable`
- `id` 必须由 consumer 稳定指定，不在 descriptor 内自动生成。
- `version` 用于后续 diagnostics 和 harness 证据。

### AgentKind

必须包含：

```swift
case backgroundWorker
case director
case librarian
case reflect
case relationshipUpdater
case conversationStateTracker
```

如实现 `CaseIterable`，tests 要锁定 raw value，防止将来改名破坏持久 diagnostics。

### AgentCapability

必须包含：

```swift
case deterministic
case llm
case webSearch
case databaseRead
case databaseWrite
case userVisibleDraft
case internalDiagnostics
```

### AgentPolicy

必须包含：

- capability set
- token budget
- timeout
- retry policy
- schema repair policy
- visibility policy
- tool use policy
- side effect policy
- confirmation policy

建议附带静态 profile：

```swift
static func backgroundWorkerDefault() -> AgentPolicy
static func directorDefault(allowsLLM: Bool = false) -> AgentPolicy
static func librarianDraftDefault() -> AgentPolicy
```

Profile 验收：

- BackgroundWorker profile 不含 `.llm`、`.webSearch`、`.databaseWrite`。
- Director 默认不含 `.webSearch`、`.databaseWrite`。
- Librarian draft 可含 `.llm`、`.webSearch`、`.userVisibleDraft`，但 `confirmationPolicy.requiredForPersistentWrite == true`。

### AgentTask / Context / Result

`AgentTask` 使用 associated types：

```swift
protocol AgentTask: Sendable {
    associatedtype Input: Sendable
    associatedtype Output: Sendable

    var descriptor: AgentDescriptor { get }
    var policy: AgentPolicy { get }
    func run(input: Input, context: AgentExecutionContext) async throws -> AgentExecutionResult<Output>
}
```

`AgentExecutionContext` 第一版只放：

- `requestId`
- `now`
- `localeIdentifier`

不要在 context 中放 DB、APIClient 或 tool broker；这些属于后续 executor / consumer 注入边界。

## 测试要求

新增：

```text
OpenChatTests/Core/AgentCoreTests/AgentDescriptorTests.swift
OpenChatTests/Core/AgentCoreTests/AgentPolicyTests.swift
```

覆盖：

- descriptor Codable round-trip。
- `AgentKind` raw value 稳定。
- background policy 禁止 LLM / web / DB write。
- director policy 可选 LLM 但不允许 web / DB write。
- librarian draft policy 允许 web search，但 persistent write 需要 confirmation。

## 完成定义

- Phase A 类型能独立编译。
- Tests 能证明三类 consumer 的权限边界已经类型化。
- 没有任何 Chat / Prompt / Memory / WorldBook 行为变化。
