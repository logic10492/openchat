# BackgroundSource 统一候选来源

> 状态：目标架构规划，尚未实现。

## 1. Source 类型

```swift
enum BackgroundSourceType: String, Codable, Sendable {
    case memory
    case worldBook
    case character
    case conversationState
}
```

## 2. MemoryBackgroundSource

来源：`memory_entry` + `memory_embedding`。

职责：

- 用当前输入做 semantic retrieval。
- 保留 recent high-value fallback，并作为 fallback metadata 标记；不得恢复任意最近 N 条 prompt 注入。
- 返回 `BackgroundCandidate(sourceType: .memory)`。
- 不再直接把 memories 传给 `PromptAssembler`。

2026-05-14 Phase A 已在现有 `PromptAssembler.trim(memories:)` 关闭 Memory P1 排序问题：prompt 裁剪保持 recall 输入顺序，不再按 `importance` 重排。Background 接入后仍必须保持该契约，semantic retrieval order 是主排序信号，`importance` 只能做 tie-breaker。

## 3. WorldBookBackgroundSource

来源：`world_book_entry` + 目标 `world_book_entry_embedding`。

职责：

- 保留 keyword trigger。
- 增加 semantic KNN。
- 融合 `priority`、keyword hit 和 semantic rank。
- 返回 `BackgroundCandidate(sourceType: .worldBook)`。

WorldBook 的 `position` 字段继续作为旧数据兼容字段，不参与最终 prompt 位置决策。

## 4. CharacterBackgroundSource

来源：`CharacterCardRecord`。

职责：

- 输出少量与当前输入相关的角色卡派生背景，例如关键身份、说话风格、长期目标。
- 不替代 Stable Identity。
- 不重复注入完整角色卡。

适用场景：

- 用户提到外貌、职业、背景故事中的具体细节。
- 当前 prompt budget 不允许注入完整角色描述，但允许注入一条短背景提醒。

## 5. ConversationStateBackgroundSource

来源：当前 conversation 的派生状态。

目标状态可能包括：

- 当前场景。
- 未完成事件。
- 近期情绪余波。
- 角色与用户之间的短期互动状态。

注意：

- 这不是长期 memory。
- 这也不是 compression checkpoint。
- 它是本轮对话中需要稳定保留的短期 state。

## 6. Candidate metadata

建议统一 metadata key：

| key | 说明 |
|---|---|
| `sourceTable` | 来源表，如 `memory_entry` / `world_book_entry` |
| `sourceId` | 来源 record id |
| `semanticDistance` | sqlite-vec distance |
| `keywordHits` | 命中的关键词 |
| `priority` | source 自带 priority |
| `importance` | memory importance |
| `fallback` | 是否来自 fallback |
| `sourceUpdatedAt` | 来源更新时间 |
