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
}
