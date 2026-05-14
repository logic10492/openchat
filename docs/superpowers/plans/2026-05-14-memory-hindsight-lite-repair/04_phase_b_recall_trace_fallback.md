# 04. Phase B：Recall Trace 与 Fallback Tier

## 目标

把 recall 从 `[MemoryEntryRecord]` 单一结果升级为可解释的内部结果，同时替换“semantic 失败就 recent by time”的粗 fallback。

## B1：新增 Recall DTO

建议新增：

- `OpenChat/Core/Memory/MemoryRecallModels.swift`

包含：

- `MemoryRecallResult`
- `MemoryRecallEntry`
- `MemoryRecallTrace`
- `MemoryRecallReason`
- `MemoryRecallFallback`
- `MemoryRecallOmission`

初始字段按 `01_target_architecture.md`，保持 `Sendable`。

## B2：MemoryManager API 分层

在 `MemoryManager` 中新增：

```swift
func recallMemories(
    for characterCardId: String,
    query: String,
    limit: Int = 5
) async throws -> MemoryRecallResult
```

保留兼容 API：

```swift
func retrieveMemories(...) async throws -> [MemoryEntryRecord] {
    try await recallMemories(...).entries.map(\.memory)
}
```

## B3：候选源

### semantic

沿用 `embeddingService.embed(query, isQuery: true)` 和 `vectorStore.search(...)`。

- search limit 建议从外部 limit 扩大到 `max(limit * 2, 20)`，再融合裁剪。
- trace 记录 semantic candidate count 和每个入选条目的 distance。

### keyword

第一版可使用 DB 读出角色 memory 后做本地轻量匹配，不立即上 FTS5：

- query 规范化为 lowercased words。
- memory content 包含任一较长 keyword 视为 candidate。
- 排名按命中数、首次命中位置、importance tie-breaker。

可后续迁移到 FTS5，但本阶段不强制。

### recent high-value

新增 DB 查询或在已有 fetch 后筛选：

- `memoryType in relationship, summary` 优先。
- 或 `importance >= 70`。
- limit <= 3。
- 排序：type priority -> importance DESC -> createdAt DESC。

不要继续把任意最近 N 条作为默认 prompt 补充。

## B4：Fallback tier

| fallback | 触发 | 返回策略 |
|---|---|---|
| `semanticUnavailable` | embedding / vector throw | keyword + recent high-value |
| `noSemanticHit` | semantic 全部超过 threshold | keyword；没有 keyword 时 recent high-value |
| `emptyIndex` | 角色没有 memory 或 semantic/keyword/recent 都空 | 空 |
| `none` | semantic 有命中 | semantic 为主，keyword / recent high-value 只补充 |

## B5：Rank fusion

第一版使用简单稳定规则即可：

1. semantic hit 按 distance 升序为主。
2. keyword hit 可插入 semantic 后，或用 reciprocal rank fusion。
3. recent high-value 只在未出现时补充，且数量小。
4. importance 只做 tie-breaker。

需要 trace 每个 selected id 的 reasons。

## 测试

在 `MemoryManagerRetrievalTests` 中新增：

- semantic 返回 `[A(distance 0.2), B(0.4)]`，keyword 命中 C，最终 A/B 顺序不被 importance 覆盖。
- embedding failure 时不返回普通 recent 噪声，只返回 keyword / high-value recent。
- semantic no hit 时有 keyword -> keyword 优先。
- semantic no hit 且无 keyword -> 只返回 relationship / summary / high importance。
- empty character memories -> entries 为空，fallback 为 `emptyIndex`。
- trace 记录 selected ids、fallback reason、candidate counts。

可在 `DatabaseManagerMemoryTests` 中补：

- high-value recent 查询只返回 relationship / summary / high importance。

## 验收

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MemoryManagerRetrievalTests' '-only-testing:OpenChatTests/DatabaseManagerMemoryTests'
```

完成后更新：

- `arch/modules/memory/retrieval-prompt.md`
- `arch/modules/memory/testing.md`
- `arch/AntiEntropy/problem.md`
- `arch/AntiEntropy/triangle-consistency.md`
