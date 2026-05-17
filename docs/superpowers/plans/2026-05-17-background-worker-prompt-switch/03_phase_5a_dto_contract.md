# 03. Phase 5A - DTO Contract

## 目标

建立 `BackgroundWorker` 所需的最小稳定 DTO。该阶段不实现排序算法，不接 Chat / Prompt。

建议新增或扩展：

```text
OpenChat/Core/Background/BackgroundPolicy.swift
OpenChat/Core/Background/BackgroundPacket.swift
OpenChat/Core/Background/BackgroundDiagnostics.swift
```

建议 contract：

```swift
struct BackgroundPolicy: Sendable, Equatable {
    let tokenBudget: Int
    let maxEntries: Int
    let perSourceLimits: [BackgroundSourceType: Int]
    let sourceWeights: [BackgroundSourceType: Double]
    let duplicationPenalty: Double
    let lowConfidenceThreshold: Double
}

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

struct BackgroundEntry: Identifiable, Sendable, Equatable {
    let id: String
    let sourceType: BackgroundSourceType
    let sourceId: String
    let title: String?
    let content: String
    let rank: Int
    let score: Double
    let estimatedTokens: Int
    let reason: String?
    let metadata: [String: String]
}

struct BackgroundOmission: Identifiable, Sendable, Equatable {
    let id: String
    let candidateId: String
    let sourceType: BackgroundSourceType
    let reason: BackgroundOmissionReason
    let detail: String?
}
```

`BackgroundOmissionReason` 至少覆盖：

- `budgetExceeded`
- `sourceLimitExceeded`
- `duplicate`
- `lowRelevance`
- `lowConfidence`
- `contradiction`
- `policyDenied`

## 设计约束

- DTO 必须 `Sendable`。
- 测试用 DTO 尽量 `Equatable`，方便 deterministic 断言。
- `BackgroundPolicy` 不读取设置页；默认策略可以先用 static factory。
- `BackgroundWorkerInput.agentPolicy` 必须默认使用 `AgentPolicy.backgroundWorkerDefault()`。
- `BackgroundPacket` 是 worker 输出，不是 prompt 文本。
- DTO 不持有 `MemoryManager`、`WorldBookSource`、`DatabaseManager`、`APIClient`。

## 与现有 DTO 的关系

不要重复定义已存在的：

- `BackgroundSourceType`
- `BackgroundRequest`
- `BackgroundCandidate`
- `BackgroundSource`
- `BackgroundSourceTool`

如需字段扩展，应优先保持向后兼容，避免 Phase 4 tests 大面积改写。

## 完成定义

- 新 DTO 编译通过并进入 Xcode target。
- DTO tests 覆盖 default policy、omission reason、entry identity、metadata 保留。
- 无 Chat / Prompt / DI diff。
- 文档和 harness 明确：只有 DTO contract 已完成，worker 尚未接主链路。

## 测试命令

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/BackgroundPacketTests' '-only-testing:OpenChatTests/BackgroundSourceTests'
```

如新增文件未进 target：

```bash
ruby scripts/generate_xcodeproj.rb
```

然后重跑 focused tests。

## 写回要求

- Source：仅 `OpenChat/Core/Background/*` 和 `OpenChatTests/Core/BackgroundTests/*`。
- Docs：更新 `arch/modules/background/architecture.md` 与 `background-worker.md` 的 DTO 当前实现证据。
- Harness：记录 DTO 文件、default policy、未实现 worker/prompt switch、测试结果。
