# 03. Phase 4A - Source Tool Contract

## 目标

新增内部 read-only source tool contract，让 Memory / WorldBook 可以用同一套边界暴露 recall result。

这一步不实现 BackgroundWorker，不改 prompt，不改 Chat。

## 建议类型

可放在 `OpenChat/Core/Background/`：

```swift
protocol BackgroundSourceTool: Sendable {
    associatedtype Input: Sendable
    associatedtype Output: Sendable

    var sourceType: BackgroundSourceType { get }
    func call(_ input: Input) async throws -> Output
}
```

基础 DTO 可先放最小集：

```swift
enum BackgroundSourceType: String, Sendable {
    case memory
    case worldBook
}

struct BackgroundToolDiagnostics: Sendable {
    let sourceType: BackgroundSourceType
    let inputSummary: [String: String]
    let startedAt: Date
    let durationMilliseconds: Double?
    let fallback: String?
}
```

如果当前阶段还不需要通用 diagnostics 类型，可以把 diagnostics 延后到 adapter / worker 阶段，但 tool tests 必须证明 result / trace 完整透传。

## 权限边界

tool contract 必须默认 read-only：

- 不包含写入 API。
- 不包含 network capability。
- 不包含 assistant-message output。
- 不包含 rebuild / retain / synthesis API。

不要把 AgentCore executor 强行塞进 tool contract。Phase 4 的工具是内部 source boundary，不是普通角色可调用的 function tool。

## 测试建议

如 contract 本身只有类型定义，可不单独测初始化；把行为测试放到 4B / 4C。

如果加入 diagnostics helper，则测：

- source type 正确。
- fallback string 可透传。
- duration 可为空或非负。

## 文档写回

更新：

- `arch/modules/background/architecture.md`：说明 source tool contract 已存在或计划实现位置。
- `arch/modules/background/migration-plan.md`：Phase 4A 状态。

不要把 BackgroundWorker 写成已实现。
