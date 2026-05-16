# AgentCore 基座设计

> 状态：AgentCore foundation 已落地并完成 closeout；BackgroundWorker / Director / LibMan runtime 仍未实现。
> 目标：为 BackgroundWorker、Director、LibMan、reflect / state updater 等后台能力提供共享的任务执行、权限和诊断骨架，避免每个 agent/worker 各自重复实现运行时约束。

AgentCore 是后续后台能力的基座，不是临时最小实现，也不是“把角色 agent 化”的入口。OpenChat 的对话角色仍是 persona；角色回复由主聊天模型根据角色卡、历史、Background 和当前输入生成。角色回复的展示适配不属于 AgentCore 范围。

## 0. 当前实现证据

2026-05-17 closeout 已验证 `OpenChat/Core/AgentCore/` 下的 foundation contract：

- `AgentDescriptor.swift` / `AgentCapability.swift`：稳定 agent identity、`AgentKind`、capability raw values。
- `AgentPolicy.swift` / `ToolUsePolicy.swift` / `SideEffectPolicy.swift`：policy、token/retry/schema/visibility/confirmation profile；包含 `backgroundWorkerDefault()`、`directorDefault(allowsLLM:)`、`librarianDraftDefault()`。
- `AgentTask.swift` / `AgentExecutionContext.swift` / `AgentExecutionResult.swift`：typed task execution shell。
- `AgentDiagnostics.swift` / `SchemaValidation.swift`：diagnostics、tool usage、token usage、schema validation 和 diagnostic error DTO。
- `AgentExecutor.swift` / `DeterministicAgentExecutor.swift` / `AgentError.swift`：deterministic executor contract、policy denial 和 typed `LocalizedError`。

对应 focused tests 已出现在 `OpenChatTests/Core/AgentCoreTests/`：

- `AgentDescriptorTests.swift`
- `AgentPolicyTests.swift`
- `DeterministicAgentExecutorTests.swift`
- `AgentDiagnosticsTests.swift`

验证结果：

- AgentCore focused：`AgentDescriptorTests`、`AgentPolicyTests`、`DeterministicAgentExecutorTests`、`AgentDiagnosticsTests`，12 tests / 4 suites passed。
- 主链路回归 focused：`PromptAssemblerTests`、`ChatViewModelPromptAssemblyTests`、`MemoryManagerRetrievalTests`、`WorldBookSourceTests`，50 tests / 4 suites passed。
- Full suite：303 tests / 58 suites passed。
- `ruby scripts/generate_xcodeproj.rb` 已重新生成 Xcode project；AgentCore source/test 已进入 target，签名配置仍来自脚本中的既有值。

本页只把 AgentCore foundation contract 记为已实现。BackgroundWorker、Director、LibMan、LLM executor、ToolBroker 和 Background runtime 仍保持未实现边界。

仍未实现：

- `LLMAgentExecutor`
- `ToolBroker` / `ToolExecutor`
- `Core/Background`、`BackgroundWorker`、`BackgroundPacket`
- Director runtime
- LibMan runtime / Exa broker
- reflect executor / relationship updater / conversation state tracker runtime

## 1. 核心原则

1. **角色不是 runtime agent**：角色不拥有工具权、联网权、后台任务队列或静默写库权限。
2. **AgentCore 服务后台能力**：BackgroundWorker、Director、LibMan、reflect executor、relationship updater、conversation state tracker 可以共享运行时骨架。
3. **能力显式声明**：每个 agent 必须声明可用能力，例如是否可联网、是否可调用 LLM、是否可写数据库、是否可产生用户可见草稿。
4. **输出必须结构化**：agent 输出必须是 typed DTO 或 schema-validated JSON；自然语言解释不能作为隐式控制信号。
5. **策略先于执行**：任务运行前先解析 `AgentPolicy`，运行时不能临时扩大权限。
6. **诊断默认内部可见**：trace、omission、tool usage、schema repair 和错误原因进入 diagnostics，不默认暴露到主聊天 UI。

## 2. 非目标

- 不实现通用多 agent 协商框架。
- 不让多个 agent 在主聊天 UI 中暴露内部协作。
- 不为普通角色回复开放 tool call。
- 不为普通角色回复引入 blocking schema parser 或 runtime agent。
- 不让 BackgroundWorker、Director 或 reflect executor 直接生成最终角色台词。
- 不用 AgentCore 替代 `APIClient`、`PromptAssembler`、`ContextManager` 或数据库层。

## 3. AgentCore 暴露面

AgentCore 应暴露 6 类稳定 contract。业务模块可以分阶段实现 consumer，但 contract 本身要按后续 Director、BackgroundWorker、LibMan、reflect / state updater 的共同需求设计。

### 3.1 Agent Identity

每个 agent / worker 必须有稳定身份：

```swift
struct AgentDescriptor: Sendable, Codable, Equatable {
    let id: String
    let kind: AgentKind
    let displayName: String
    let version: String
    let purpose: String
}

enum AgentKind: String, Codable, Sendable {
    case backgroundWorker
    case director
    case librarian
    case reflect
    case relationshipUpdater
    case conversationStateTracker
}
```

用途：

- diagnostics / trace 能稳定记录是谁执行的。
- policy 可以按 `kind` 限权。
- 后续设置页可以开关某些后台能力。
- 测试、日志、harness 证据都能引用稳定 id。

### 3.2 Capability / Policy

能力和策略是 AgentCore 的核心。权限必须类型化，不能只靠文档约束：

```swift
enum AgentCapability: String, Codable, Sendable {
    case deterministic
    case llm
    case webSearch
    case databaseRead
    case databaseWrite
    case userVisibleDraft
    case internalDiagnostics
}

struct AgentPolicy: Sendable {
    let allowedCapabilities: Set<AgentCapability>
    let tokenBudget: AgentTokenBudget
    let timeoutSeconds: Double
    let retryPolicy: AgentRetryPolicy
    let schemaRepairPolicy: SchemaRepairPolicy
    let visibilityPolicy: AgentVisibilityPolicy
}
```

关键约束：

- BackgroundWorker 默认只允许 `deterministic` / `internalDiagnostics`。
- Director 可选 `llm`，但不允许 `webSearch` 或 `databaseWrite`。
- LibMan 可允许 `llm` / `webSearch` / `userVisibleDraft`，但数据库写入必须走用户确认后的 app flow。
- reflect / state updater 如需写入，必须带 provenance / based-on ids。

### 3.3 Task / Request / Result

AgentCore 不定义业务输入输出，只定义执行外壳：

```swift
protocol AgentTask: Sendable {
    associatedtype Input: Sendable
    associatedtype Output: Sendable

    var descriptor: AgentDescriptor { get }
    var policy: AgentPolicy { get }
    func run(input: Input, context: AgentExecutionContext) async throws -> AgentExecutionResult<Output>
}

struct AgentExecutionContext: Sendable {
    let requestId: String
    let now: Date
    let localeIdentifier: String
}

struct AgentExecutionResult<Output: Sendable>: Sendable {
    let output: Output
    let diagnostics: AgentDiagnostics
}
```

业务模块自己定义 DTO：

```text
BackgroundWorkerInput -> BackgroundPacket
DirectorInput -> DirectorPlan
LibrarianRequest -> LibrarianDraft
ReflectRequest -> ReflectObservation
```

### 3.4 Diagnostics / Trace

三个核心 consumer 都需要可观测性。AgentCore 应提供统一 `AgentDiagnostics`，业务模块可以附加领域专用 diagnostics：

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

Diagnostics 是审计材料，不是 prompt 内容。默认不展示给用户；只有 debug、导演面板、详细统计或 harness 证据需要时才展示经过筛选的信息。

### 3.5 Executor

AgentCore 不把执行方式写死：

```swift
protocol AgentExecutor: Sendable {
    func execute<Task: AgentTask>(
        task: Task,
        input: Task.Input,
        context: AgentExecutionContext
    ) async throws -> AgentExecutionResult<Task.Output>
}
```

目标 executor：

- `DeterministicAgentExecutor`：本地规则执行，用于 BackgroundWorker 第一阶段。
- `LLMAgentExecutor`：调用 LLM 得到 schema-validated 输出，用于 Director / reflect / LibMan。
- `ToolBroker` / `ToolExecutor`：受 `ToolUsePolicy` 管控的工具调用入口，优先服务 LibMan 的 Exa。

### 3.6 Tool / Side Effect Boundary

工具和副作用必须显式建模：

```swift
struct ToolUsePolicy: Sendable {
    let allowedToolNames: Set<String>
    let allowNetwork: Bool
    let requireCitations: Bool
}

struct SideEffectPolicy: Sendable {
    let allowDatabaseRead: Bool
    let allowDatabaseWrite: Bool
    let requiresUserConfirmationForWrite: Bool
}

struct ConfirmationPolicy: Sendable {
    let requiredForDraftApply: Bool
    let requiredForPersistentWrite: Bool
}
```

特别约束：

- BackgroundWorker 不使用工具、不联网、不写库。
- Director 不联网、不写库，只产出 `DirectorPlan`。
- LibMan 可以联网和生成 draft，但不能静默写角色卡或世界书；写入必须由用户确认后的 app flow 执行。

## 4. Consumer 需求矩阵

| Agent / Worker | 是否 runtime agent | LLM | Tool / 网络 | 写 DB | 用户可见输出 | 说明 |
|---|---:|---:|---:|---:|---:|---|
| `BackgroundWorker` | 是，受限 | L0 否；后续可选 L1 | 不可联网 | 不写 | 默认不显示 | 选择、排序、裁剪 background candidates |
| `DirectorAgent` | 是，受限 | 可选 | 不联网 | 不写 | 仅导演面板/调试可见 | 生成 `DirectorPlan`，不写角色台词 |
| `LibManAgent` | 是 | 可用 | 可用 Exa | 仅用户确认后写 | 草稿可见 | 生成角色卡/世界书草稿和 citations |
| `ReflectAgent` | 是，低频 | 可用 | 不联网 | 写入需 provenance | 默认不显示 | 生成 observation / relationship update，必须带 based-on ids |

| 需求 | BackgroundWorker | DirectorAgent | LibManAgent |
|---|---|---|---|
| 核心任务 | 选背景 | 舞台调度 | 素材构建 |
| 输入 DTO | `BackgroundWorkerInput` | `DirectorInput` | `LibrarianRequest` |
| 输出 DTO | `BackgroundPacket` | `DirectorPlan` | `LibrarianDraft` |
| 执行器 | deterministic | deterministic 或 LLM | LLM + tool |
| 网络 | 禁止 | 禁止 | 允许 Exa |
| 写库 | 禁止 | 禁止 | 用户确认后由 app flow 写 |
| 失败策略 | fallback 到空/低配背景 | fallback 到 silent/default plan | 返回失败或部分草稿 |
| diagnostics 重点 | selected / omitted / fallback | speaker plan / instructions | citations / warnings / tool usage |

## 5. 目标目录建议

```text
Core/AgentCore/
  AgentDescriptor.swift
  AgentCapability.swift
  AgentPolicy.swift
  AgentTask.swift
  AgentExecutionContext.swift
  AgentExecutionResult.swift
  AgentDiagnostics.swift
  AgentExecutor.swift
  DeterministicAgentExecutor.swift
  LLMAgentExecutor.swift
  ToolUsePolicy.swift
  SideEffectPolicy.swift
  SchemaValidation.swift
```

## 6. 角色回复展示与 AgentCore 的关系

角色回复保持主聊天模型的自然流式文本输出。第一阶段不把角色回复改成 AgentCore task，也不要求模型输出 blocking JSON / tagged schema。

可接受的展示适配：

- 模型自然输出的 Markdown 斜体动作继续按 Markdown 渲染。
- UI 可以在完整消息落库后做轻量 display adapter，例如识别独立斜体段落并用动作样式展示。
- 流式过程中以原始文本优先，避免为了动作/台词拆分阻塞增量显示。

暂不纳入 AgentCore：

- `PersonaRender` runtime。
- 普通角色 tool call。
- 强制 `[ACTION]` / `[SPEECH]` schema。
- 半包 JSON / tagged block 的复杂 streaming repair。

如果后续确实需要动作/台词强结构化，应单独设计“流式解析与增量渲染”计划，先证明不会破坏现有 streaming 体验。

## 7. 落地顺序

1. 先稳定 AgentCore contract：identity、capability/policy、task/result、diagnostics、executor、tool/side-effect boundary。
2. 先暴露 Memory / WorldBook 内部 read-only source tool：`MemoryRecallTool` 包装 `MemoryManager.recallMemories(...)`，`WorldBookRecallTool` 包装 `WorldBookSource.recallEntries(...)`。
3. 再以 BackgroundWorker 作为第一个 AgentCore consumer，使用 deterministic executor 验证 policy 与 diagnostics；worker 只消费 `BackgroundCandidate`，不复制 Memory / WorldBook recall logic。
4. DirectorAgent 后续复用 AgentCore，但默认只输出 `DirectorPlan`。
5. LibManAgent 后续复用 AgentCore，并显式打开 `webSearch` 与 `userVisibleDraft`。
6. reflect / relationship updater 后续复用 AgentCore，并强制 provenance / based-on ids。
