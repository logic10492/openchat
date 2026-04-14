import SwiftUI

struct MessageBubbleView: View {
    let item: MessageDisplayItem
    let onDelete: () -> Void
    let onRegenerate: () -> Void

    var body: some View {
        HStack {
            if item.role == "user" {
                Spacer(minLength: 48)
            }

            VStack(alignment: .leading, spacing: 8) {
                MarkdownTextView(text: item.content)
                Text(item.createdAt.openChatRelativeTimestamp())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(bubbleColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contextMenu {
                Button(String(localized: "Delete"), role: .destructive, action: onDelete)
                if item.role == "assistant" {
                    Button(String(localized: "Regenerate"), action: onRegenerate)
                }
            }

            if item.role != "user" {
                Spacer(minLength: 48)
            }
        }
    }

    private var bubbleColor: some ShapeStyle {
        switch item.role {
        case "user":
            Color.accentColor.opacity(0.2)
        case "assistant":
            Color(uiColor: .secondarySystemBackground)
        default:
            Color.orange.opacity(0.15)
        }
    }
}
