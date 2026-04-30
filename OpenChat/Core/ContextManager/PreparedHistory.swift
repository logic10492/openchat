import Foundation

struct PreparedHistory: Sendable {
    let compressedContext: CompressionCheckpointRecord?
    let messageHistory: [MessageRecord]
    let didCreateCheckpoint: Bool
    let didFallbackToTruncation: Bool

    func messagesForLegacyPrompt(conversationId: String) -> [MessageRecord] {
        guard let compressedContext else { return messageHistory }
        let compressedMessage = MessageRecord(
            id: compressedContext.id,
            conversationId: conversationId,
            role: "system",
            content: "[Previously]\n\(compressedContext.summary)",
            tokenCount: compressedContext.summaryTokenCount,
            isCompressed: true,
            originalContent: nil,
            sortOrder: compressedContext.sourceEndSortOrder,
            createdAt: compressedContext.createdAt,
            reasoningContent: nil
        )
        return [compressedMessage] + messageHistory
    }
}
