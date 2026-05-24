import SwiftUI

struct MessageBubbleView: View {
    let item: MessageDisplayItem
    var isStreaming = false
    var showDetailedStats = false
    var canEdit = true
    var isGroupedWithPrevious = false
    var isGroupedWithNext = false
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onRegenerate: () -> Void

    @State private var isHovering = false
    @State private var cursorVisible = false

    private var isUser: Bool { item.role == "user" }
    private var isSystem: Bool { item.role == "system" }
    private var maximumMessageWidth: CGFloat { isUser ? 590 : 680 }

    var body: some View {
        Group {
            if isSystem {
                systemMessage
            } else {
                messageRow
            }
        }
        .onHover { isHovering = $0 }
        .accessibilityIdentifier("messageBubble.\(item.role).\(item.speakerName ?? roleName)")
    }

    private var messageRow: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if isUser {
                Spacer(minLength: 54)
                messageCluster
                    .frame(maxWidth: maximumMessageWidth, alignment: .trailing)
            } else {
                messageCluster
                    .frame(maxWidth: maximumMessageWidth, alignment: .leading)
                Spacer(minLength: 54)
            }
        }
        .padding(.vertical, isGroupedWithPrevious || isGroupedWithNext ? 0 : 1)
    }

    private var messageCluster: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 3) {
            if shouldShowSpeakerName {
                Text(roleName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, OpenChatDesignSystem.Spacing.sm)
                    .accessibilityIdentifier("messageBubble.speaker.\(roleName)")
            }

            contentBubble

            if !isUser {
                assistantActionBar
                statsBar
            }
        }
    }

    private var contentBubble: some View {
        Group {
            if isUser {
                VStack(alignment: .trailing, spacing: OpenChatDesignSystem.Spacing.xxs) {
                    Text(item.content)
                        .font(OpenChatDesignSystem.Typography.body)
                        .foregroundStyle(.white)
                        .textSelection(.enabled)
                    bubbleFooter
                }
                .contextMenu {
                    Button {
                        onEdit()
                    } label: {
                        Label(String(localized: "Edit"), systemImage: "pencil")
                    }
                    .disabled(!canEdit)

                    Button {
                        UIPasteboard.general.string = item.content
                    } label: {
                        Label(String(localized: "Copy"), systemImage: "doc.on.doc")
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: OpenChatDesignSystem.Spacing.xs) {
                    reasoningSection
                    HStack(alignment: .bottom, spacing: 0) {
                        MarkdownTextView(blocks: item.contentBlocks, fillsAvailableWidth: false)
                        if isStreaming {
                            streamingCursor
                        }
                    }
                    bubbleFooter
                }
                .contextMenu {
                    Button {
                        UIPasteboard.general.string = item.content
                    } label: {
                        Label(String(localized: "Copy"), systemImage: "doc.on.doc")
                    }

                    Button {
                        onRegenerate()
                    } label: {
                        Label(String(localized: "Regenerate"), systemImage: "arrow.clockwise")
                    }
                    .disabled(isStreaming)

                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label(String(localized: "Delete"), systemImage: "trash")
                    }
                    .disabled(isStreaming)
                }
            }
        }
        .padding(.horizontal, isUser ? OpenChatDesignSystem.Spacing.sm : OpenChatDesignSystem.Spacing.md)
        .padding(.vertical, 7)
        .background {
            UnevenRoundedRectangle(cornerRadii: bubbleCorners, style: .continuous)
                .fill(bubbleFill)
        }
        .overlay {
            UnevenRoundedRectangle(cornerRadii: bubbleCorners, style: .continuous)
                .stroke(bubbleStroke, lineWidth: isUser ? 0 : 0.5)
        }
        .shadow(
            color: Color.black.opacity(isUser ? 0.05 : 0.035),
            radius: isGroupedWithPrevious || isGroupedWithNext ? 1 : 3,
            x: 0,
            y: 1
        )
    }

    private var systemMessage: some View {
        SystemMessageBubble(
            content: item.content,
            copyContent: item.originalContent ?? item.content
        )
    }

    @ViewBuilder
    private var bubbleFooter: some View {
        if !isGroupedWithNext {
            MessageTimestampFooter(
                date: item.createdAt,
                isStreaming: isStreaming,
                isOutgoing: isUser
            )
        }
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
            return String(localized: "Assistant")
        default:
            return String(localized: "System")
        }
    }

    private var shouldShowSpeakerName: Bool {
        !isUser && !isGroupedWithPrevious && item.speakerName != nil
    }

    private var bubbleCorners: RectangleCornerRadii {
        let wide: CGFloat = 18
        let grouped: CGFloat = 7
        let tail: CGFloat = 5
        if isUser {
            return RectangleCornerRadii(
                topLeading: wide,
                bottomLeading: wide,
                bottomTrailing: isGroupedWithNext ? grouped : tail,
                topTrailing: isGroupedWithPrevious ? grouped : wide
            )
        }
        return RectangleCornerRadii(
            topLeading: isGroupedWithPrevious ? grouped : wide,
            bottomLeading: isGroupedWithNext ? grouped : tail,
            bottomTrailing: wide,
            topTrailing: wide
        )
    }

    private var bubbleFill: Color {
        if isUser {
            return Color.accentColor
        }
        return Color(.secondarySystemGroupedBackground)
    }

    private var bubbleStroke: Color {
        Color(.separator).opacity(0.10)
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

    private var cursorOpacity: Double { cursorVisible ? 1.0 : 0.0 }

    // MARK: - Action Bar

    @ViewBuilder
    private var assistantActionBar: some View {
        if !isStreaming && !isGroupedWithNext && isHovering {
            MessageActionBar(
                content: item.content,
                showsRegenerate: item.role == "assistant",
                onRegenerate: onRegenerate,
                onDelete: onDelete
            )
            .padding(.leading, OpenChatDesignSystem.Spacing.xs)
        }
    }

    // MARK: - Stats Bar

    @ViewBuilder
    private var statsBar: some View {
        if !isStreaming, !isGroupedWithNext, let stats = item.streamingStats {
            StatsBarView(stats: stats, showDetailed: showDetailedStats)
                .padding(.leading, OpenChatDesignSystem.Spacing.xs)
        }
    }
}
