import Foundation
import Testing

@testable import OpenChat

@Suite("Prepared history")
struct PreparedHistoryTests {
    @Test func test_messagesForLegacyPrompt_prefixes_compressed_context_when_present() {
        let checkpoint = TestHelpers.makeCompressionCheckpoint(
            conversationId: "conv",
            summary: "Older events summary.",
            summaryTokenCount: 4
        )
        let recent = TestHelpers.makeMessage(
            conversationId: "conv",
            role: "user",
            content: "Recent message",
            sortOrder: 3
        )
        let prepared = PreparedHistory(
            compressedContext: checkpoint,
            messageHistory: [recent],
            didCreateCheckpoint: false,
            didFallbackToTruncation: false
        )

        let messages = prepared.messagesForLegacyPrompt(conversationId: "conv")

        #expect(messages.count == 2)
        #expect(messages[0].role == "system")
        #expect(messages[0].content == "[Previously]\nOlder events summary.")
        #expect(messages[0].isCompressed)
        #expect(messages[1].content == "Recent message")
    }

    @Test func test_messagesForLegacyPrompt_without_checkpoint_returns_historyOnly() {
        let recent = TestHelpers.makeMessage(
            conversationId: "conv",
            role: "assistant",
            content: "Recent reply",
            sortOrder: 2
        )
        let prepared = PreparedHistory(
            compressedContext: nil,
            messageHistory: [recent],
            didCreateCheckpoint: false,
            didFallbackToTruncation: false
        )

        #expect(prepared.messagesForLegacyPrompt(conversationId: "conv").map(\.content) == ["Recent reply"])
    }
}
