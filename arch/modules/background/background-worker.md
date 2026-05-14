# BackgroundWorker / 后台员工

> 状态：目标架构规划，尚未实现。

## 1. 定义

后台员工是一个无发言权的上下文整理器。它可以根据当前输入、候选条目和预算做选择，但不能直接对用户说话。

中文命名建议：

- UI/文档面向用户：`后台员工`
- 源码类型：`BackgroundWorker`
- 结果类型：`BackgroundPacket`

## 2. 权限边界

BackgroundWorker 可以：

- 选择候选条目。
- 排序候选条目。
- 去重或合并高度重复条目。
- 标记冲突或低置信条目。
- 根据 token budget 裁剪。
- 返回 omission diagnostics，说明为什么某些候选没进 prompt。

BackgroundWorker 不可以：

- 生成 assistant 回复。
- 生成用户可见聊天消息。
- 改写用户输入。
- 静默修改角色卡、世界书或记忆。
- 直接拼接最终 prompt 文本。
- 调用 Exa 或其他 web search 工具。

## 3. 输入输出 contract

输入：

```swift
struct BackgroundWorkerInput: Sendable {
    let request: BackgroundRequest
    let candidates: [BackgroundCandidate]
    let policy: BackgroundPolicy
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

不调用 LLM。根据分数规则排序：

- semantic relevance
- keyword hit
- world-book priority
- memory importance
- recency
- source policy

适合作为第一阶段实现。

### Level 1：LLM-assisted Selector

调用 LLM 只做结构化选择，不写自然语言背景总结。

要求：

- 返回 JSON。
- 只能引用 candidate ids。
- 不允许生成新 facts。
- 必须带 omission reason。

### Level 2：Synthesis Worker

低频使用，可把多个条目合成为 observation，但不能直接进主聊天链路。产物需要 `based_on` 源 ids，并经过用户确认或后台审计策略。

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
