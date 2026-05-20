import Foundation
import Testing

@testable import OpenChat

@Suite("Prompt assembler")
struct PromptAssemblerTests {
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

    @Test func test_preview_current_turn_includes_time_context() throws {
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

        let currentTurn = preview.currentTurnMessage
        #expect(currentTurn.role == "user")
        #expect(currentTurn.content.hasPrefix("hello"))
        #expect(currentTurn.content.contains("[Time] "))
        #expect(currentTurn.content.hasSuffix(" [/Time]"))

        let timestamp = try #require(
            currentTurn.content
                .components(separatedBy: "[Time] ")
                .last?
                .replacing("[Time] ", with: "")
                .replacing(" [/Time]", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        )
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

        let memoryBlock = try #require(preview.currentTurnContextMessages.first { $0.content.contains("[Memories]") })
        #expect(memoryBlock.role == "system")
        #expect(memoryBlock.content.contains("Hero saved village."))
        #expect(memoryBlock.content.contains("Sky is green in this world."))
        #expect(preview.tokenUsage.memories > 0)
    }

    @Test func test_memory_trim_preserves_retrieval_order_when_budget_drops_high_importance_memory() throws {
        let conversation = TestHelpers.makeConversation(slowPlotMode: false)
        let cardId = "card-ordering"
        let filler = String(repeating: "detail ", count: 24)
        let first = TestHelpers.makeMemoryEntry(
            characterCardId: cardId,
            content: "alpha relevant first memory. \(filler)",
            memoryType: .fact,
            importance: 10
        )
        let second = TestHelpers.makeMemoryEntry(
            characterCardId: cardId,
            content: "bravo relevant second memory. \(filler)",
            memoryType: .fact,
            importance: 50
        )
        let third = TestHelpers.makeMemoryEntry(
            characterCardId: cardId,
            content: "cedar less relevant third memory. \(filler)",
            memoryType: .fact,
            importance: 100
        )

        let preview = PromptAssembler.preview(
            conversation: conversation,
            characterCard: nil,
            worldBook: nil,
            worldBookEntries: [],
            memories: [first, second, third],
            recentMessages: [],
            currentInput: "hello",
            endpoint: TestHelpers.makeEndpoint(maxContextTokens: 2200)
        )

        let memoryBlock = try #require(preview.currentTurnContextMessages.first { $0.content.contains("[Memories]") })
        let firstRange = try #require(memoryBlock.content.range(of: "alpha relevant first memory."))
        let secondRange = try #require(memoryBlock.content.range(of: "bravo relevant second memory."))

        #expect(firstRange.lowerBound < secondRange.lowerBound)
        #expect(!memoryBlock.content.contains("cedar less relevant third memory."))
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

        #expect(result.messages.contains(where: { $0.content.contains("[Memories]") }))
        let currentTurn = try #require(result.messages.last)
        #expect(currentTurn.content.contains("[Time] "))
        #expect(currentTurn.content.hasSuffix(" [/Time]"))
        #expect(result.tokenUsage.timeContext > 0)
        #expect(result.tokenUsage.memories > 0)
    }

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

    @Test func test_world_book_block_shape_remains_compatible_for_semantic_candidates() throws {
        let conversation = TestHelpers.makeConversation(slowPlotMode: false)
        let card = TestHelpers.makeCharacterCard()
        let book = TestHelpers.makeWorldBook(isEnabled: true)
        let semanticEntry = TestHelpers.makeWorldBookEntry(
            worldBookId: book.id,
            title: "Moon Archive",
            keywords: ["never-triggered-keyword"],
            content: "The semantic-only lore survives prompt assembly."
        )

        let result = PromptAssembler.assembleWithPreselectedWorldBookEntries(
            conversation: conversation,
            characterCard: card,
            worldBook: book,
            worldBookEntries: [semanticEntry],
            processedHistory: [],
            currentInput: "Where are the old maps kept?",
            endpoint: TestHelpers.makeEndpoint(maxContextTokens: 4000)
        )

        let worldBookMessage = try #require(result.messages.first { $0.content.contains("[World Book Entries]") })
        #expect(worldBookMessage.role == "system")
        #expect(worldBookMessage.content.contains("[World Book Entries]"))
        #expect(worldBookMessage.content.contains("[World Book: Moon Archive]"))
        #expect(worldBookMessage.content.contains("The semantic-only lore survives prompt assembly."))
        #expect(worldBookMessage.content.contains("[/World Book Entries]"))
        #expect(result.triggeredEntries == [semanticEntry.id])
    }

    @Test func test_packet_prompt_uses_compatible_worldbook_and_memory_blocks() throws {
        let conversation = TestHelpers.makeConversation(slowPlotMode: false)
        let card = TestHelpers.makeCharacterCard()
        let packet = Self.makePacket(entries: [
            BackgroundEntry(
                id: "memory:one",
                sourceType: .memory,
                sourceId: "one",
                title: "event",
                content: "Packet memory content.",
                rank: 2,
                score: 0.8,
                estimatedTokens: 4,
                reason: "semantic",
                metadata: ["memoryType": "event"]
            ),
            BackgroundEntry(
                id: "worldBook:moon",
                sourceType: .worldBook,
                sourceId: "moon",
                title: "Moon Archive",
                content: "Packet world-book content.",
                rank: 1,
                score: 0.9,
                estimatedTokens: 4,
                reason: "semantic",
                metadata: [:]
            ),
        ])

        let result = PromptAssembler.assemble(
            conversation: conversation,
            characterCard: card,
            backgroundPacket: packet,
            processedHistory: [],
            currentInput: "Where are the old maps kept?",
            endpoint: TestHelpers.makeEndpoint(maxContextTokens: 4000)
        )

        let worldBookIndex = try #require(result.messages.firstIndex { $0.content.contains("[World Book Entries]") })
        let memoryIndex = try #require(result.messages.firstIndex { $0.content.contains("[Memories]") })
        #expect(worldBookIndex < memoryIndex)
        #expect(result.messages[worldBookIndex].content.contains("[World Book: Moon Archive]"))
        #expect(result.messages[worldBookIndex].content.contains("Packet world-book content."))
        #expect(result.messages[memoryIndex].content.contains("[Memory — event]"))
        #expect(result.messages[memoryIndex].content.contains("Packet memory content."))
        #expect(!result.messages.contains { $0.content.contains("semantic") && $0.content.contains("score") })
        #expect(result.triggeredEntries == ["moon"])
    }

    @Test func test_packet_prompt_budget_trims_raw_packet_entries() throws {
        let conversation = TestHelpers.makeConversation(slowPlotMode: false)
        let filler = String(repeating: "detail ", count: 80)
        let packet = Self.makePacket(entries: [
            BackgroundEntry(
                id: "worldBook:first",
                sourceType: .worldBook,
                sourceId: "first",
                title: "First",
                content: "first included \(filler)",
                rank: 1,
                score: 1,
                estimatedTokens: 40,
                reason: nil,
                metadata: [:]
            ),
            BackgroundEntry(
                id: "worldBook:second",
                sourceType: .worldBook,
                sourceId: "second",
                title: "Second",
                content: "second trimmed \(filler)",
                rank: 2,
                score: 0.9,
                estimatedTokens: 40,
                reason: nil,
                metadata: [:]
            ),
        ])

        let preview = PromptAssembler.preview(
            conversation: conversation,
            characterCard: nil,
            backgroundPacket: packet,
            currentInput: "hello",
            endpoint: TestHelpers.makeEndpoint(maxContextTokens: 600)
        )

        let worldBookBlock = try #require(preview.currentTurnContextMessages.first { $0.content.contains("[World Book Entries]") })
        #expect(worldBookBlock.content.contains("first included"))
        #expect(!worldBookBlock.content.contains("second trimmed"))
        #expect(preview.triggeredEntries == ["first"])
        #expect(preview.tokenUsage.worldBookEntries == TokenCounter.count(message: worldBookBlock))
    }

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
        #expect(exampleBlock.content.contains("Assistant: Hello there."))
        #expect(!result.messages.contains { $0.role == "user" && $0.content == "Hello" })
        #expect(!result.messages.contains { $0.role == "assistant" && $0.content == "Hello there." })
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

        let slowPlotIndex = preview.stableIdentityMessages.firstIndex { $0.content.contains("场景维持者") }
        let scenarioIndex = preview.stableIdentityMessages.firstIndex { $0.content.localizedCaseInsensitiveContains("tavern") }

        #expect(slowPlotIndex != nil)
        if let si = scenarioIndex, let spi = slowPlotIndex {
            #expect(spi == si + 1)
        }
        #expect(preview.currentTurnMessage.content.contains("[Time] "))
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

        let hasSlowPlot = preview.stableIdentityMessages.contains { $0.content.contains("场景维持者") }
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

    @Test func test_backgroundPacketStateEntriesAreAssembledIntoBackgroundBlock() throws {
        let conversation = TestHelpers.makeConversation(slowPlotMode: false)
        let card = TestHelpers.makeCharacterCard(id: "card-state", name: "Mara")
        let packet = Self.makePacket(entries: [
            Self.makeBackgroundEntry(
                id: "characterState:card-state",
                sourceType: .characterState,
                sourceId: "card-state",
                title: "Mara",
                content: "Character: Mara\nPersonality: Focused."
            ),
            Self.makeBackgroundEntry(
                id: "conversationState:\(conversation.id)",
                sourceType: .conversationState,
                sourceId: conversation.id,
                title: conversation.title,
                content: "Recent Turns:\nuser: Hold position."
            ),
        ])

        let preview = PromptAssembler.preview(
            conversation: conversation,
            characterCard: card,
            backgroundPacket: packet,
            stageTurnPlan: nil,
            currentInput: "continue",
            endpoint: TestHelpers.makeEndpoint(maxContextTokens: 2000)
        )

        let block = try #require(preview.currentTurnContextMessages.first { $0.content.contains("[Background]") })
        #expect(block.content.contains("[Character State: Mara]"))
        #expect(block.content.contains("[Conversation State: \(conversation.title)]"))
        #expect(block.content.contains("Hold position."))
        #expect(preview.tokenUsage.background > 0)
    }

    private static func makePacket(entries: [BackgroundEntry]) -> BackgroundPacket {
        BackgroundPacket(
            entries: entries,
            omitted: [],
            diagnostics: BackgroundDiagnostics(
                requestId: "conversation-1",
                startedAt: Date(timeIntervalSince1970: 1),
                endedAt: Date(timeIntervalSince1970: 1),
                elapsedMilliseconds: 0,
                policyProfile: [:],
                agentPolicySummary: [:],
                sourceSummaries: [],
                inputCandidateCount: entries.count,
                selectedIds: entries.map(\.id),
                omitted: [],
                fallbacks: [],
                warnings: []
            )
        )
    }

    private static func makeBackgroundEntry(
        id: String,
        sourceType: BackgroundSourceType,
        sourceId: String,
        title: String?,
        content: String
    ) -> BackgroundEntry {
        BackgroundEntry(
            id: id,
            sourceType: sourceType,
            sourceId: sourceId,
            title: title,
            content: content,
            rank: 1,
            score: 1,
            estimatedTokens: TokenCounter.count(content),
            reason: "test",
            metadata: [:]
        )
    }
}
