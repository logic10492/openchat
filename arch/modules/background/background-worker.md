# BackgroundWorker / 后台员工

> 状态：Level 0 deterministic worker 已实现。AgentCore foundation、Phase 4A-4D source tools/adapters、Phase 5 `BackgroundPacket` / diagnostics / worker、Phase 6 manager/prompt/chat compatible switch 均已落地；LLM-assisted selector 与 synthesis worker 尚未实现。

## 1. 定义

后台员工是一个无发言权的上下文整理器。它可以根据当前输入、候选条目和预算做选择，但不能直接对用户说话。

实现上，BackgroundWorker 应是 `AgentCore` 的受限 consumer：复用 `AgentPolicy`、capability 和 diagnostics contract，但第一阶段只启用 deterministic capability，不调用 LLM、不联网、不写数据库。

2026-05-17 AgentCore closeout：`OpenChat/Core/AgentCore/AgentPolicy.swift` 已提供 `AgentPolicy.backgroundWorkerDefault()`，`OpenChat/Core/AgentCore/DeterministicAgentExecutor.swift` 已提供 deterministic executor 的 capability / network / database write denial。AgentCore focused tests 12 tests / 4 suites passed，当时 full suite 303 tests / 58 suites passed；Background Source Tools Phase 4A-4D 后 full-suite 基线为 319 tests / 61 suites passed。当前 BackgroundWorker 复用这些 contract，不能临时扩大权限。

接入顺序：BackgroundWorker 不直接接 raw Memory / WorldBook 内部实现。2026-05-17 Phase 4A-4D 已暴露 `MemoryRecallTool` / `WorldBookRecallTool` 内部 read-only source tool，并由 `MemoryBackgroundSource` / `WorldBookBackgroundSource` 把 tool result 转成 `BackgroundCandidate`。BackgroundWorker 只处理候选和预算，不复制 Memory / WorldBook 的召回排序。

中文命名建议：

- UI/文档面向用户：`后台员工`
- 源码类型：`BackgroundWorker`
- 结果类型：`BackgroundPacket`

## 2. 权限边界

BackgroundWorker 当前可以：

- 选择候选条目。
- 排序候选条目。
- 去重或合并高度重复条目。
- 标记冲突或低置信条目。
- 根据 token budget 裁剪。
- 返回 omission diagnostics，说明为什么某些候选没进 prompt。
- 复用 AgentCore diagnostics 记录策略、输入规模、选中/省略、fallback 和耗时。
- 消费 source tool / source adapter 已经结构化的候选和 trace metadata。

BackgroundWorker 不可以：

- 生成 assistant 回复。
- 生成用户可见聊天消息。
- 改写用户输入。
- 静默修改角色卡、世界书或记忆。
- 直接拼接最终 prompt 文本。
- 调用 Exa 或其他 web search 工具。
- 临时扩大自己的 AgentCore capability。
- 绕过 source tool 直接读取/写入 Memory 或 WorldBook 数据库。
- 触发 WorldBook embedding rebuild、Memory retain 或其他持久化 side effect。

## 3. 输入输出 contract

输入：

```swift
struct BackgroundWorkerInput: Sendable {
    let request: BackgroundRequest
    let candidates: [BackgroundCandidate]
    let policy: BackgroundPolicy
    let agentPolicy: AgentPolicy
}
```

输出：

```swift
struct BackgroundPacket: Sendable {
    let entries: [BackgroundEntry]
    let omitted: [BackgroundOmission]
    let diagnostics: BackgroundDiagnostics
}

struct BackgroundEntry: Identifiable, Sendable {
    let id: String
    let sourceType: BackgroundSourceType
    let sourceId: String
    let title: String?
    let content: String
    let rank: Int
    let reason: String?
}
```

## 4. Worker 实现等级

### Level 0：Deterministic Worker

已实现。不调用 LLM。只需要 AgentCore 的 deterministic capability，根据分数规则排序：

- semantic relevance
- keyword hit
- world-book priority
- memory importance
- recency
- source policy

适合作为第一阶段实现。

当前实现证据：

- `OpenChat/Core/Background/BackgroundWorker.swift`：输入为 `BackgroundWorkerInput(request, candidates, policy, agentPolicy)`；输出 `BackgroundPacket`。
- `OpenChat/Core/Background/BackgroundPolicy.swift`：`compatibilityDefault(...)` 给出 token budget、max entries、per-source limits、source weights、duplicate penalty 和 low confidence threshold。
- `OpenChat/Core/Background/BackgroundDiagnostics.swift`：记录 source counts、selected ids、omitted reasons、fallbacks、warnings 和 policy profile。
- `OpenChatTests/Core/BackgroundTests/BackgroundWorkerTests.swift`：覆盖 deterministic order、semantic relevance 不被 memory importance 覆盖、per-source limit、budget、duplicate omission 和 policy denial。
- `OpenChatTests/Core/BackgroundTests/BackgroundDiagnosticsTests.swift`：覆盖 selected ids、source summaries、fallback 和 diagnostics 不进入 prompt content。

### Level 1：LLM-assisted Selector

调用 LLM 只做结构化选择，不写自然语言背景总结。

要求：

- 返回 JSON。
- 只能引用 candidate ids。
- 不允许生成新 facts。
- 必须带 omission reason。
- 必须显式启用 AgentCore `llm` capability。

### Level 2：Synthesis Worker

低频使用，可把多个条目合成为 observation，但不能直接进主聊天链路。产物需要 `based_on` 源 ids，并经过用户确认或后台审计策略。

Level 2 更接近 reflect / observation synthesis，不应混进每轮 BackgroundWorker 默认路径；如果落地，应作为单独 AgentCore task 审计。

## 5. 排序策略草案

```text
candidateScore =
  semanticRankScore
  + keywordHitBoost
  + sourcePriorityBoost
  + recencyBoost
  + importanceBoost
  - contradictionPenalty
  - duplicationPenalty
```

对不同 source 的解释：

- WorldBook：`priority` 是强信号，但 semantic/keyword 仍应决定是否相关。
- Memory：semantic relevance 是强信号，importance 不应覆盖当前相关性。
- CharacterState：少量稳定条目可以固定保留，但不能吞掉全部 background budget。
- ConversationState：只表达当前场景和未完成事项。

## 6. 诊断信息

`BackgroundDiagnostics` 至少应能回答：

- 本轮有哪些 source 被调用。
- 各 source 返回多少 candidates。
- 有哪些条目被选中。
- 哪些条目因预算、重复、低相关或冲突被省略。
- 是否发生 fallback。

诊断默认不展示给用户，可在 debug / 详细统计模式中查看。
