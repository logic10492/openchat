# 04. Phase 5B：Reflect Executor + Structured Parser

## 目标

建立低频 reflect executor，让它读取指定 memory cluster，调用现有 OpenAI-compatible endpoint，返回 validated `MemoryReflectObservation` draft。

5B 不写数据库。它只返回 draft。

## 建议文件

计划新增：

- `OpenChat/Core/Memory/MemoryReflectExecutor.swift`
- `OpenChat/Core/Memory/MemoryReflectPromptBuilder.swift`
- `OpenChat/Core/Memory/MemoryReflectParser.swift`

必要时扩展：

- `OpenChat/Core/Memory/MemoryError.swift`
- `OpenChat/Core/AgentCore/AgentPolicy.swift`

实际实现：

- 为避免新增 Swift 文件后重新生成 Xcode project，prompt builder、parser、executor、result/diagnostics 追加到 target-backed `OpenChat/Core/Memory/MemoryReflectModels.swift`。
- `MemoryError.swift` 新增 typed reflect errors。
- `AgentPolicy.swift` 新增 `reflectDefault()`。

## 输入数据流

```text
MemoryReflectRequest
  -> fetch source memories by ids
  -> validate all source ids belong to characterCardId
  -> build prompt
  -> APIClient.sendMessage(messages:endpoint:parameters:)
  -> parse JSON
  -> MemoryReflectObservation
```

如果任一 source id 不存在或不属于目标角色，直接失败，不让 LLM 猜。

## Prompt contract

输入给 LLM 的 cluster 应只包含必要字段：

```json
{
  "characterCardId": "card-1",
  "task": "summarize",
  "sourceMemories": [
    {
      "id": "m1",
      "type": "relationship",
      "content": "..."
    }
  ]
}
```

要求输出单个 JSON object：

```json
{
  "content": "Short observation",
  "type": "summary",
  "basedOn": ["m1", "m2"],
  "confidence": 0.82,
  "suggestedAction": "insert_observation"
}
```

Parser 接受外层 markdown fence 时可剥离，但必须拒绝：

- 缺 `content`。
- 缺 `basedOn`。
- `basedOn` 为空。
- `basedOn` 包含 request source ids 之外的 id。
- `type` 不是 `MemoryType`。
- `suggestedAction` 不是 `MemoryReflectAction`。
- 返回多个 observations，除非后续明确支持 batch。

## Endpoint / Model 选择

第一版可复用当前 conversation / selected endpoint 的模型，也可由手动入口传入 endpoint config。计划实现时必须明确一个策略：

1. MemoryList 手动入口如果没有 conversation context，就需要用户设置中的默认 endpoint。
2. 如果没有默认 endpoint 或 API key，返回 typed error，不静默跳过。
3. 不在 executor 内自行创建 `APIClient`，通过 init 注入。

## Policy

如果新增 `AgentPolicy.reflectDefault()`：

- `allowedCapabilities` 包含 `.llm` 和 `.internalDiagnostics`。
- `toolUsePolicy` disabled。
- `sideEffectPolicy` read-only。
- `confirmationPolicy.requiredForPersistentWrite` true。

这只是 policy contract，不表示 executor 已经有完整 AgentCore LLM runtime。

## Diagnostics

建议结果：

```swift
struct MemoryReflectResult: Sendable {
    let observation: MemoryReflectObservation
    let diagnostics: MemoryReflectDiagnostics
}
```

Diagnostics 至少包含：

- request id。
- task。
- source ids。
- model id。
- prompt token estimate 或 input count。
- parse repair count，如果没有 repair 就为 0。
- rejected reason，如果 parser 拒绝。

Diagnostics 不进入 prompt，也不作为用户普通消息。

## Tests

新增或更新：

- `MemoryReflectModelsTests`
  - parses valid JSON。
  - strips markdown fenced JSON。
  - rejects missing basedOn。
  - rejects unknown source id in basedOn。
  - rejects invalid action / type。
  - clamps confidence through `MemoryReflectObservation`。
  - fetches only requested source memories。
  - rejects missing source memory。
  - rejects source memory from another character。
  - sends stable request shape to mock API。
  - returns validated draft without DB write。
- `AgentPolicyTests`
  - reflect policy is no-web-search and persistent-write-confirmed, if policy is added.

## 红线

- 不写 `memory_entry`。
- 不写 `memory_entry_link`。
- 不触发 embedding。
- 不接入 `ChatViewModel.generateResponse(...)`。
- 不把 LLM 返回的正文当普通 assistant message。
- 不调用 web search。

## 验收命令

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/MemoryReflectModelsTests' '-only-testing:OpenChatTests/AgentPolicyTests'
```

## 写回要求

- `arch/modules/memory/hindsight-lite.md` 更新 executor 当前事实。
- `arch/modules/memory/testing.md` 增加 parser / executor 测试边界。
- Harness 记录 mock API request shape，不记录真实 API key。
