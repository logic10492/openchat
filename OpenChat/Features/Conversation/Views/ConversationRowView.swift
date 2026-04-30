import SwiftUI

struct ConversationRowView: View {
    let conversation: ConversationRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(conversation.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Spacer()
                if conversation.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }

            Text(conversation.updatedAt.openChatRelativeTimestamp())
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    List {
        ConversationRowView(
            conversation: ConversationRecord(
                id: "1",
                title: "Sample Chat",
                characterCardId: nil,
                apiEndpointId: nil,
                modelName: nil,
                contextStrategy: "truncation",
                compressionMode: "standard",
                customScenario: nil,
                modelParameters: nil,
                slowPlotMode: true,
                isTitleGenerated: false,
                isPinned: false,
                createdAt: .now,
                updatedAt: .now
            )
        )
        ConversationRowView(
            conversation: ConversationRecord(
                id: "2",
                title: "Pinned Chat with a very long title that should truncate",
                characterCardId: nil,
                apiEndpointId: nil,
                modelName: nil,
                contextStrategy: "truncation",
                compressionMode: "standard",
                customScenario: nil,
                modelParameters: nil,
                slowPlotMode: true,
                isTitleGenerated: false,
                isPinned: true,
                createdAt: .now,
                updatedAt: .now.addingTimeInterval(-3600)
            )
        )
    }
    .listStyle(.plain)
}
