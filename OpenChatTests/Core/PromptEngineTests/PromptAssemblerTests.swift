import Foundation
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
        let memory = TestHelpers.makeMemoryEntry(characterCardId: card.id, content: "Hero remembers the dragon map.", memoryType: .event)

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

        #expect(preview.messagesBeforeHistory.count >= 5)
        #expect(preview.messagesBeforeHistory[0].content.contains("You are"))
        #expect(preview.messagesBeforeHistory[1].content.contains("After system note."))
        #expect(preview.messagesBeforeHistory[2].content.contains("Character:"))
        #expect(preview.messagesBeforeHistory[3].content.localizedCaseInsensitiveContains("tavern"))
        #expect(preview.messagesBeforeHistory[4].content.contains("场景维持者"))
        #expect(preview.messagesBeforeHistory.contains(where: { $0.content.contains("Before history note.") }))
        let beforeIndex = try #require(preview.messagesBeforeHistory.firstIndex { $0.content.contains("Before history note.") })
        let memoryIndex = try #require(preview.messagesBeforeHistory.firstIndex { $0.content.contains("Hero remembers the dragon map.") })
        let exampleIndex = try #require(preview.messagesBeforeHistory.firstIndex { $0.content == "Hello" })
        #expect(beforeIndex < memoryIndex)
        #expect(memoryIndex < exampleIndex)
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

        let timeContext = try #require(preview.messagesBeforeHistory.first { $0.content.hasPrefix("[Time] ") })
        #expect(timeContext.content.hasSuffix(" [/Time]"))

        let timestamp = timeContext.content
            .replacing("[Time] ", with: "")
            .replacing(" [/Time]", with: "")
        #expect(ISO8601DateFormatter().date(from: timestamp) != nil)
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
        #expect(result.messages.contains(where: { $0.content.hasPrefix("[Time] ") && $0.content.hasSuffix(" [/Time]") }))
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

    @Test func test_preview_includes_slow_plot_directive_when_enabled() throws {
        let conversation = TestHelpers.makeConversation(slowPlotMode: true)
        let card = TestHelpers.makeCharacterCard()

        let preview = PromptAssembler.preview(
            conversation: conversation,
            characterCard: card,
            worldBook: nil,
            worldBookEntries: [],
            recentMessages: [],
            currentInput: "hello",
            endpoint: TestHelpers.makeEndpoint(maxContextTokens: 2000)
        )

        let slowPlotIndex = preview.messagesBeforeHistory.firstIndex { $0.content.contains("场景维持者") }
        let scenarioIndex = preview.messagesBeforeHistory.firstIndex { $0.content.localizedCaseInsensitiveContains("tavern") }
        let timeIndex = preview.messagesBeforeHistory.firstIndex { $0.content.hasPrefix("[Time] ") }

        #expect(slowPlotIndex != nil)
        if let si = scenarioIndex, let spi = slowPlotIndex {
            #expect(spi == si + 1)
        }
        if let spi = slowPlotIndex, let ti = timeIndex {
            #expect(ti == spi + 1)
        }
        #expect(preview.tokenUsage.slowPlotDirective > 0)
    }

    @Test func test_preview_excludes_slow_plot_directive_when_disabled() throws {
        let conversation = TestHelpers.makeConversation(slowPlotMode: false)

        let preview = PromptAssembler.preview(
            conversation: conversation,
            characterCard: nil,
            worldBook: nil,
            worldBookEntries: [],
            recentMessages: [],
            currentInput: "hello",
            endpoint: TestHelpers.makeEndpoint(maxContextTokens: 2000)
        )

        let hasSlowPlot = preview.messagesBeforeHistory.contains { $0.content.contains("场景维持者") }
        #expect(!hasSlowPlot)
        #expect(preview.tokenUsage.slowPlotDirective == 0)
    }

    @Test func test_slow_plot_directive_tokens_counted_in_budget() throws {
        let enabledConversation = TestHelpers.makeConversation(slowPlotMode: true)
        let disabledConversation = TestHelpers.makeConversation(slowPlotMode: false)
        let endpoint = TestHelpers.makeEndpoint(maxContextTokens: 2000)

        let enabledPreview = PromptAssembler.preview(
            conversation: enabledConversation,
            characterCard: nil,
            worldBook: nil,
            worldBookEntries: [],
            recentMessages: [],
            currentInput: "hello",
            endpoint: endpoint
        )
        let disabledPreview = PromptAssembler.preview(
            conversation: disabledConversation,
            characterCard: nil,
            worldBook: nil,
            worldBookEntries: [],
            recentMessages: [],
            currentInput: "hello",
            endpoint: endpoint
        )

        #expect(enabledPreview.fixedTokens > disabledPreview.fixedTokens)
        #expect(enabledPreview.historyBudget < disabledPreview.historyBudget)
    }
}
