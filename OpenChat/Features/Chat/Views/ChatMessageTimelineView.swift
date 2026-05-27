import SwiftUI

struct ChatMessageTimelineView: View {
    let messages: [MessageDisplayItem]
    let isGenerating: Bool
    let showDetailedStats: Bool
    let extractionPhase: MemoryExtractionPhase
    let backgroundDiagnostics: BackgroundDiagnostics?
    let hasEarlierMessages: Bool
    let isLoadingEarlierMessages: Bool
    let onLoadEarlier: () -> Void
    let onEdit: (MessageDisplayItem) -> Void
    let onDelete: (String) -> Void
    let onRegenerate: () -> Void
    let onDismissExtraction: () -> Void
    let onScrollingChanged: (Bool) -> Void

    var body: some View {
        ChatTimelineUIKitRepresentable(
            configuration: ChatTimelineConfiguration(
                messages: messages,
                isGenerating: isGenerating,
                showDetailedStats: showDetailedStats,
                extractionPhase: extractionPhase,
                backgroundDiagnostics: backgroundDiagnostics,
                hasEarlierMessages: hasEarlierMessages,
                isLoadingEarlierMessages: isLoadingEarlierMessages,
                onLoadEarlier: onLoadEarlier,
                onEdit: onEdit,
                onDelete: onDelete,
                onRegenerate: onRegenerate,
                onDismissExtraction: onDismissExtraction,
                onScrollingChanged: onScrollingChanged
            )
        )
    }
}

#Preview("Telegram Stage Timeline") {
    ZStack {
        ChatConversationBackground(
            isGenerating: false,
            isEnabled: true,
            isTimelineScrolling: false
        )
        ChatMessageTimelineView(
            messages: MessageDisplayItem.stagePreviewMessages(),
            isGenerating: false,
            showDetailedStats: false,
            extractionPhase: .idle,
            backgroundDiagnostics: nil,
            hasEarlierMessages: false,
            isLoadingEarlierMessages: false,
            onLoadEarlier: {},
            onEdit: { _ in },
            onDelete: { _ in },
            onRegenerate: {},
            onDismissExtraction: {},
            onScrollingChanged: { _ in }
        )
    }
}

private extension MessageDisplayItem {
    static func stagePreviewMessages() -> [MessageDisplayItem] {
        let baseDate = Date(timeIntervalSince1970: 1_800_000_000)
        return [
            makePreviewMessage(
                id: "stage-preview-1",
                role: "user",
                content: "Mara, answer first. Io can follow after you confirm the gate is safe.",
                sortOrder: 0,
                createdAt: baseDate
            ),
            makePreviewMessage(
                id: "stage-preview-2",
                role: "assistant",
                content: "The gate is quiet. I can hold the threshold while Io checks the archive mark.",
                sortOrder: 1,
                createdAt: baseDate.addingTimeInterval(14),
                speakerId: "mara",
                speakerName: "Mara"
            ),
            makePreviewMessage(
                id: "stage-preview-3",
                role: "assistant",
                content: "The mark is fresh, but the seal is intact. We should move before the next patrol.",
                sortOrder: 2,
                createdAt: baseDate.addingTimeInterval(38),
                speakerId: "io",
                speakerName: "Io"
            ),
            makePreviewMessage(
                id: "stage-preview-4",
                role: "user",
                content: "Keep the pace slow and stay in scene.",
                sortOrder: 3,
                createdAt: baseDate.addingTimeInterval(80)
            ),
            makePreviewMessage(
                id: "stage-preview-5",
                role: "assistant",
                content: "Then we wait for one breath, no more. The hinges will tell us if the hall is awake.",
                sortOrder: 4,
                createdAt: baseDate.addingTimeInterval(112),
                speakerId: "mara",
                speakerName: "Mara"
            ),
        ]
    }

    private static func makePreviewMessage(
        id: String,
        role: String,
        content: String,
        sortOrder: Int,
        createdAt: Date,
        speakerId: String? = nil,
        speakerName: String? = nil
    ) -> MessageDisplayItem {
        var record = MessageRecord(
            id: id,
            conversationId: "stage-preview",
            role: role,
            content: content,
            tokenCount: TokenCounter.count(content),
            isCompressed: false,
            originalContent: nil,
            sortOrder: sortOrder,
            createdAt: createdAt,
            reasoningContent: nil
        )
        record.stageId = speakerId == nil ? nil : "stage-preview"
        record.speakerKind = speakerId == nil ? nil : MessageSpeakerKind.participant.rawValue
        record.speakerId = speakerId
        record.speakerName = speakerName
        return MessageDisplayItem(record: record)
    }
}
