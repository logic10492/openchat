import SwiftUI

struct MessageBubbleView: View {
    let item: MessageDisplayItem
    var isStreaming = false
    var characterName: String?
    var showDetailedStats = false
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
                    statsBar
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
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(.white.opacity(0.15), lineWidth: 0.5)
                            .blendMode(.overlay)
                    )
                    .shadowElevation1()
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    reasoningSection
                    HStack(spacing: 0) {
                        MarkdownTextView(text: item.content)
                        if isStreaming {
                            streamingCursor
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .textSelection(.enabled)
    }

    // MARK: - Reasoning Section

    @State private var isReasoningExpanded = false

    @ViewBuilder
    private var reasoningSection: some View {
        if let reasoning = item.reasoningContent, !reasoning.isEmpty {
            DisclosureGroup(isExpanded: $isReasoningExpanded) {
                Text(reasoning)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            } label: {
                Label {
                    Text(String(localized: "Thinking"))
                    if isStreaming && item.content.isEmpty {
                        ProgressView()
                            .controlSize(.mini)
                            .padding(.leading, 4)
                    }
                } icon: {
                    Image(systemName: "brain")
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.purple)
            }
            .padding(8)
            .background(Color.purple.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else if isStreaming && item.content.isEmpty {
            // Streaming hasn't produced content yet — may be in reasoning phase
            HStack(spacing: 6) {
                Image(systemName: "brain")
                Text(String(localized: "Thinking…"))
                ProgressView()
                    .controlSize(.mini)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.purple)
            .padding(8)
            .background(Color.purple.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
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

    // MARK: - Stats Bar

    @ViewBuilder
    private var statsBar: some View {
        if !isStreaming, let stats = item.streamingStats {
            StatsBarView(stats: stats, showDetailed: showDetailedStats)
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
