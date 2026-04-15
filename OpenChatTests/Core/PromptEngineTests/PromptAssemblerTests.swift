import Testing

@testable import OpenChat

@Suite("Prompt assembler")
struct PromptAssemblerTests {
    @Test func test_preview_orders_segments_correctly() throws {
        let conversation = TestHelpers.makeConversation()
        let card = TestHelpers.makeCharacterCard()
        let book = TestHelpers.makeWorldBook(isEnabled: true)
        let afterEntry = TestHelpers.makeWorldBookEntry(worldBookId: book.id, title: "After", keywords: ["dragon"], priority: 90, position: .afterSystem, content: "After system note.")
        let beforeEntry = TestHelpers.makeWorldBookEntry(worldBookId: book.id, title: "Before", keywords: ["dragon"], priority: 80, position: .beforeHistory, content: "Before history note.")

        let preview = PromptAssembler.preview(
            conversation: conversation,
            characterCard: card,
            worldBook: book,
            worldBookEntries: [afterEntry, beforeEntry],
            recentMessages: [TestHelpers.makeMessage(conversationId: conversation.id, role: "assistant", content: "Old reply", sortOrder: 1)],
            currentInput: "dragon",
            endpoint: TestHelpers.makeEndpoint(maxContextTokens: 1000)
        )

        #expect(preview.messagesBeforeHistory.count >= 5)
        #expect(preview.messagesBeforeHistory[0].content.contains("You are"))
        #expect(preview.messagesBeforeHistory[1].content.contains("After system note."))
        #expect(preview.messagesBeforeHistory[2].content.contains("Character:"))
        #expect(preview.messagesBeforeHistory[3].content.localizedCaseInsensitiveContains("tavern"))
        #expect(preview.messagesBeforeHistory.contains(where: { $0.content.contains("Before history note.") }))
        #expect(preview.triggeredEntries.count == 2)
    }

    @Test func test_preview_includes_time_context() throws {
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

        let hasTimeContext = preview.messagesBeforeHistory.contains { $0.content.contains("[Current Time:") }
        #expect(hasTimeContext)
        #expect(preview.tokenUsage.timeContext > 0)
    }

    @Test func test_preview_includes_memories() throws {
        let conversation = TestHelpers.makeConversation()
        let card = TestHelpers.makeCharacterCard()
        let memory1 = TestHelpers.makeMemoryEntry(characterCardId: card.id, content: "Hero saved village.", memoryType: .event, importance: 8)
        let memory2 = TestHelpers.makeMemoryEntry(characterCardId: card.id, content: "Sky is green in this world.", memoryType: .fact, importance: 6)

        let preview = PromptAssembler.preview(
            conversation: conversation,
            characterCard: card,
            worldBook: nil,
            worldBookEntries: [],
            memories: [memory1, memory2],
            recentMessages: [],
            currentInput: "hello",
            endpoint: TestHelpers.makeEndpoint(maxContextTokens: 2000)
        )

        let memoryMessages = preview.messagesBeforeHistory.filter { $0.content.contains("[Memory") }
        #expect(memoryMessages.count == 2)
        #expect(preview.tokenUsage.memories > 0)
    }

    @Test func test_assemble_includes_memories_and_time_context() throws {
        let conversation = TestHelpers.makeConversation()
        let card = TestHelpers.makeCharacterCard()
        let memory = TestHelpers.makeMemoryEntry(characterCardId: card.id, content: "Important fact.", memoryType: .fact)
        let history = [TestHelpers.makeMessage(conversationId: conversation.id, role: "user", content: "Previous", sortOrder: 1)]

        let result = PromptAssembler.assemble(
            conversation: conversation,
            characterCard: card,
            worldBook: nil,
            worldBookEntries: [],
            memories: [memory],
            recentMessages: history,
            processedHistory: history,
            currentInput: "Next question",
            endpoint: TestHelpers.makeEndpoint(maxContextTokens: 2000)
        )

        #expect(result.messages.contains(where: { $0.content.contains("[Memory") }))
        #expect(result.messages.contains(where: { $0.content.contains("[Current Time:") }))
        #expect(result.tokenUsage.timeContext > 0)
        #expect(result.tokenUsage.memories > 0)
    }

    @Test func test_token_budget_allocates_memory_budget() throws {
        let budget = TokenBudget.calculate(
            totalBudget: 1000,
            fixedTokens: 100,
            exampleDialogsTokens: 200,
            worldBookTokens: 300,
            memoryTokens: 150
        )

        #expect(budget.memoryBudget > 0)
        #expect(budget.memoryBudget <= 150)
        #expect(budget.exampleDialogsBudget + budget.worldBookBudget + budget.memoryBudget + budget.historyBudget == 1000 - 100)
    }

    @Test func test_memory_message_content_format() {
        let entry = TestHelpers.makeMemoryEntry(
            characterCardId: "test",
            content: "The hero defeated the dragon.",
            memoryType: .event
        )
        let content = PromptAssembler.makeMemoryMessageContent(entry)
        #expect(content == "[Memory — event]\nThe hero defeated the dragon.")
    }
}
