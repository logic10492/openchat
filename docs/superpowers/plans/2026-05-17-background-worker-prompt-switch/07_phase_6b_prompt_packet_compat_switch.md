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
- 保持 packet rank order 或 source-specific order，具体规则写入 tests。
- 保留现有 `PromptAssembler.makeWorldBookMessageContent(...)` / memory block 语义，避免 prompt shape 大漂移。

建议不要让 `PromptAssembler` 直接遍历 raw candidates。它只应该消费 `BackgroundPacket` 或 already assembled blocks。

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
