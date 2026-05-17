# 07. Phase 6B - Prompt Packet Compatible Switch

## 目标

让 Prompt 层可以消费 `BackgroundPacket`，但第一阶段保持文本输出兼容：

```text
[World Book Entries]
...
[/World Book Entries]

[Memories]
...
[/Memories]
```

不要把统一 `[Background]` 作为默认输出。

建议文件：

```text
OpenChat/Core/Background/BackgroundAssembler.swift
OpenChat/Core/PromptEngine/PromptAssembler.swift
OpenChatTests/Core/PromptEngineTests/PromptAssemblerTests.swift
```

## BackgroundAssembler 责任

`BackgroundAssembler` 把 packet entry 分组成 prompt block DTO 或 `ChatMessage`：

- `.worldBook` entries -> `[World Book Entries]`
- `.memory` entries -> `[Memories]`
- 兼容输出默认按 source 分组：worldBook block 先于 memory block；每个 source 内按 `BackgroundEntry.rank`，再按 `id` 稳定排序。
- 保留现有 `PromptAssembler.makeWorldBookMessageContent(...)` / memory block 语义，避免 prompt shape 大漂移。

建议不要让 `PromptAssembler` 直接遍历 raw candidates。它只应该消费 `BackgroundPacket` 或 already assembled blocks。

## 本修订的兼容格式 contract

Phase 6B 第一版不把 `BackgroundEntry` 伪装成 `WorldBookEntryRecord` / `MemoryEntryRecord`，而是用 entry 字段生成兼容文本：

```text
worldBook:
  [World Book: <title-or-sourceId>]
  <content>

memory:
  [Memory — <title-or-metadata.memoryType-or-sourceId>]
  <content>
```

Block wrapper 保持不变：

```text
[World Book Entries]
...
[/World Book Entries]

[Memories]
...
[/Memories]
```

`BackgroundPacket.diagnostics`、omission reason、score、metadata 不进入 prompt content，除非后续有单独 debug UI 计划。

## PromptAssembler 改动策略

第一步新增 packet-aware overload，而不是直接删除旧入口：

```swift
static func preview(
    conversation: ConversationRecord,
    characterCard: CharacterCardRecord?,
    backgroundPacket: BackgroundPacket,
    currentInput: String,
    endpoint: APIEndpointConfig
) -> PromptAssemblyPreview
```

```swift
static func assemble(
    conversation: ConversationRecord,
    characterCard: CharacterCardRecord?,
    backgroundPacket: BackgroundPacket,
    processedHistory: [MessageRecord],
    currentInput: String,
    endpoint: APIEndpointConfig
) -> AssemblyResult
```

旧 direct memories/worldBook entries overload 可暂时保留，用于 regression 对比和回滚。

Packet-aware overload 必须复用当前 preview/assemble 的预算结构：

- stable identity、scenario、slow plot、example dialogs、time context、current turn message 的顺序不变。
- `BackgroundPacket.entries` 先由 `BackgroundAssembler` 分组为 worldBook / memory prompt items。
- PromptAssembler 仍按现有 `TokenBudget.calculate(...)` 计算 example / worldBook / memory / history budget。
- 最终 request body 只包含预算内的 prompt items；如果 packet entry 被 PromptAssembler 因预算裁掉，必须有测试覆盖。
- `TokenUsageReport.worldBookEntries` / `memories` 统计最终 block tokens，而不是 packet 原始总量。
- `AssemblyResult.triggeredEntries` 至少继续记录最终进入 prompt 的 worldBook source ids；如需要新增 background included ids，必须不破坏旧字段语义。

## 必须保持的行为

- Stable identity、scenario、slow plot、example dialogs 顺序不漂移。
- processed history 仍位于 stable identity 之后、current-turn context 之前。
- current input 只出现一次；保留 existing duplicate-input guard。
- `[Time]` 仍附在 current turn content，除非有单独 prompt plan。
- semantic-only world book entries 不被 keyword 二次过滤。
- token usage 中 worldBookEntries / memories 计数仍合理；如果新增 background 字段，不能破坏现有统计。

## 后续可选 `[Background]`

统一 block 的迁移必须另起小阶段或至少由用户确认。进入统一 block 前需要：

- request-shape snapshot tests。
- PromptAssemblerTests 比较旧兼容输出和新输出。
- ChatViewModelPromptAssemblyTests 验证实际 API request body。
- arch 文档说明 prompt format 变更。

## 完成定义

- Packet-aware PromptAssembler overload 存在并有 tests。
- 兼容 block 输出文本与旧格式一致或差异有明确测试说明。
- Packet entry 因 prompt budget 被裁掉时，request body、token usage 和 included ids 有明确断言。
- 旧 prompt tests 仍通过。
- Chat 尚未切换或只在 6C 切换。

## 测试命令

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/PromptAssemblerTests'
```

Prompt + worker：

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' '-only-testing:OpenChatTests/BackgroundWorkerTests' '-only-testing:OpenChatTests/BackgroundDiagnosticsTests' '-only-testing:OpenChatTests/PromptAssemblerTests'
```

## 写回要求

- Source：`BackgroundAssembler.swift`、`PromptAssembler.swift`、PromptAssembler focused tests。
- Docs：更新 `arch/modules/prompt-assembly.md` 和 `arch/modules/background/architecture.md`，明确兼容 block 来源已计划或已切到 packet。
- Harness：记录 request / prompt block shape，明确 `[Background]` 仍未默认启用。
