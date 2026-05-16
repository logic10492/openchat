# 04. Phase B：Executor 与 Diagnostics

## 目标

让 AgentCore 不只是 DTO 集合，而是具备最小可测试的执行约束：

- deterministic executor 可以运行 `AgentTask`。
- executor 会拒绝超出自身能力的 policy。
- diagnostics 能稳定记录执行者、策略、selected / omitted ids、fallback、tool usage 和错误。
- 错误使用 typed `LocalizedError`。

## 实现内容

新增或补完：

```text
OpenChat/Core/AgentCore/AgentDiagnostics.swift
OpenChat/Core/AgentCore/SchemaValidation.swift
OpenChat/Core/AgentCore/AgentExecutor.swift
OpenChat/Core/AgentCore/DeterministicAgentExecutor.swift
OpenChat/Core/AgentCore/AgentError.swift
```

## DeterministicAgentExecutor

第一版能力集合：

```swift
let supportedCapabilities: Set<AgentCapability> = [
    .deterministic,
    .internalDiagnostics,
]
```

执行前校验：

- `task.policy.allowedCapabilities` 必须是 `supportedCapabilities` 子集。
- `task.policy.toolUsePolicy.allowNetwork == false`。
- `task.policy.sideEffectPolicy.allowDatabaseWrite == false`。
- timeout / retry 第一版可只作为 policy 数据存在，不实现复杂调度；但 tests 要证明值被保存在 diagnostics policy 中。

如果违反，抛出：

```swift
enum AgentError: LocalizedError, Sendable, Equatable {
    case capabilityDenied(agentId: String, capability: AgentCapability)
    case networkDenied(agentId: String)
    case databaseWriteDenied(agentId: String)
    case executionFailed(agentId: String, message: String)
}
```

错误枚举具体 shape 可按 Swift 编译要求调整，但必须 typed，不使用泛 `Error`。

## Diagnostics

第一版不做持久化，只随 `AgentExecutionResult` 返回。

必须能表达：

- task name
- agent descriptor
- policy snapshot
- started / ended
- input summary
- selected ids
- omitted ids
- fallback reason
- tool usage
- token usage
- schema validation
- errors

建议添加便捷 builder / static helper，但不要引入复杂 logger 或 DB 写入。

## SchemaValidation

第一版只定义结构，不实现 parser：

```swift
struct SchemaValidationResult: Sendable, Equatable {
    let isValid: Bool
    let repaired: Bool
    let errors: [String]
}
```

用于后续 LLM executor；不要在本阶段解析角色回复。

## 测试要求

新增：

```text
OpenChatTests/Core/AgentCoreTests/DeterministicAgentExecutorTests.swift
OpenChatTests/Core/AgentCoreTests/AgentDiagnosticsTests.swift
```

覆盖：

- deterministic executor 可以运行只含 `.deterministic` / `.internalDiagnostics` 的 fake task。
- executor 拒绝 `.llm`。
- executor 拒绝 `.webSearch` 或 `toolUsePolicy.allowNetwork == true`。
- executor 拒绝 `sideEffectPolicy.allowDatabaseWrite == true`。
- result diagnostics 保留 selected / omitted ids。
- thrown `AgentError` 有可读 `localizedDescription`。

## 完成定义

- AgentCore 有可执行闭环，但只支持 deterministic。
- Policy enforcement 有测试，不只是文档约束。
- Diagnostics 可用于 BackgroundWorker 后续审计。
- 没有引入网络、数据库、UI 或 Prompt 行为。
