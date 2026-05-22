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
    private var maximumMessageWidth: CGFloat { isUser ? 520 : 680 }
    private var horizontalSpacerWidth: CGFloat { isUser ? 56 : 32 }

    var body: some View {
        HStack(alignment: .top, spacing: OpenChatDesignSystem.Spacing.sm) {
            if isUser {
                Spacer(minLength: horizontalSpacerWidth)
                VStack(alignment: .trailing, spacing: 6) {
                    roleLabel
                    contentView
                    actionBar
                }
                .frame(maxWidth: maximumMessageWidth, alignment: .trailing)
                avatarView
            } else {
                avatarView
                VStack(alignment: .leading, spacing: 6) {
                    roleLabel
                    contentView
                    actionBar
                    statsBar
                }
                .frame(maxWidth: maximumMessageWidth, alignment: .leading)
                Spacer(minLength: horizontalSpacerWidth)
            }
        }
        .padding(.vertical, OpenChatDesignSystem.Spacing.xxs)
        .onHover { isHovering = $0 }
        .accessibilityIdentifier("messageBubble.\(item.role).\(item.speakerName ?? roleName)")
    }

    // MARK: - Avatar

    private var avatarView: some View {
        Circle()
            .fill(avatarBackground)
            .frame(width: OpenChatDesignSystem.IconSize.avatar, height: OpenChatDesignSystem.IconSize.avatar)
            .overlay {
                Image(systemName: avatarIcon)
                    .font(.system(size: OpenChatDesignSystem.IconSize.xs, weight: .medium))
                    .foregroundStyle(avatarForeground)
            }
            .overlay(
                Circle()
                    .stroke(avatarForeground.opacity(0.16), lineWidth: 0.5)
            )
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
        case "user": OpenChatDesignSystem.Surface.subtleFill
        case "assistant": OpenChatDesignSystem.Surface.accentSoft
        default: OpenChatDesignSystem.Surface.warningWash
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
            .font(OpenChatDesignSystem.Typography.sectionTitle)
    }

    private var roleName: String {
        if let speakerName = item.speakerName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !speakerName.isEmpty {
            return speakerName
        }

        switch item.role {
        case "user":
            return String(localized: "You")
        case "assistant":
            return characterName ?? String(localized: "Assistant")
        default:
            return String(localized: "System")
        }
    }

    // MARK: - Content

    private var contentView: some View {
        Group {
            if item.role == "user" {
                Text(item.content)
                    .padding(14)
                    .textSelection(.enabled)
                    .background(
                        RoundedRectangle(cornerRadius: OpenChatDesignSystem.Radius.xl, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: OpenChatDesignSystem.Radius.xl, style: .continuous)
                            .stroke(OpenChatDesignSystem.Surface.hairline, lineWidth: 0.5)
                            .blendMode(.overlay)
                    )
                    .shadowElevation1()
            } else {
                VStack(alignment: .leading, spacing: OpenChatDesignSystem.Spacing.xs) {
                    reasoningSection
                    HStack(alignment: .bottom, spacing: 0) {
                        MarkdownTextView(blocks: item.contentBlocks)
                        if isStreaming {
                            streamingCursor
                        }
                    }
                }
                .padding(.vertical, OpenChatDesignSystem.Spacing.xxs)
            }
        }
    }

    // MARK: - Reasoning Section

    @ViewBuilder
    private var reasoningSection: some View {
        if let reasoning = item.reasoningContent, !reasoning.isEmpty {
            ReasoningDisclosureView(
                reasoning: reasoning,
                isStreaming: isStreaming && item.content.isEmpty
            )
        } else if isStreaming && item.content.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "brain")
                Text(String(localized: "Character thinking…"))
                ProgressView()
                    .controlSize(.mini)
            }
            .font(OpenChatDesignSystem.Typography.badge)
            .foregroundStyle(.purple)
            .padding(OpenChatDesignSystem.Spacing.xs)
            .background(
                OpenChatDesignSystem.Surface.reasoningWash,
                in: RoundedRectangle(cornerRadius: OpenChatDesignSystem.Radius.xs, style: .continuous)
            )
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
                createdAt: .now,
                reasoningContent: nil
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
                createdAt: .now,
                reasoningContent: nil
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
                createdAt: .now,
                reasoningContent: nil
            )
        ),
        isStreaming: true,
        onDelete: {},
        onRegenerate: {}
    )
    .padding()
}
