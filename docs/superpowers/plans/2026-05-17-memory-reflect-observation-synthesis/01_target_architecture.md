# 01. Target Architecture

## 目标形态

Phase 5 完成后，Memory 层应具备低频整理能力：

```text
selected source memories
  -> MemoryReflectRequest(task, sourceMemoryIds)
  -> MemoryReflectExecutor
  -> APIClient.sendMessage(...)
  -> structured JSON response
  -> MemoryReflectObservation draft
  -> review/apply
  -> memory_entry observation
  -> memory_embedding
  -> memory_entry_link basedOn relations
```

Reflect 输出是 draft 或用户确认后的新 memory，不是聊天回复。

## 数据边界

### Request

沿用已存在 contract：

```swift
struct MemoryReflectRequest: Sendable {
    let characterCardId: String
    let task: MemoryReflectTask
    let sourceMemoryIds: [String]
}
```

第一版 task：

- `summarize`
- `dedupe`
- `resolve_conflict`
- `relationship_observation`

### Observation

沿用已存在 contract：

```swift
struct MemoryReflectObservation: Sendable {
    let content: String
    let memoryType: MemoryType
    let basedOnMemoryIds: [String]
    let confidence: Double?
    let suggestedAction: MemoryReflectAction
}
```

规则：

- `basedOnMemoryIds` 必须是请求 source ids 的子集。
- `content` 必须是短 observation，不接受 markdown 长文或聊天台词。
- `memoryType` 第一版优先允许 `summary` / `relationship`；`event` / `fact` 仅在 parser 明确验证后接受。
- `suggestedAction == insertObservation` 才允许直接进入 apply review。
- `markDuplicate` / `needsUserReview` 默认不自动写库。

## 持久化目标

新增 companion table：

```text
memory_entry_link
  id TEXT PRIMARY KEY
  fromMemoryEntryId TEXT NOT NULL REFERENCES memory_entry(id) ON DELETE CASCADE
  toMemoryEntryId TEXT NOT NULL REFERENCES memory_entry(id) ON DELETE CASCADE
  relation TEXT NOT NULL
  createdAt DATETIME NOT NULL
```

语义：

- `fromMemoryEntryId`：新 observation / link 发起方。
- `toMemoryEntryId`：原始 source memory。
- `relation`：第一版只允许 `summarizes` / `duplicates` / `reinforces`。

写入 observation 时必须在同一 transaction 中完成：

```text
memory_entry insert
  + memory_embedding insert
  + memory_entry_link inserts
```

如果 embedding 失败或 link 写入失败，整批回滚。

## Executor 目标

建议新增独立 service，而不是把所有逻辑塞进 `MemoryManager`：

```text
MemoryReflectExecutor
  - fetch source memories
  - build prompt
  - call APIClient.sendMessage
  - parse structured output
  - validate observation
  - return MemoryReflectResult

MemoryReflectApplyService 或 MemoryManager extension
  - apply confirmed observation
  - write entry + embedding + links atomically
```

原因：

- `MemoryManager` 已经很大，当前还承担 retain / recall。
- executor 需要 API request / response parsing，和 DB apply 是不同风险面。
- tests 可以分别覆盖 parser、executor request shape、apply atomicity。

## AgentCore 边界

`AgentKind.reflect` 已存在，但当前 `DeterministicAgentExecutor` 不支持 LLM capability。Phase 5 第一版可以先不强制通过 AgentCore 执行 LLM，但必须保持 policy 语义：

- reflect 是 internal / low-frequency agent-like task。
- 允许 LLM。
- 不允许 web search。
- 不允许自动 persistent write；apply 必须走 review / confirmation。

如要新增 `AgentPolicy.reflectDefault()`，它应符合：

```text
allowedCapabilities: llm + internalDiagnostics
toolUsePolicy: disabled
sideEffectPolicy: readOnly
confirmationPolicy.requiredForPersistentWrite: true
```

## UI / Trigger 目标

第一版只要求手动入口：

```text
MemoryListView
  -> select cluster or use selected memories
  -> run reflect
  -> show observation draft
  -> user confirms
  -> apply observation
```

低频后台触发可以只落 service contract / scheduler boundary，不作为第一批必须 UI：

- App idle。
- 用户手动点整理。
- 后续 Background diagnostics 发现 duplicate / conflict cluster。

## 错误处理

使用 typed `LocalizedError`：

- empty source cluster
- missing source memory
- invalid response JSON
- observation without basedOn
- basedOn id outside request
- unsupported suggested action for auto apply
- embedding failed
- database write failed
- api key missing / endpoint missing

错误必须可测试，不用泛 `Error` 吞掉。

## 非目标

- 不实现每轮聊天自动 reflect。
- 不把 observation 自动注入当前正在生成的回复。
- 不让 reflect 修改角色卡、世界书或 conversation state。
- 不删除原始 memories。
- 不做跨角色 memory 合并。
- 不做 unified `[Background]` block。
- 不做 UI 自动化 target。
- 不接 LibMan / Exa。
