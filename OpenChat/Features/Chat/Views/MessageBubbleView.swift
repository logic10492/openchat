import SwiftUI

struct MessageBubbleView: View {
    let item: MessageDisplayItem
    var isStreaming = false
    var characterName: String?
    let onDelete: () -> Void
    let onRegenerate: () -> Void
    @State private var isHovering = false

    private var isUser: Bool { item.role == "user" }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if isUser {
                Spacer(minLength: 48)
                VStack(alignment: .trailing, spacing: 6) {
                    roleLabel
                    contentView
                    actionBar
                }
                avatarView
            } else {
                avatarView
                VStack(alignment: .leading, spacing: 6) {
                    roleLabel
                    contentView
                    actionBar
                }
                Spacer(minLength: 48)
            }
        }
        .padding(.vertical, 4)
        .onHover { isHovering = $0 }
    }

    // MARK: - Avatar

    private var avatarView: some View {
        Circle()
            .fill(avatarBackground)
            .frame(width: 32, height: 32)
            .overlay {
                Image(systemName: avatarIcon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(avatarForeground)
            }
    }

    private var avatarIcon: String {
        switch item.role {
        case "user": "person.fill"
        case "assistant": "sparkle"
        default: "info.circle.fill"
        }
    }

    private var avatarBackground: Color {
        switch item.role {
        case "user": Color(.systemGray5)
        case "assistant": Color.accentColor.opacity(0.15)
        default: Color.orange.opacity(0.15)
        }
    }

    private var avatarForeground: Color {
        switch item.role {
        case "user": Color(.label)
        case "assistant": Color.accentColor
        default: Color.orange
        }
    }

    // MARK: - Role Label

    private var roleLabel: some View {
        Text(roleName)
            .font(.subheadline.weight(.semibold))
    }

    private var roleName: String {
        switch item.role {
        case "user": String(localized: "You")
        case "assistant": characterName ?? String(localized: "Assistant")
        default: String(localized: "System")
        }
    }

    // MARK: - Content

    private var contentView: some View {
        Group {
            if item.role == "user" {
                Text(item.content)
                    .padding(12)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                HStack(spacing: 0) {
                    MarkdownTextView(text: item.content)
                    if isStreaming {
                        streamingCursor
                    }
                }
            }
        }
        .textSelection(.enabled)
    }

    private var streamingCursor: some View {
        Text("▍")
            .foregroundStyle(.primary)
            .opacity(cursorOpacity)
            .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: cursorOpacity)
            .onAppear { cursorVisible = true }
    }

    @State private var cursorVisible = false
    private var cursorOpacity: Double { cursorVisible ? 1.0 : 0.0 }

    // MARK: - Action Bar

    @ViewBuilder
    private var actionBar: some View {
        if !isStreaming {
            MessageActionBar(
                role: item.role,
                content: item.content,
                onRegenerate: onRegenerate,
                onDelete: onDelete
            )
            .opacity(isHovering ? 1 : 0.5)
        }
    }
}

#Preview("User Message") {
    MessageBubbleView(
        item: MessageDisplayItem(
            record: MessageRecord(
                id: "1",
                conversationId: "c1",
                role: "user",
                content: "Tell me about the history of ancient Rome.",
                tokenCount: 10,
                isCompressed: false,
                originalContent: nil,
                sortOrder: 0,
                createdAt: .now
            )
        ),
        onDelete: {},
        onRegenerate: {}
    )
    .padding()
}

#Preview("Assistant Message") {
    MessageBubbleView(
        item: MessageDisplayItem(
            record: MessageRecord(
                id: "2",
                conversationId: "c1",
                role: "assistant",
                content: "Ancient Rome was one of the **most powerful** civilizations in history. It began as a small settlement along the banks of the *Tiber River*.",
                tokenCount: 30,
                isCompressed: false,
                originalContent: nil,
                sortOrder: 1,
                createdAt: .now
            )
        ),
        onDelete: {},
        onRegenerate: {}
    )
    .padding()
}

#Preview("Streaming") {
    MessageBubbleView(
        item: MessageDisplayItem(
            record: MessageRecord(
                id: "3",
                conversationId: "c1",
                role: "assistant",
                content: "Generating response...",
                tokenCount: nil,
                isCompressed: false,
                originalContent: nil,
                sortOrder: 2,
                createdAt: .now
            )
        ),
        isStreaming: true,
        onDelete: {},
        onRegenerate: {}
    )
    .padding()
}
