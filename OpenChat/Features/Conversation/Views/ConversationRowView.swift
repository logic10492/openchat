import SwiftUI

struct ConversationRowView: View {
    let conversation: ConversationRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(conversation.title)
                    .font(.headline)
                if conversation.isPinned {
                    Image(systemName: "pin.fill")
                        .foregroundStyle(.orange)
                }
            }

            Text(conversation.updatedAt.openChatRelativeTimestamp())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
