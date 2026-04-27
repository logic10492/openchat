# Triangle Consistency Repair Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Repair the OpenChat `arch-test` / `arch-src` / `src-test` drift called out by `arch/AntiEntropy/triangle-consistency.md`, with Prompt time context standardized to ISO8601.

**Architecture:** Follow the repair order in `arch/AntiEntropy/triangle-consistency.md`: first lock the Chat prompt assembly chain with a Feature-level test, then align PromptAssembler behavior and tests, then clean database migration architecture drift, and finally write the implementation evidence back into arch docs. The broad Feature-layer dependency drift is intentionally split into a separate repair plan artifact because it crosses App shell, Feature navigation, and Shared/Core ownership.

**Tech Stack:** Swift 6, Swift Testing, SwiftUI `@Observable`, Swift Concurrency, GRDB.swift, URLSession/AsyncBytes, Xcode project driven by `OpenChat.xcodeproj`.

---

## Scope Decisions

1. Time format target is ISO8601 in Prompt context. The source output must become `[Time] <ISO8601-with-timezone> [/Time]`.
2. Prompt segment order follows the current arch contract: `before_history` world book entries come before memory entries, and memory entries come before example dialogs.
3. Chat should keep optimistic user-message persistence, but the current user message must be excluded from prompt history before `PromptAssembler.assemble()` appends `currentInput`.
4. Memory lifecycle trigger docs are repaired to the current runtime reality in this wave: periodic extraction every 10 generated messages plus `ChatView.onDisappear`; App-background lifecycle hooks can be planned separately after this consistency repair.
5. The Feature/App/Shared boundary drift is not mixed into this source repair. This plan writes a dedicated boundary repair plan so it can be implemented without coupling it to prompt behavior changes.

## File Structure

- Create: `OpenChatTests/Features/ChatTests/ChatViewModelPromptAssemblyTests.swift`
  - Feature-level regression test that proves the final API request includes the current user input exactly once.
- Modify: `OpenChat/Core/ContextManager/ContextManager.swift`
  - Add an overload that processes an already-filtered message list while preserving the existing DB-backed API.
- Modify: `OpenChat/Features/Chat/ViewModels/ChatViewModel+Support.swift`
  - Build a prompt-history list that excludes the current input record for send, regenerate, and edit flows.
- Modify: `OpenChat/Core/PromptEngine/PromptAssembler.swift`
  - Emit ISO8601 time context and enforce world-book-before-memory ordering.
- Modify: `OpenChatTests/Core/PromptEngineTests/PromptAssemblerTests.swift`
  - Update time assertions to parse ISO8601 and lock relative order of `before_history`, memory, and examples.
- Modify: `OpenChat/Core/Database/Migrations.swift`
  - Decouple migrations from live Record and enum symbols by using migration-local table/default constants.
- Modify: `OpenChatTests/Core/DatabaseTests/MigrationTests.swift`
  - Add a source-contract test that prevents migrations from referencing runtime Record table names or runtime enum cases.
- Modify docs:
  - `arch/index.md`
  - `arch/source-tree.md`
  - `arch/data-model.md`
  - `arch/modules/prompt-assembly.md`
  - `arch/modules/chat.md`
  - `arch/modules/memory/index.md`
  - `arch/modules/settings/api-endpoint.md`
  - `arch/roadmap.md`
  - `arch/AntiEntropy/triangle-consistency.md`
  - `arch/AntiEntropy/propagation-audit.md`
- Create: `arch/AntiEntropy/layering-repair-plan.md`
  - Dedicated plan for Feature/App/Shared dependency boundary cleanup.

## Baseline Commands

- Full test command:

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17'
```

- Focused prompt tests:

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:OpenChatTests/PromptAssemblerTests
```

- Focused migration tests:

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:OpenChatTests/MigrationTests
```

---

### Task 1: Lock Chat Current Input De-duplication

**Files:**
- Create: `OpenChatTests/Features/ChatTests/ChatViewModelPromptAssemblyTests.swift`
- Modify: `OpenChat/Core/ContextManager/ContextManager.swift`
- Modify: `OpenChat/Features/Chat/ViewModels/ChatViewModel+Support.swift`

- [ ] **Step 1: Write the failing Feature-level test**

Create `OpenChatTests/Features/ChatTests/ChatViewModelPromptAssemblyTests.swift`:

```swift
import Foundation
import Testing

@testable import OpenChat

private final class RequestCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var request: APIRequest?

    func store(_ request: APIRequest) {
        lock.lock()
        defer { lock.unlock() }
        self.request = request
    }

    func load() -> APIRequest? {
        lock.lock()
        defer { lock.unlock() }
        return request
    }
}

private extension URLRequest {
    func openChatTestBodyData() throws -> Data {
        if let httpBody {
            return httpBody
        }
        guard let httpBodyStream else {
            throw URLError(.cannotDecodeRawData)
        }

        httpBodyStream.open()
        defer { httpBodyStream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let bytesRead = buffer.withUnsafeMutableBufferPointer { pointer in
                httpBodyStream.read(pointer.baseAddress!, maxLength: pointer.count)
            }
            if bytesRead < 0 {
                throw httpBodyStream.streamError ?? URLError(.cannotDecodeRawData)
            }
            if bytesRead == 0 {
                break
            }
            data.append(contentsOf: buffer.prefix(bytesRead))
        }
        return data
    }
}

@MainActor
@Suite("Chat prompt assembly")
struct ChatViewModelPromptAssemblyTests {
    @Test func test_sendMessage_sends_current_input_once() async throws {
        let databaseManager = try TestHelpers.makeDatabaseManager()
        let now = Date()
        let endpoint = APIEndpointRecord(
            id: "endpoint-1",
            name: "Local",
            baseURL: "http://localhost:8080/v1",
            apiKey: "test-key",
            isDefault: true,
            createdAt: now,
            updatedAt: now
        )
        let model = EndpointModelRecord(
            id: "model-1",
            endpointId: endpoint.id,
            modelId: "test-model",
            maxContextTokens: 4096,
            apiMode: APIMode.chatCompletions.rawValue,
            isDefault: true,
            isManual: true,
            createdAt: now
        )
        var conversation = TestHelpers.makeConversation(slowPlotMode: false)
        conversation.apiEndpointId = endpoint.id
        conversation.modelName = model.modelId
        conversation.isTitleGenerated = true

        try await databaseManager.saveEndpoint(endpoint)
        try await databaseManager.saveEndpointModel(model)
        try await databaseManager.saveConversation(conversation)
        try await databaseManager.saveMessage(
            TestHelpers.makeMessage(
                conversationId: conversation.id,
                role: "assistant",
                content: "Previous assistant turn.",
                sortOrder: 1
            )
        )

        let capture = RequestCapture()
        let session = MockURLProtocol.makeSession { request in
            let body = try request.openChatTestBodyData()
            capture.store(try JSONDecoder().decode(APIRequest.self, from: body))
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            let payload = """
            data: {"id":"1","choices":[{"index":0,"delta":{"content":"Done"},"finish_reason":"stop"}]}

            data: [DONE]
            """
            return (response, Data(payload.utf8))
        }
        let apiClient = APIClient(session: session)
        let contextManager = ContextManager(databaseManager: databaseManager, apiClient: apiClient)
        let memoryManager = MemoryManager(
            databaseManager: databaseManager,
            embeddingService: EmbeddingService(),
            vectorStore: VectorStore(databaseManager: databaseManager),
            apiClient: apiClient
        )
        let viewModel = ChatViewModel(
            conversation: conversation,
            databaseManager: databaseManager,
            apiClient: apiClient,
            contextManager: contextManager,
            memoryManager: memoryManager,
            titleGenerator: TitleGenerator(apiClient: apiClient),
            appState: AppState()
        )

        viewModel.inputText = "What is this?"
        await viewModel.sendMessage()

        for _ in 0..<100 {
            if viewModel.streamTask == nil, !viewModel.isGenerating {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(viewModel.streamTask == nil)
        let request = try #require(capture.load())
        let currentInputMessages = request.messages.filter {
            $0.role == "user" && $0.content == "What is this?"
        }
        #expect(currentInputMessages.count == 1)

        let storedMessages = try await databaseManager.fetchMessages(conversationId: conversation.id)
        let storedCurrentInputs = storedMessages.filter {
            $0.role == "user" && $0.content == "What is this?"
        }
        #expect(storedCurrentInputs.count == 1)
    }
}
```

- [ ] **Step 2: Run the failing test**

Run:

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests
```

Expected: FAIL because `currentInputMessages.count` is `2` before the prompt-history filter exists.

- [ ] **Step 3: Add filtered-history support to ContextManager**

Replace `prepareHistory` in `OpenChat/Core/ContextManager/ContextManager.swift` with this overload pair:

```swift
    func prepareHistory(
        conversation: ConversationRecord,
        endpoint: APIEndpointConfig,
        fixedTokens: Int
    ) async throws -> [MessageRecord] {
        let allMessages = try await databaseManager.fetchMessages(conversationId: conversation.id)
        return try await prepareHistory(
            messages: allMessages,
            conversation: conversation,
            endpoint: endpoint,
            fixedTokens: fixedTokens
        )
    }

    func prepareHistory(
        messages allMessages: [MessageRecord],
        conversation: ConversationRecord,
        endpoint: APIEndpointConfig,
        fixedTokens: Int
    ) async throws -> [MessageRecord] {
        let totalBudget = max(Int((Double(endpoint.maxContextTokens) * 0.4).rounded(.down)), 1)
        let historyBudget = max(totalBudget - fixedTokens, 0)

        switch conversation.contextStrategyValue {
        case .truncation:
            return try await TruncationStrategy().process(allMessages: allMessages, tokenBudget: historyBudget)
        case .compression:
            do {
                return try await CompressionStrategy(apiClient: apiClient, endpoint: endpoint).process(
                    allMessages: allMessages,
                    tokenBudget: historyBudget
                )
            } catch {
                return try await TruncationStrategy().process(allMessages: allMessages, tokenBudget: historyBudget)
            }
        }
    }
```

- [ ] **Step 4: Filter current input from Chat prompt history**

In `OpenChat/Features/Chat/ViewModels/ChatViewModel+Support.swift`, add this helper inside the `extension ChatViewModel` body:

```swift
    private func makePromptHistoryMessages(
        from messages: [MessageRecord],
        prompt: String,
        persistedUserMessage: MessageRecord?
    ) -> [MessageRecord] {
        if let persistedUserMessage {
            return messages.filter { $0.id != persistedUserMessage.id }
        }

        guard let currentInputRecord = messages.last(where: {
            $0.role == "user" && $0.content == prompt
        }) else {
            return messages
        }
        return messages.filter { $0.id != currentInputRecord.id }
    }
```

Then replace the `currentMessages` use in `generateResponse`:

```swift
        let currentMessages = try await databaseManager.fetchMessages(conversationId: conversation.id)
        let promptHistoryMessages = makePromptHistoryMessages(
            from: currentMessages,
            prompt: prompt,
            persistedUserMessage: userMessageRecord
        )
```

Pass `promptHistoryMessages` into both PromptAssembler calls and ContextManager:

```swift
            recentMessages: promptHistoryMessages,
```

```swift
        let history = try await contextManager.prepareHistory(
            messages: promptHistoryMessages,
            conversation: conversation,
            endpoint: endpoint,
            fixedTokens: preview.fixedTokens
        )
```

- [ ] **Step 5: Run the focused test**

Run:

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests
```

Expected: PASS. The captured request contains exactly one `user` message with content `What is this?`.

- [ ] **Step 6: Commit Task 1**

```bash
git add OpenChatTests/Features/ChatTests/ChatViewModelPromptAssemblyTests.swift OpenChat/Core/ContextManager/ContextManager.swift OpenChat/Features/Chat/ViewModels/ChatViewModel+Support.swift
git commit -m "fix: avoid duplicate current input in chat prompt history"
```

---

### Task 2: Standardize Prompt Time Context to ISO8601

**Files:**
- Modify: `OpenChat/Core/PromptEngine/PromptAssembler.swift`
- Modify: `OpenChatTests/Core/PromptEngineTests/PromptAssemblerTests.swift`
- Modify docs later in Task 5:
  - `arch/index.md`
  - `arch/modules/prompt-assembly.md`
  - `arch/modules/chat.md`

- [ ] **Step 1: Replace the time test with an ISO8601 contract**

In `OpenChatTests/Core/PromptEngineTests/PromptAssemblerTests.swift`, replace `test_preview_includes_time_context` with:

```swift
    @Test func test_preview_includes_iso8601_time_context() throws {
        let conversation = TestHelpers.makeConversation()
        let preview = PromptAssembler.preview(
            conversation: conversation,
            characterCard: nil,
            worldBook: nil,
            worldBookEntries: [],
            recentMessages: [],
            currentInput: "hello",
            endpoint: TestHelpers.makeEndpoint(maxContextTokens: 1000)
        )

        let timeContext = try #require(preview.messagesBeforeHistory.first {
            $0.content.hasPrefix("[Time] ") && $0.content.hasSuffix(" [/Time]")
        })
        let iso8601Value = String(
            timeContext.content
                .dropFirst("[Time] ".count)
                .dropLast(" [/Time]".count)
        )
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        #expect(formatter.date(from: iso8601Value) != nil)
        #expect(!timeContext.content.contains("[Current Time:"))
        #expect(preview.tokenUsage.timeContext > 0)
    }
```

Also update this assertion in `test_assemble_includes_memories_and_time_context`:

```swift
        #expect(result.messages.contains(where: { $0.content.hasPrefix("[Time] ") }))
```

And update this lookup in `test_preview_includes_slow_plot_directive_when_enabled`:

```swift
        let timeIndex = preview.messagesBeforeHistory.firstIndex { $0.content.hasPrefix("[Time] ") }
```

- [ ] **Step 2: Run the failing prompt test**

Run:

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:OpenChatTests/PromptAssemblerTests/test_preview_includes_iso8601_time_context
```

Expected: FAIL because current source emits `[Current Time: yyyy-MM-dd EEEE HH:mm]`.

- [ ] **Step 3: Change PromptAssembler time formatting**

In `OpenChat/Core/PromptEngine/PromptAssembler.swift`, replace `makeTimeContext()` with:

```swift
    private static func makeTimeContext() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = .current
        return "[Time] \(formatter.string(from: Date())) [/Time]"
    }
```

- [ ] **Step 4: Run focused prompt tests**

Run:

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:OpenChatTests/PromptAssemblerTests
```

Expected: PASS.

- [ ] **Step 5: Commit Task 2**

```bash
git add OpenChat/Core/PromptEngine/PromptAssembler.swift OpenChatTests/Core/PromptEngineTests/PromptAssemblerTests.swift
git commit -m "fix: emit prompt time context as iso8601"
```

---

### Task 3: Align Memory and before_history World Book Ordering

**Files:**
- Modify: `OpenChat/Core/PromptEngine/PromptAssembler.swift`
- Modify: `OpenChatTests/Core/PromptEngineTests/PromptAssemblerTests.swift`
- Modify docs later in Task 5:
  - `arch/modules/prompt-assembly.md`
  - `arch/modules/memory/index.md`

- [ ] **Step 1: Extend the segment-order test**

In `OpenChatTests/Core/PromptEngineTests/PromptAssemblerTests.swift`, update `test_preview_orders_segments_correctly` so it creates a memory and passes it into preview:

```swift
        let memory = TestHelpers.makeMemoryEntry(
            characterCardId: card.id,
            content: "Ava remembers the dragon pact.",
            memoryType: .fact
        )

        let preview = PromptAssembler.preview(
            conversation: conversation,
            characterCard: card,
            worldBook: book,
            worldBookEntries: [afterEntry, beforeEntry],
            memories: [memory],
            recentMessages: [TestHelpers.makeMessage(conversationId: conversation.id, role: "assistant", content: "Old reply", sortOrder: 1)],
            currentInput: "dragon",
            endpoint: TestHelpers.makeEndpoint(maxContextTokens: 4000)
        )
```

Then add these assertions before the `triggeredEntries` assertion:

```swift
        let beforeHistoryIndex = try #require(preview.messagesBeforeHistory.firstIndex {
            $0.content.contains("Before history note.")
        })
        let memoryIndex = try #require(preview.messagesBeforeHistory.firstIndex {
            $0.content.contains("[Memory") && $0.content.contains("dragon pact")
        })
        let exampleDialogIndex = try #require(preview.messagesBeforeHistory.firstIndex {
            $0.role == "user" && $0.content == "Hello"
        })

        #expect(beforeHistoryIndex < memoryIndex)
        #expect(memoryIndex < exampleDialogIndex)
```

- [ ] **Step 2: Run the failing order test**

Run:

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:OpenChatTests/PromptAssemblerTests/test_preview_orders_segments_correctly
```

Expected: FAIL because current source appends memory before `before_history` world book entries.

- [ ] **Step 3: Swap source order**

In `OpenChat/Core/PromptEngine/PromptAssembler.swift`, replace the memory/before-history block with:

```swift
        messagesBeforeHistory.append(contentsOf: trimmedBeforeHistoryEntries.map { ChatMessage(role: "system", content: makeWorldBookMessageContent($0)) })
        if !trimmedMemories.isEmpty {
            messagesBeforeHistory.append(contentsOf: trimmedMemories.map { ChatMessage(role: "system", content: makeMemoryMessageContent($0)) })
        }
        messagesBeforeHistory.append(contentsOf: trimmedExampleDialogs)
```

- [ ] **Step 4: Run focused prompt tests**

Run:

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:OpenChatTests/PromptAssemblerTests
```

Expected: PASS.

- [ ] **Step 5: Commit Task 3**

```bash
git add OpenChat/Core/PromptEngine/PromptAssembler.swift OpenChatTests/Core/PromptEngineTests/PromptAssemblerTests.swift
git commit -m "fix: align memory prompt segment ordering"
```

---

### Task 4: Decouple Database Migrations from Runtime Record Symbols

**Files:**
- Modify: `OpenChat/Core/Database/Migrations.swift`
- Modify: `OpenChatTests/Core/DatabaseTests/MigrationTests.swift`
- Modify docs later in Task 5:
  - `arch/data-model.md`

- [ ] **Step 1: Add a migration source-contract test**

Append this test and helper to `OpenChatTests/Core/DatabaseTests/MigrationTests.swift` inside `struct MigrationTests`:

```swift
    @Test func test_migrations_do_not_reference_runtime_record_or_enum_symbols() throws {
        let source = try String(contentsOf: migrationsSourceURL(), encoding: .utf8)

        #expect(!source.contains(".databaseTableName"))
        #expect(!source.contains("APIMode."))
        #expect(!source.contains("WorldBookEntryPosition."))
        #expect(!source.contains("ContextStrategy."))
    }

    private func migrationsSourceURL() throws -> URL {
        let components = URL(fileURLWithPath: #filePath).pathComponents
        let testRootIndex = try #require(components.lastIndex(of: "OpenChatTests"))
        let rootPath = NSString.path(withComponents: Array(components.prefix(testRootIndex)))
        return URL(fileURLWithPath: rootPath)
            .appending(path: "OpenChat/Core/Database/Migrations.swift")
    }
```

- [ ] **Step 2: Run the failing migration test**

Run:

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:OpenChatTests/MigrationTests/test_migrations_do_not_reference_runtime_record_or_enum_symbols
```

Expected: FAIL because current migrations reference `.databaseTableName`, `APIMode.chatCompletions.rawValue`, `WorldBookEntryPosition.beforeHistory.rawValue`, and `ContextStrategy.truncation.rawValue`.

- [ ] **Step 3: Add migration-local constants**

In `OpenChat/Core/Database/Migrations.swift`, add this block directly inside `enum Migrations` before `static func makeMigrator()`:

```swift
    private enum Tables {
        static let apiEndpoint = "api_endpoint"
        static let endpointModel = "endpoint_model"
        static let characterCard = "character_card"
        static let worldBook = "world_book"
        static let worldBookEntry = "world_book_entry"
        static let conversation = "conversation"
        static let message = "message"
        static let memoryEntry = "memory_entry"
    }

    private enum Defaults {
        static let chatCompletions = "chatCompletions"
        static let beforeHistory = "before_history"
        static let truncation = "truncation"
    }
```

- [ ] **Step 4: Replace runtime symbol references in Migrations**

Make these replacements in `OpenChat/Core/Database/Migrations.swift`:

```swift
APIMode.chatCompletions.rawValue -> Defaults.chatCompletions
EndpointModelRecord.databaseTableName -> Tables.endpointModel
APIEndpointRecord.databaseTableName -> Tables.apiEndpoint
CharacterCardRecord.databaseTableName -> Tables.characterCard
WorldBookRecord.databaseTableName -> Tables.worldBook
WorldBookEntryRecord.databaseTableName -> Tables.worldBookEntry
ConversationRecord.databaseTableName -> Tables.conversation
MessageRecord.databaseTableName -> Tables.message
MemoryEntryRecord.databaseTableName -> Tables.memoryEntry
WorldBookEntryPosition.beforeHistory.rawValue -> Defaults.beforeHistory
ContextStrategy.truncation.rawValue -> Defaults.truncation
```

The resulting v8 table creation must read:

```swift
            try db.create(table: Tables.endpointModel) { t in
                t.column("id", .text).notNull().primaryKey()
                t.column("endpointId", .text).notNull()
                    .references(Tables.apiEndpoint, onDelete: .cascade)
                t.column("modelId", .text).notNull()
                t.column("maxContextTokens", .integer).notNull().defaults(to: 4096)
                t.column("apiMode", .text).notNull().defaults(to: Defaults.chatCompletions)
                t.column("isDefault", .boolean).notNull().defaults(to: false)
                t.column("isManual", .boolean).notNull().defaults(to: false)
                t.column("createdAt", .datetime).notNull()
                t.uniqueKey(["endpointId", "modelId"])
            }
```

- [ ] **Step 5: Run migration tests**

Run:

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:OpenChatTests/MigrationTests
```

Expected: PASS.

- [ ] **Step 6: Commit Task 4**

```bash
git add OpenChat/Core/Database/Migrations.swift OpenChatTests/Core/DatabaseTests/MigrationTests.swift
git commit -m "fix: decouple migrations from runtime records"
```

---

### Task 5: Write Back arch-src and arch-test Evidence

**Files:**
- Modify: `arch/index.md`
- Modify: `arch/source-tree.md`
- Modify: `arch/data-model.md`
- Modify: `arch/modules/prompt-assembly.md`
- Modify: `arch/modules/chat.md`
- Modify: `arch/modules/memory/index.md`
- Modify: `arch/modules/settings/api-endpoint.md`
- Modify: `arch/roadmap.md`
- Modify: `arch/AntiEntropy/triangle-consistency.md`
- Modify: `arch/AntiEntropy/propagation-audit.md`

- [ ] **Step 1: Run the full suite and capture the real count**

Run:

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17'
```

Expected after Tasks 1-4: PASS in the current audit worktree. The worktree may report `133 tests` because it includes pre-existing dirty networking tests from before this plan; the plan itself adds:

- `ChatViewModelPromptAssemblyTests.test_sendMessage_sends_current_input_once`
- `MigrationTests.test_migrations_do_not_reference_runtime_record_or_enum_symbols`

- [ ] **Step 2: Update Prompt docs**

In `arch/modules/prompt-assembly.md`, ensure the segment order says:

```markdown
│  [5] system: 时间上下文                          │
│      [Time] ISO 8601 当前时间含时区 [/Time]      │
├─────────────────────────────────────────────────┤
│  [6] system: 世界书条目 (position=before_history)│
├─────────────────────────────────────────────────┤
│  [7] system: 跨对话记忆                          │
```

Update the implementation evidence block to include:

```markdown
- `OpenChat/Core/PromptEngine/PromptAssembler.swift` — `makeTimeContext()` 输出 `[Time] <ISO8601> [/Time]`；`before_history` 世界书条目位于 memory 前。
- `OpenChatTests/Core/PromptEngineTests/PromptAssemblerTests.swift` — 覆盖 ISO8601 时间格式、memory 注入、`before_history -> memory -> exampleDialogs` 相对顺序。
```

In `arch/index.md`, replace the stale test sentence with:

```markdown
- 当前审计工作区自动化测试结果：133 个 Swift Testing 测试全部通过，覆盖数据库迁移、SSE 解析、API 客户端、Prompt 组装、关键词匹配、Token 计数、上下文截断与压缩、Chat 发送链路当前输入去重。该计数包含审计开始前已有未提交 networking 测试改动。
```

- [ ] **Step 3: Update Chat docs**

In `arch/modules/chat.md`, update the send-message flow so steps 7-9 read:

```markdown
7. 从 DB 读取当前会话消息后，构造 `promptHistoryMessages`：
   - 乐观保存的当前 user message 保留在 DB/UI 中；
   - prompt history 中排除本轮 current input record；
   - 重新生成/编辑时排除与 `currentInput` 对应的最后一条 user record。
8. `PromptAssembler.preview(...)` 使用 `promptHistoryMessages` 计算固定段 token。
9. `ContextManager.prepareHistory(messages:promptHistoryMessages, ...)` 只处理过滤后的历史，再由 `PromptAssembler.assemble(...)` 在末尾追加一次 `currentInput`。
```

Update its evidence block test line to:

```markdown
- 该模块的核心依赖和 Chat prompt 链路已通过当前审计工作区自动化测试验证（133 tests；包含审计开始前已有未提交 networking 测试改动），其中 `OpenChatTests/Features/ChatTests/ChatViewModelPromptAssemblyTests.swift` 锁定当前输入只进入 API request 一次。
```

- [ ] **Step 4: Update Memory docs to current runtime reality**

In `arch/source-tree.md`, replace the Memory feature tree with:

```markdown
│   ├── CharacterCard/
│   │   ├── Views/
│   │   │   ├── CharacterCardListView.swift
│   │   │   ├── CharacterCardEditorView.swift
│   │   │   ├── CharacterCardDetailView.swift
│   │   │   └── MemoryListView.swift
│   │   ├── ViewModels/
│   │   │   ├── CharacterCardListViewModel.swift
│   │   │   ├── CharacterCardEditorViewModel.swift
│   │   │   └── MemoryListViewModel.swift
```

In `arch/modules/memory/index.md`, replace the top file-list rows:

```markdown
| `Features/CharacterCard/Views/MemoryListView.swift` | 角色卡详情入口下的记忆列表界面 |
| `Features/CharacterCard/ViewModels/MemoryListViewModel.swift` | 记忆列表状态管理 |
```

Replace section `6.1 触发时机` with:

```markdown
### 6.1 触发时机

当前实现采用发送链路内的周期性后台提取，并保留 `ChatView.onDisappear` 触发：

- `ChatViewModel` 每完成一轮 user + assistant 生成后将 `messagesSinceLastExtraction += 2`。
- 当计数达到 `ChatViewModel.extractionInterval == 10` 时，调用 `triggerMemoryExtraction()`。
- `triggerMemoryExtraction()` 内部启动后台 `Task`，调用 `MemoryManager.extractMemories(from:)`，成功后向聊天 UI 追加 memory marker。
- `ChatView.onDisappear` 也会调用 `triggerMemoryExtraction()`，因此离开当前聊天视图或切换对话时可能触发提取。

App 进入后台的 lifecycle hook 不属于当前源码行为，作为后续 UX/生命周期增强项单独规划。
```

Update the stale `全部 73 tests 通过` line to:

```markdown
- 当前审计工作区全量 `xcodebuild test` 为 133 个 Swift Testing 测试通过；该计数包含审计开始前已有未提交 networking 测试改动。Memory 直接覆盖仍以 DB、解析、Prompt 注入为主，EmbeddingService/VectorStore KNN 属于后续测试补强范围。
```

- [ ] **Step 5: Update data model migration rule**

In `arch/data-model.md`, under migration strategy or design decisions, add:

```markdown
### Migration 源码约束

- migration 中使用迁移本地常量记录历史表名和默认值，例如 `Tables.apiEndpoint`、`Defaults.chatCompletions`。
- migration 不引用 `Record.databaseTableName`、`APIMode.*.rawValue`、`WorldBookEntryPosition.*.rawValue`、`ContextStrategy.*.rawValue`，避免未来 runtime 重命名破坏旧迁移。
- `OpenChatTests/Core/DatabaseTests/MigrationTests.swift` 中的 `test_migrations_do_not_reference_runtime_record_or_enum_symbols` 保护该约束。
```

- [ ] **Step 6: Update stale test-count docs**

Replace stale counts:

```markdown
arch/roadmap.md: 当前通过的核心测试（60 个） -> 当前审计工作区通过的 Swift Testing 测试（133 个，含审计前 dirty networking tests）
arch/modules/settings/api-endpoint.md: 全量 114 个测试通过（2026-04-18） -> 当前审计工作区全量 133 个 Swift Testing 测试通过（2026-04-27，含审计前 dirty networking tests）
```

Use the same command in each evidence block:

```markdown
`xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17'`
```

- [ ] **Step 7: Update AntiEntropy docs**

In `arch/AntiEntropy/triangle-consistency.md`, add a `修复计划写回` section:

```markdown
## 修复计划写回（2026-04-27）

- `src-test`：新增 Chat 发送链路测试，锁定当前输入只进入 request messages 一次。
- `arch-src`：Prompt 时间上下文统一为 `[Time] <ISO8601> [/Time]`；Prompt 段顺序统一为 `before_history -> memory -> exampleDialogs`；migration 源码不再引用 runtime Record/enum 符号。
- `arch-test`：PromptAssemblerTests 覆盖 ISO8601 和 memory/world-book 相对顺序；MigrationTests 覆盖 migration 源码约束；全量基线更新为当前审计工作区 133 tests。
- 分层漂移：已拆出 `arch/AntiEntropy/layering-repair-plan.md`，不在本次 prompt/db/doc 修复中混入跨层搬迁。
```

In `arch/AntiEntropy/propagation-audit.md`, add a note near the Chat chain risk:

```markdown
> 修复计划：`docs/superpowers/plans/2026-04-27-triangle-consistency-repair.md` Task 1 通过 Feature 级测试和 `promptHistoryMessages` 过滤修复当前输入重复注入风险。
```

- [ ] **Step 8: Commit Task 5**

```bash
git add arch/index.md arch/source-tree.md arch/data-model.md arch/modules/prompt-assembly.md arch/modules/chat.md arch/modules/memory/index.md arch/modules/settings/api-endpoint.md arch/roadmap.md arch/AntiEntropy/triangle-consistency.md arch/AntiEntropy/propagation-audit.md
git commit -m "docs: write back triangle consistency evidence"
```

---

### Task 6: Split Layering Drift into a Dedicated Repair Plan

**Files:**
- Create: `arch/AntiEntropy/layering-repair-plan.md`
- Modify: `arch/AntiEntropy/triangle-consistency.md`

- [ ] **Step 1: Create the boundary repair plan artifact**

Create `arch/AntiEntropy/layering-repair-plan.md`:

```markdown
# Layering Repair Plan

> Created: 2026-04-27
> Source: `arch/AntiEntropy/triangle-consistency.md` section "分层规则与当前 Feature 装配漂移"

## Goal

Repair or explicitly codify the current App / Features / Core / Shared boundary drift without mixing navigation and dependency-injection refactors into Prompt or Database consistency fixes.

## Current Drift Evidence

| Drift | Current file | Repair direction |
|---|---|---|
| Feature owns App shell navigation | `OpenChat/Features/Support/SidebarView.swift` | Move shell composition to `OpenChat/App/Views/SidebarView.swift` or document `Features/Support` as App shell after moving it under `OpenChat/App/` |
| Feature cross-composes multiple Features | `OpenChat/Features/Support/SidebarView.swift` | App shell owns Feature composition; individual Feature modules keep local views/view models |
| WorldBook opens CharacterCard UI directly | `OpenChat/Features/WorldBook/Views/WorldBookEditorView.swift` | Replace direct Feature-to-Feature navigation with App route state or a Core-level relationship service |
| ChatViewModel depends on AppState | `OpenChat/Features/Chat/ViewModels/ChatViewModel.swift` | Inject a small error-presenting closure or protocol owned outside Features |
| Shared extension calls Core TokenCounter | `OpenChat/Shared/Extensions/String+Token.swift` | Move token extension into `OpenChat/Core/PromptEngine/` or remove the extension and call `TokenCounter` directly |

## Repair Order

1. Move `Features/Support` shell files into `OpenChat/App/Views/` and regenerate the Xcode project if file membership does not update automatically.
2. Replace `ChatViewModel.appState` with injected closures:
   - `presentError: @MainActor (String) -> Void`
   - `markConversationListNeedsRefresh: @MainActor () -> Void`
3. Route WorldBook-to-CharacterCard navigation through App state rather than importing sibling Feature views directly.
4. Move `String+Token.swift` out of Shared or delete it after replacing call sites with `TokenCounter.count`.
5. Add a source-boundary test that scans Swift imports/references for `OpenChat/Features/*` sibling imports and `OpenChat/Shared/*` references to `Core` symbols.
6. Update `arch/source-tree.md` and module docs with the final boundary.

## Verification

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17'
```

Expected result for this separate repair: all tests pass, and the new source-boundary test passes.
```

- [ ] **Step 2: Link the split plan from triangle consistency**

In `arch/AntiEntropy/triangle-consistency.md`, add under the layering inconsistency:

```markdown
拆分计划：`arch/AntiEntropy/layering-repair-plan.md`。该问题跨 App shell、Feature navigation、Shared/Core 边界，不与 Prompt/Database 修复混在同一执行波次。
```

- [ ] **Step 3: Commit Task 6**

```bash
git add arch/AntiEntropy/layering-repair-plan.md arch/AntiEntropy/triangle-consistency.md
git commit -m "docs: split layering repair plan"
```

---

### Task 7: Final Verification and Cleanup

**Files:**
- Read-only verification across source, tests, and docs

- [ ] **Step 1: Run focused suites**

Run:

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:OpenChatTests/ChatViewModelPromptAssemblyTests
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:OpenChatTests/PromptAssemblerTests
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:OpenChatTests/MigrationTests
```

Expected: all three focused runs PASS.

- [ ] **Step 2: Run full test suite**

Run:

```bash
xcodebuild test -project OpenChat.xcodeproj -scheme OpenChat -destination 'platform=iOS Simulator,name=iPhone 17'
```

Expected: PASS. In the current audit worktree this is expected to report `133 tests`; note that count includes pre-existing dirty networking tests.

- [ ] **Step 3: Scan for stale Prompt time format**

Run:

```bash
rg -n "\\[Current Time:|yyyy-MM-dd EEEE HH:mm|12 个核心测试|60 个|73 tests|114 个测试" OpenChat OpenChatTests arch
```

Expected: no matches.

- [ ] **Step 4: Scan migrations for runtime symbol references**

Run:

```bash
rg -n "databaseTableName|APIMode\\.|WorldBookEntryPosition\\.|ContextStrategy\\." OpenChat/Core/Database/Migrations.swift
```

Expected: no matches.

- [ ] **Step 5: Confirm docs link to this plan**

Run:

```bash
rg -n "2026-04-27-triangle-consistency-repair|layering-repair-plan" arch docs
```

Expected: matches in `arch/AntiEntropy/triangle-consistency.md`, `arch/AntiEntropy/propagation-audit.md`, and this plan.

- [ ] **Step 6: Commit verification writeback if any docs changed**

If verification output changes the documented test count or AntiEntropy status, commit only those doc changes:

```bash
git add arch docs/superpowers/plans/2026-04-27-triangle-consistency-repair.md
git commit -m "docs: finalize triangle consistency repair plan"
```

---

## Self-Review Checklist

- Spec coverage:
  - Chat current input duplication is covered by Task 1.
  - ISO8601 Prompt time context is covered by Task 2 and Task 5.
  - Memory vs `before_history` order is covered by Task 3 and Task 5.
  - Database migration runtime-symbol drift is covered by Task 4 and Task 5.
  - Memory path/trigger drift and stale test counts are covered by Task 5.
  - Layering drift is split into `arch/AntiEntropy/layering-repair-plan.md` by Task 6.
- Placeholder scan:
  - No empty "add tests" steps or unspecified implementation steps remain.
- Type consistency:
  - `promptHistoryMessages`, `prepareHistory(messages:conversation:endpoint:fixedTokens:)`, `[Time] ... [/Time]`, and migration constants are named consistently across tasks.
