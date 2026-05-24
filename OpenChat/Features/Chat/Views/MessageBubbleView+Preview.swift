import SwiftUI

#Preview("Telegram Stack") {
    VStack(spacing: 2) {
        MessageBubbleView(
            item: MessageDisplayItem(
                record: MessageRecord(
                    id: "1",
                    conversationId: "c1",
                    role: "assistant",
                    content: "I can keep the reply compact while still rendering **Markdown**.",
                    tokenCount: 18,
                    isCompressed: false,
                    originalContent: nil,
                    sortOrder: 0,
                    createdAt: .now,
                    reasoningContent: nil
                )
            ),
            isGroupedWithNext: true,
            onEdit: {},
            onDelete: {},
            onRegenerate: {}
        )
        MessageBubbleView(
            item: MessageDisplayItem(
                record: MessageRecord(
                    id: "2",
                    conversationId: "c1",
                    role: "assistant",
                    content: "Grouped assistant messages share spacing while keeping the rail visually clean.",
                    tokenCount: 22,
                    isCompressed: false,
                    originalContent: nil,
                    sortOrder: 1,
                    createdAt: .now,
                    reasoningContent: nil
                )
            ),
            isGroupedWithPrevious: true,
            onEdit: {},
            onDelete: {},
            onRegenerate: {}
        )
        MessageBubbleView(
            item: MessageDisplayItem(
                record: MessageRecord(
                    id: "3",
                    conversationId: "c1",
                    role: "user",
                    content: "Good. Make it feel like a modern chat app.",
                    tokenCount: 12,
                    isCompressed: false,
                    originalContent: nil,
                    sortOrder: 2,
                    createdAt: .now,
                    reasoningContent: nil
                )
            ),
            onEdit: {},
            onDelete: {},
            onRegenerate: {}
        )
    }
    .padding()
    .background(OpenChatDesignSystem.Surface.pageBackground)
}
