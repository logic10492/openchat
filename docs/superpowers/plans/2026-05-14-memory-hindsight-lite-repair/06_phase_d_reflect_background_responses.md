# 06. Phase D：Reflect、Background 适配边界与 Responses API

> 状态：2026-05-16 已完成最小 reflect contract 与当前 `[Memories]` request-shape 验收。未实现 reflect LLM executor、UI 入口、`memory_entry_link` migration 或 Background 层。

## 目标

在不扩大主聊天链路延迟的前提下，为低频 reflect 建立 Memory 层 contract，并验收当前 `[Memories]` 在 Responses API 下的请求形态。Background 只记录后续适配边界，不在本计划包实现。

## D1：Reflect observation contract

本阶段只做最小 contract，不强制接 UI：

```swift
struct MemoryReflectRequest: Sendable {
    let characterCardId: String
    let task: MemoryReflectTask
    let sourceMemoryIds: [String]
}

struct MemoryReflectObservation: Sendable {
    let content: String
    let memoryType: MemoryType
    let basedOnMemoryIds: [String]
    let confidence: Double?
    let suggestedAction: MemoryReflectAction
}
```

规则：

- `basedOnMemoryIds` 不能为空。
- reflect 不在每轮 `generateResponse(...)` 中调用。
- reflect 不生成 assistant reply。
- reflect 不静默删除或覆盖原始 memory。

若需要持久化 basedOn，可追加 `memory_entry_link`：

```text
memory_entry_link
  id TEXT PRIMARY KEY
  fromMemoryEntryId TEXT REFERENCES memory_entry(id) ON DELETE CASCADE
  toMemoryEntryId TEXT REFERENCES memory_entry(id) ON DELETE CASCADE
  relation TEXT
  createdAt DATETIME
```

`relation` 第一版至少支持 `summarizes`、`duplicates`、`reinforces`。

实现证据：

- `OpenChat/Core/Memory/MemoryReflectModels.swift`
- `OpenChatTests/Core/MemoryTests/MemoryReflectModelsTests.swift`

当前 enum raw values：

- `MemoryReflectTask`：`summarize`、`dedupe`、`resolve_conflict`、`relationship_observation`
- `MemoryReflectAction`：`insert_observation`、`mark_duplicate`、`needs_user_review`
- `MemoryEntryLinkRelation`：`summarizes`、`duplicates`、`reinforces`

## D2：Background 边界

本计划包不实现完整 `BackgroundWorker`，也不实现世界书向量化。这里的目标只是避免 Memory 继续把 prompt 注入权越做越深，并为后续独立 Background 计划包留下清晰 adapter 边界。

建议：

- `MemoryRecallResult` 保持和 prompt 无关。
- 仅在文档或测试 helper 中保留 adapter sketch；不要新增生产侧 `Core/Background` 依赖：

```swift
struct MemoryBackgroundCandidate: Sendable {
    let memoryId: String
    let content: String
    let type: String
    let rank: Int
    let traceReasons: [String]
}
```

- 暂不让 `PromptAssembler` 消费这个类型，等独立 Background 模块落地。

## D3：Responses API request shape

当前 `ResponsesAPIRequest` 会把 system messages 合并到 `instructions`：

```text
stable identity system
+ example/worldbook/memory system
=> instructions
```

这不一定是 bug，但必须被测试和文档承认。

测试目标：

- Chat Completions 模式下 `[Memories]` 仍在 messages 中，位于 current turn user 前。
- Responses 模式下当前 `[Memories]` 存在于 `instructions`，非 system `input` 不重复 current input。
- 当前 `[Memories]` block 不被拼进 user message。
- system folding 的顺序保持 `Stable Identity -> Current-Turn Context`。

Background block 的 request-shape 验收不在本计划包内，留给后续独立 Background 计划包。

修改位置：

- `OpenChatTests/Core/NetworkingTests/ResponsesAPITests.swift`
- `OpenChatTests/Features/ChatTests/ChatViewModelPromptAssemblyTests.swift`

只有测试证明当前 shape 不满足目标时，才修改 `ResponsesAPIRequest.swift`。

当前测试证明 source behavior 满足 D3 目标，因此未修改 `ResponsesAPIRequest.swift`。

## D4：可观测性 UI / Debug

普通 UI 先不暴露 distance 数值。可选 debug 展示：

- 本轮 selected memory count。
- fallback reason。
- “相关记忆 / 关键词命中 / 近期高价值补充”这样的原因标签。
- budget omitted count。

若加 UI 文案，必须写入 `OpenChat/Resources/Localizable.xcstrings`。

## 验收

旧计划草稿曾写过：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/ResponsesAPITests' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests'
```

注意：Swift Testing 的 `-only-testing` 选择器需要使用 suite 名称；`ResponsesAPITests` 是文件名，不会选中该文件内的 Swift Testing suites。Phase D 实际验收使用以下 suite-name 命令：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'id=6F61E759-8E3C-4951-B929-0A63AA47BFBB' '-only-testing:OpenChatTests/ResponsesAPIRequestTests' '-only-testing:OpenChatTests/ResponsesAPIResponseTests' '-only-testing:OpenChatTests/SSEParserTypedEventsTests' '-only-testing:OpenChatTests/APIClientResponsesModeTests' '-only-testing:OpenChatTests/ModelParametersAPIModeTests'
```

结果：21 tests / 5 suites passed，`** TEST SUCCEEDED **`。

Chat + reflect focused 验证：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'id=F8D0D88B-71FD-471F-855A-B2B5D8267117' '-only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests' '-only-testing:OpenChatTests/MemoryReflectModelsTests'
```

结果：17 tests / 2 suites passed，`** TEST SUCCEEDED **`。旧命令中曾包含 `ResponsesAPITests` 文件名选择器，但 Swift Testing 不会用文件名选中 Responses suites；Responses suites 已由上方 suite-name 命令单独验证。

完成后更新：

- `arch/modules/api-client.md`
- `arch/modules/memory/hindsight-lite.md`
- `arch/modules/memory/ui-management.md`
- `arch/AntiEntropy/problem.md`
