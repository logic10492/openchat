# Prompt Four-Layer Assembly Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 PromptAssembler 的实际输出改为 `Stable Identity -> Stable Conversation State -> Current-Turn Context -> Current Turn` 四层顺序，并让测试和架构文档同步反映该顺序。

**Architecture:** 保持现有 `ChatViewModel -> PromptAssembler.preview -> ContextManager.prepareHistory -> PromptAssembler.assemble -> APIClient` 三段链路，但把 `PromptAssemblyPreview` 从单一 `messagesBeforeHistory` 拆成四层可组合结构。`ContextManager` 继续只负责压缩/裁剪历史；`PromptAssembler` 负责把压缩摘要、checkpoint 后历史、当前轮检索上下文和当前输入按目标顺序拼回最终 `[ChatMessage]`。

**Tech Stack:** Swift 6, Swift Testing, GRDB.swift records, Swift Concurrency, Xcode project via `OpenChat.xcodeproj`。

---

## Scope Decisions

1. 本计划只实现 prompt 拼装顺序，不改变 compression checkpoint schema、不新增 migration、不改签名配置。
2. 保持 `PromptAssembler.preview(...)` / `assemble(...)` 的入参形态，降低 `ChatViewModel+Support` 调用链改动面。
3. `PromptAssemblyPreview` 改为四层输出结构：`stableIdentityMessages`、`currentTurnContextMessages`、`currentTurnMessage`，同时保留 `fixedTokens`、`historyBudget`、`tokenUsage`、`triggeredEntries`。
4. `processedHistory` 仍由 `ContextManager.prepareHistory(...)` 返回；compression 时其第一条可为 `[Previously]` system message，后续为 checkpoint 后历史。
5. 当前轮上下文统一位于 Stable Conversation State 之后，顺序固定为 `example dialogs block -> world book entries block -> memories block`。
6. `WorldBookEntryPosition.after_system` / `.before_history` 不再决定最终 prompt 位置；实现期只作为旧数据兼容字段保留，触发时统一按 `KeywordMatcher.triggeredEntries(..., position: nil)` 取当前轮命中条目。
7. time context 合并进最后一条 current turn user message，内容顺序为用户输入在前、`[Time] <ISO8601> [/Time]` 在后。

## File Structure

- Modify: `OpenChat/Core/PromptEngine/PromptAssemblyModels.swift`
  - 拆分 `PromptAssemblyPreview` 输出结构，移除 `messagesBeforeHistory`。
- Modify: `OpenChat/Core/PromptEngine/PromptAssembler.swift`
  - 重排 `preview(...)` 和 `assemble(...)`。
  - 新增 labeled system block helper：example dialogs、world book entries、memories。
  - 调整 token usage，使 `totalUsed` 按真实最终 messages 计数。
- Modify: `OpenChat/Core/PromptEngine/PromptSegment.swift`
  - 将 segment 类型改为文档中的 `exampleDialogsBlock` / `currentTurn` 语义。
- No change expected: `OpenChat/Core/ContextManager/*`
  - 现有 `PreparedHistory.messagesForLegacyPrompt(...)` 已能返回 `[Previously] + checkpoint 后历史`，只需要由 `PromptAssembler.assemble(...)` 放到新位置。
- No change expected: `OpenChat/Features/Chat/ViewModels/ChatViewModel+Support.swift`
  - 继续用 `preview.fixedTokens` 调 ContextManager，再把 `processedHistory` 传给 `assemble(...)`。
- Modify: `OpenChatTests/Core/PromptEngineTests/PromptAssemblerTests.swift`
  - 更新旧顺序测试，新增四层顺序、labeled blocks、time-in-current-turn 覆盖。
- Modify: `OpenChatTests/Features/ChatTests/ChatViewModelPromptAssemblyTests.swift`
  - 增加真实发送链路 API request 顺序断言，防止当前输入重复和当前轮上下文位置回退。
- Modify docs:
  - `arch/modules/prompt-assembly.md`
  - `.github/instructions/prompt-engine.instructions.md`
  - `arch/AntiEntropy/triangle-consistency.md`
  - `arch/AntiEntropy/propagation-audit.md`
  - `arch/roadmap.md`

## Baseline Commands

Focused prompt tests:

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:OpenChatTests/PromptAssemblerTests
```

Focused chat prompt tests:

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests
```

Combined verification:

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:OpenChatTests/PromptAssemblerTests -only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests
```

Full suite:

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

---

### Task 1: Lock the Target Order with Failing PromptAssembler Tests

**Files:**
- Modify: `OpenChatTests/Core/PromptEngineTests/PromptAssemblerTests.swift`

- [ ] **Step 1: Replace the old segment-order test with a four-layer order test**

Replace `test_preview_orders_segments_correctly` with:

```swift
@Test func test_assemble_orders_four_layers() throws {
    let conversation = TestHelpers.makeConversation(slowPlotMode: true)
    let card = TestHelpers.makeCharacterCard()
    let book = TestHelpers.makeWorldBook(isEnabled: true)
    let highPriorityEntry = TestHelpers.makeWorldBookEntry(
        worldBookId: book.id,
        title: "High",
        keywords: ["dragon"],
        priority: 90,
        position: .beforeHistory,
        content: "High priority dragon note."
    )
    let lowPriorityEntry = TestHelpers.makeWorldBookEntry(
        worldBookId: book.id,
        title: "Low",
        keywords: ["dragon"],
        priority: 10,
        position: .afterSystem,
        content: "Low priority dragon note."
    )
    let memory = TestHelpers.makeMemoryEntry(
        characterCardId: card.id,
        content: "Hero remembers the dragon map.",
        memoryType: .event
    )
    let processedHistory = [
        TestHelpers.makeMessage(
            conversationId: conversation.id,
            role: "system",
            content: "[Previously]\nThe party entered the old city.",
            sortOrder: 1
        ),
        TestHelpers.makeMessage(
            conversationId: conversation.id,
            role: "assistant",
            content: "Previous assistant reply.",
            sortOrder: 2
        ),
    ]

    let result = PromptAssembler.assemble(
        conversation: conversation,
        characterCard: card,
        worldBook: book,
        worldBookEntries: [lowPriorityEntry, highPriorityEntry],
        memories: [memory],
        recentMessages: [
            TestHelpers.makeMessage(
                conversationId: conversation.id,
                role: "assistant",
                content: "A dragon is nearby.",
                sortOrder: 2
            )
        ],
        processedHistory: processedHistory,
        currentInput: "What do I see near the dragon?",
        endpoint: TestHelpers.makeEndpoint(maxContextTokens: 4000)
    )

    let messages = result.messages
    let baseSystemIndex = try #require(messages.firstIndex { $0.content.contains("You are") })
    let characterIndex = try #require(messages.firstIndex { $0.content.contains("Character:") })
    let scenarioIndex = try #require(messages.firstIndex { $0.content.localizedCaseInsensitiveContains("tavern") })
    let slowPlotIndex = try #require(messages.firstIndex { $0.content.contains("场景维持者") })
    let compressedIndex = try #require(messages.firstIndex { $0.content.contains("[Previously]") })
    let historyIndex = try #require(messages.firstIndex { $0.content == "Previous assistant reply." })
    let exampleIndex = try #require(messages.firstIndex { $0.content.contains("[Example Dialogs]") })
    let worldBookIndex = try #require(messages.firstIndex { $0.content.contains("[World Book Entries]") })
    let memoryIndex = try #require(messages.firstIndex { $0.content.contains("[Memories]") })
    let currentTurnIndex = try #require(messages.firstIndex { $0.content.contains("What do I see near the dragon?") })

    #expect(baseSystemIndex < characterIndex)
    #expect(characterIndex < scenarioIndex)
    #expect(scenarioIndex < slowPlotIndex)
    #expect(slowPlotIndex < compressedIndex)
    #expect(compressedIndex < historyIndex)
    #expect(historyIndex < exampleIndex)
    #expect(exampleIndex < worldBookIndex)
    #expect(worldBookIndex < memoryIndex)
    #expect(memoryIndex < currentTurnIndex)
    #expect(currentTurnIndex == messages.indices.last)
    #expect(messages[currentTurnIndex].role == "user")
    #expect(messages[currentTurnIndex].content.contains("[Time] "))
}
```

- [ ] **Step 2: Add a preview structure test**

Add:

```swift
@Test func test_preview_exposes_four_layer_parts() throws {
    let conversation = TestHelpers.makeConversation()
    let card = TestHelpers.makeCharacterCard()

    let preview = PromptAssembler.preview(
        conversation: conversation,
        characterCard: card,
        worldBook: nil,
        worldBookEntries: [],
        recentMessages: [],
        currentInput: "hello",
        endpoint: TestHelpers.makeEndpoint(maxContextTokens: 1000)
    )

    #expect(preview.stableIdentityMessages.first?.role == "system")
    #expect(preview.stableIdentityMessages.first?.content.contains("You are") == true)
    #expect(preview.currentTurnContextMessages.contains { $0.content.contains("[Example Dialogs]") })
    #expect(preview.currentTurnMessage.role == "user")
    #expect(preview.currentTurnMessage.content.contains("hello"))
    #expect(preview.currentTurnMessage.content.contains("[Time] "))
}
```

- [ ] **Step 3: Run tests and confirm they fail for the expected reason**

Run:

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:OpenChatTests/PromptAssemblerTests/test_assemble_orders_four_layers -only-testing:OpenChatTests/PromptAssemblerTests/test_preview_exposes_four_layer_parts
```

Expected: FAIL because `PromptAssemblyPreview` has no `stableIdentityMessages`, `currentTurnContextMessages`, or `currentTurnMessage`, and because final assembly still uses `messagesBeforeHistory + processedHistory + currentInput`.

---

### Task 2: Design and Implement the Four-Layer Output Structure

**Files:**
- Modify: `OpenChat/Core/PromptEngine/PromptAssemblyModels.swift`
- Modify: `OpenChat/Core/PromptEngine/PromptAssembler.swift`

- [ ] **Step 1: Change PromptAssemblyPreview**

In `OpenChat/Core/PromptEngine/PromptAssemblyModels.swift`, replace:

```swift
let messagesBeforeHistory: [ChatMessage]
```

with:

```swift
let stableIdentityMessages: [ChatMessage]
let currentTurnContextMessages: [ChatMessage]
let currentTurnMessage: ChatMessage
```

Keep:

```swift
let fixedTokens: Int
let historyBudget: Int
let tokenUsage: TokenUsageReport
let triggeredEntries: [String]
```

- [ ] **Step 2: Split preview output into stable identity, current-turn context, and current turn**

In `OpenChat/Core/PromptEngine/PromptAssembler.swift`, change `preview(...)` so it builds:

```swift
let stableIdentityMessages = [
    systemMessage,
    characterMessage,
    scenarioMessage,
    slowPlotMessage,
].compactMap { $0 }

let currentTurnContextMessages = [
    exampleDialogsBlock,
    worldBookBlock,
    memoryBlock,
].compactMap { $0 }

let currentTurnMessage = ChatMessage(
    role: "user",
    content: makeCurrentTurnContent(currentInput: currentInput, timeContext: timeContext)
)
```

`fixedTokens` must become the tokens that ContextManager cannot trim:

```swift
let actualFixedTokens =
    stableIdentityMessages.reduce(0) { $0 + TokenCounter.count(message: $1) }
    + currentTurnContextMessages.reduce(0) { $0 + TokenCounter.count(message: $1) }
    + TokenCounter.count(message: currentTurnMessage)
```

- [ ] **Step 3: Recompose final messages in assemble(...)**

Replace:

```swift
var messages = context.messagesBeforeHistory
messages.append(contentsOf: processedHistory.map(\.chatMessage))
messages.append(ChatMessage(role: "user", content: currentInput))
```

with:

```swift
var messages = context.stableIdentityMessages
messages.append(contentsOf: processedHistory.map(\.chatMessage))
messages.append(contentsOf: context.currentTurnContextMessages)
messages.append(context.currentTurnMessage)
```

Expected final order:

```text
Stable Identity
Stable Conversation State from processedHistory
Current-Turn Context
Current Turn
```

- [ ] **Step 4: Run focused tests**

Run:

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:OpenChatTests/PromptAssemblerTests/test_preview_exposes_four_layer_parts
```

Expected: PASS after this task; `test_assemble_orders_four_layers` may still fail until blocks and world book ordering are implemented.

---

### Task 3: Adjust Prompt Assembly Order to Match the Document

**Files:**
- Modify: `OpenChat/Core/PromptEngine/PromptAssembler.swift`
- Modify: `OpenChat/Core/PromptEngine/PromptSegment.swift`
- Modify: `OpenChatTests/Core/PromptEngineTests/PromptAssemblerTests.swift`

- [ ] **Step 1: Stop using world book position for final prompt placement**

Replace the two-position trigger flow:

```swift
let afterSystemEntries = makeTriggeredEntries(..., position: .afterSystem)
let beforeHistoryEntries = makeTriggeredEntries(..., position: .beforeHistory)
let trimmedWorldBookEntries = trim(entries: afterSystemEntries + beforeHistoryEntries, within: tokenBudget.worldBookBudget)
```

with a single trigger flow:

```swift
let triggeredWorldBookEntries = makeTriggeredEntries(
    worldBook: worldBook,
    entries: worldBookEntries,
    contextText: contextText
)
let trimmedWorldBookEntries = trim(entries: triggeredWorldBookEntries, within: tokenBudget.worldBookBudget)
```

Add an overload or change the helper to accept no position:

```swift
private static func makeTriggeredEntries(
    worldBook: WorldBookRecord?,
    entries: [WorldBookEntryRecord],
    contextText: String
) -> [WorldBookEntryRecord] {
    guard worldBook?.isEnabled ?? false else { return [] }
    return KeywordMatcher.triggeredEntries(entries, contextText: contextText)
}
```

- [ ] **Step 2: Update PromptSegment to reflect the target semantic model**

Replace cases:

```swift
case timeContext(String)
case exampleDialog(ChatMessage)
case currentInput(String)
```

with:

```swift
case exampleDialogsBlock(String)
case currentTurn(String)
```

Update `role`, `content`, `priority`, and `isRequired`:

```swift
case .currentTurn:
    "user"

case .exampleDialogsBlock:
    "system"
```

`isRequired` should return true for `.systemPrompt` and `.currentTurn`; time context is now part of `.currentTurn`, not a separate required segment.

- [ ] **Step 3: Add world book position compatibility test**

Add to `PromptAssemblerTests.swift`:

```swift
@Test func test_world_book_positions_do_not_split_final_context_block() throws {
    let conversation = TestHelpers.makeConversation(slowPlotMode: false)
    let card = TestHelpers.makeCharacterCard()
    let book = TestHelpers.makeWorldBook(isEnabled: true)
    let afterEntry = TestHelpers.makeWorldBookEntry(
        worldBookId: book.id,
        title: "After",
        keywords: ["dragon"],
        priority: 10,
        position: .afterSystem,
        content: "After system note."
    )
    let beforeEntry = TestHelpers.makeWorldBookEntry(
        worldBookId: book.id,
        title: "Before",
        keywords: ["dragon"],
        priority: 90,
        position: .beforeHistory,
        content: "Before history note."
    )

    let result = PromptAssembler.assemble(
        conversation: conversation,
        characterCard: card,
        worldBook: book,
        worldBookEntries: [afterEntry, beforeEntry],
        recentMessages: [],
        processedHistory: [],
        currentInput: "dragon",
        endpoint: TestHelpers.makeEndpoint(maxContextTokens: 4000)
    )

    let worldBookMessage = try #require(result.messages.first { $0.content.contains("[World Book Entries]") })
    #expect(worldBookMessage.role == "system")
    #expect(worldBookMessage.content.contains("Before history note."))
    #expect(worldBookMessage.content.contains("After system note."))
    #expect(worldBookMessage.content.range(of: "Before history note.")!.lowerBound < worldBookMessage.content.range(of: "After system note.")!.lowerBound)
}
```

- [ ] **Step 4: Run focused tests**

Run:

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:OpenChatTests/PromptAssemblerTests/test_world_book_positions_do_not_split_final_context_block -only-testing:OpenChatTests/PromptAssemblerTests/test_assemble_orders_four_layers
```

Expected: PASS.

---

### Task 4: Implement Labeled System Block Design

**Files:**
- Modify: `OpenChat/Core/PromptEngine/PromptAssembler.swift`
- Modify: `OpenChatTests/Core/PromptEngineTests/PromptAssemblerTests.swift`

- [ ] **Step 1: Add block format helpers**

Add these helpers to `PromptAssembler.swift`:

```swift
private static func makeExampleDialogsBlock(_ messages: [ChatMessage]) -> ChatMessage? {
    guard !messages.isEmpty else { return nil }
    let body = messages.map { message in
        let label = message.role == "assistant" ? "Assistant" : "User"
        return "\(label): \(message.content)"
    }.joined(separator: "\n")
    return ChatMessage(role: "system", content: "[Example Dialogs]\n\(body)\n[/Example Dialogs]")
}

private static func makeWorldBookBlock(_ entries: [WorldBookEntryRecord]) -> ChatMessage? {
    guard !entries.isEmpty else { return nil }
    let body = entries.map { makeWorldBookMessageContent($0) }.joined(separator: "\n\n")
    return ChatMessage(role: "system", content: "[World Book Entries]\n\(body)\n[/World Book Entries]")
}

private static func makeMemoryBlock(_ memories: [MemoryEntryRecord]) -> ChatMessage? {
    guard !memories.isEmpty else { return nil }
    let body = memories.map { makeMemoryMessageContent($0) }.joined(separator: "\n\n")
    return ChatMessage(role: "system", content: "[Memories]\n\(body)\n[/Memories]")
}

private static func makeCurrentTurnContent(currentInput: String, timeContext: String) -> String {
    let trimmedInput = currentInput.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedInput.isEmpty else { return timeContext }
    return "\(trimmedInput)\n\n\(timeContext)"
}
```

- [ ] **Step 2: Trim items before wrapping blocks**

Keep item-level trimming before block construction:

```swift
let trimmedExampleDialogs = trim(messages: exampleDialogs, within: tokenBudget.exampleDialogsBudget)
let trimmedWorldBookEntries = trim(entries: triggeredWorldBookEntries, within: tokenBudget.worldBookBudget)
let trimmedMemories = trim(memories: memories, within: tokenBudget.memoryBudget)

let exampleDialogsBlock = makeExampleDialogsBlock(trimmedExampleDialogs)
let worldBookBlock = makeWorldBookBlock(trimmedWorldBookEntries)
let memoryBlock = makeMemoryBlock(trimmedMemories)
```

This preserves the current "first item may exceed budget" behavior while changing the wire shape to labeled system blocks.

- [ ] **Step 3: Add labeled block tests**

Add:

```swift
@Test func test_example_dialogs_are_labeled_system_block() throws {
    let conversation = TestHelpers.makeConversation(slowPlotMode: false)
    let card = TestHelpers.makeCharacterCard()

    let result = PromptAssembler.assemble(
        conversation: conversation,
        characterCard: card,
        worldBook: nil,
        worldBookEntries: [],
        recentMessages: [],
        processedHistory: [],
        currentInput: "hello",
        endpoint: TestHelpers.makeEndpoint(maxContextTokens: 2000)
    )

    let exampleBlock = try #require(result.messages.first { $0.content.contains("[Example Dialogs]") })
    #expect(exampleBlock.role == "system")
    #expect(exampleBlock.content.contains("User: Hello"))
    #expect(exampleBlock.content.contains("Assistant: Hi there!"))
    #expect(!result.messages.contains { $0.role == "user" && $0.content == "Hello" })
    #expect(!result.messages.contains { $0.role == "assistant" && $0.content == "Hi there!" })
}

@Test func test_time_context_is_inside_current_turn_message() throws {
    let conversation = TestHelpers.makeConversation(slowPlotMode: false)

    let result = PromptAssembler.assemble(
        conversation: conversation,
        characterCard: nil,
        worldBook: nil,
        worldBookEntries: [],
        recentMessages: [],
        processedHistory: [],
        currentInput: "hello",
        endpoint: TestHelpers.makeEndpoint(maxContextTokens: 1000)
    )

    let last = try #require(result.messages.last)
    #expect(last.role == "user")
    #expect(last.content.hasPrefix("hello"))
    #expect(last.content.contains("[Time] "))
    #expect(result.messages.filter { $0.content.hasPrefix("[Time] ") }.isEmpty)
}
```

- [ ] **Step 4: Run focused tests**

Run:

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:OpenChatTests/PromptAssemblerTests/test_example_dialogs_are_labeled_system_block -only-testing:OpenChatTests/PromptAssemblerTests/test_time_context_is_inside_current_turn_message
```

Expected: PASS.

---

### Task 5: Update the Real Chat Request Regression Tests

**Files:**
- Modify: `OpenChatTests/Features/ChatTests/ChatViewModelPromptAssemblyTests.swift`

- [ ] **Step 1: Keep current input de-duplication test, but adjust time expectations**

Find any assertion that expects `[Time]` as a standalone system message and change it to inspect the final current-turn user message.

Expected assertion shape:

```swift
let currentInputMessages = request.messages.filter {
    $0.role == "user" && $0.content.contains("CURRENT_INPUT_UNIQUE_TEXT")
}
#expect(currentInputMessages.count == 1)

let currentTurn = try #require(currentInputMessages.first)
#expect(currentTurn.content.contains("[Time] "))
```

- [ ] **Step 2: Add final API order test**

Add a Feature-level test that sends through `ChatViewModel.sendMessage(...)`, captures `APIRequest.messages`, and checks:

```swift
let compressedOrHistoryIndex = try #require(messages.firstIndex { $0.content.contains("Previous assistant turn") || $0.content.contains("[Previously]") })
let exampleIndex = try #require(messages.firstIndex { $0.content.contains("[Example Dialogs]") })
let memoryIndex = try #require(messages.firstIndex { $0.content.contains("[Memories]") })
let currentTurnIndex = try #require(messages.firstIndex { $0.content.contains("CURRENT_INPUT_UNIQUE_TEXT") })

#expect(compressedOrHistoryIndex < exampleIndex)
#expect(exampleIndex < memoryIndex)
#expect(memoryIndex < currentTurnIndex)
#expect(currentTurnIndex == messages.indices.last)
```

If the test fixture has no world book configured, do not assert world book in this Feature-level test; world book ordering is already covered in `PromptAssemblerTests`.

- [ ] **Step 3: Run focused chat tests**

Run:

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests
```

Expected: PASS.

---

### Task 6: Update Documentation and Anti-Entropy Evidence

**Files:**
- Modify: `arch/modules/prompt-assembly.md`
- Modify: `.github/instructions/prompt-engine.instructions.md`
- Modify: `arch/AntiEntropy/triangle-consistency.md`
- Modify: `arch/AntiEntropy/propagation-audit.md`
- Modify: `arch/roadmap.md`

- [ ] **Step 1: Update prompt architecture evidence**

In `arch/modules/prompt-assembly.md`, replace "当前源码尚未同步" and "目标差异" wording with implementation evidence:

```markdown
- 当前实现描述：
  - `PromptAssemblyPreview` 输出 `stableIdentityMessages`、`currentTurnContextMessages`、`currentTurnMessage`。
  - `assemble(...)` 输出顺序为 `stableIdentityMessages + processedHistory + currentTurnContextMessages + currentTurnMessage`。
  - 示例对话以 `[Example Dialogs]` labeled system block 注入。
  - 世界书条目统一进入 `[World Book Entries]` block，不再按 `after_system` / `before_history` 拆分最终位置。
  - 时间上下文位于最后一条 current turn user message 内。
```

- [ ] **Step 2: Update prompt-engine instruction**

In `.github/instructions/prompt-engine.instructions.md`, replace the old assembly order with:

```markdown
1. Stable Identity: base system prompt, character description, scenario, slowPlot directive
2. Stable Conversation State: compressed context, checkpoint 后 history
3. Current-Turn Context: example dialogs block, world book entries block, memories block
4. Current Turn: current user input + `[Time] <ISO8601> [/Time]`
```

- [ ] **Step 3: Update anti-entropy docs**

In `arch/AntiEntropy/triangle-consistency.md`, update the PromptEngine row and old "before_history -> memory -> exampleDialogs" closure text to the new four-layer contract.

In `arch/AntiEntropy/propagation-audit.md`, update the Prompt/Context chain section to say:

```markdown
`PromptAssembler.preview` 计算 Stable Identity、Current-Turn Context、Current Turn 与 fixedTokens -> `ContextManager.prepareHistory` 处理 Stable Conversation State -> `PromptAssembler.assemble` 输出四层顺序。
```

- [ ] **Step 4: Update roadmap**

In `arch/roadmap.md`, update any prompt checklist item that still says time context is pending or that describes the old world book/memory order.

- [ ] **Step 5: Run markdown and diff checks**

Run:

```bash
git diff --check -- arch/modules/prompt-assembly.md .github/instructions/prompt-engine.instructions.md arch/AntiEntropy/triangle-consistency.md arch/AntiEntropy/propagation-audit.md arch/roadmap.md
```

Expected: no output.

---

### Task 7: Verification and Closeout

**Files:**
- Verify all modified source, test, and doc files.

- [ ] **Step 1: Run focused prompt suite**

Run:

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:OpenChatTests/PromptAssemblerTests
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 2: Run focused chat prompt suite**

Run:

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 3: Run combined focused suite**

Run:

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:OpenChatTests/PromptAssemblerTests -only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 4: Run full suite**

Run:

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Inspect final diff**

Run:

```bash
git diff --stat
git diff -- OpenChat/Core/PromptEngine OpenChatTests/Core/PromptEngineTests OpenChatTests/Features/ChatTests arch/modules/prompt-assembly.md .github/instructions/prompt-engine.instructions.md arch/AntiEntropy/triangle-consistency.md arch/AntiEntropy/propagation-audit.md arch/roadmap.md
```

Expected:

- Source changes limited to PromptEngine.
- Feature changes limited to prompt assembly tests unless a call-site compile error forces a narrow adjustment.
- Docs state the new four-layer order as implemented, not planned.

## Self-Review Checklist

- [ ] User design item 1 covered: four-layer output structure in `PromptAssemblyPreview`.
- [ ] User design item 2 covered: current prompt assembly structure is adjusted without changing `ChatViewModel` chain.
- [ ] User design item 3 covered: final order matches `arch/modules/prompt-assembly.md`.
- [ ] User design item 4 covered: labeled system block helpers and tests.
- [ ] User design item 5 covered: docs and tests verify prompt assembly document order.
- [ ] No signing config changes.
- [ ] No database migration changes.
- [ ] No unrelated `.serena` / `.obsidian` changes included in implementation commits.
