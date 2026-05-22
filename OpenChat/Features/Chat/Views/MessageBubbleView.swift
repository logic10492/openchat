import SwiftUI

struct MessageBubbleView: View {
    let item: MessageDisplayItem
    var isStreaming = false
    var showDetailedStats = false
    var canEdit = true
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onRegenerate: () -> Void
    @State private var isHovering = false

    private var isUser: Bool { item.role == "user" }
    private var maximumMessageWidth: CGFloat { isUser ? 520 : 680 }
    private var horizontalSpacerWidth: CGFloat { isUser ? 64 : 48 }

    var body: some View {
        HStack(alignment: .bottom, spacing: OpenChatDesignSystem.Spacing.sm) {
            if isUser {
                Spacer(minLength: horizontalSpacerWidth)
                contentView
                    .frame(maxWidth: maximumMessageWidth, alignment: .trailing)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    contentView
                    assistantActionBar
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

    // MARK: - Content

    private var contentView: some View {
        Group {
            if item.role == "user" {
                Text(item.content)
                    .font(OpenChatDesignSystem.Typography.body)
                    .foregroundStyle(.white)
                    .padding(.horizontal, OpenChatDesignSystem.Spacing.md)
                    .padding(.vertical, OpenChatDesignSystem.Spacing.sm)
                    .textSelection(.enabled)
                    .background(
                        RoundedRectangle(cornerRadius: OpenChatDesignSystem.Radius.xl, style: .continuous)
                            .fill(Color.accentColor)
                    )
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
                        MarkdownTextView(blocks: item.contentBlocks)
                        if isStreaming {
                            streamingCursor
                        }
                    }
                }
                .padding(.horizontal, OpenChatDesignSystem.Spacing.md)
                .padding(.vertical, OpenChatDesignSystem.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: OpenChatDesignSystem.Radius.xl, style: .continuous)
                        .fill(assistantBubbleColor)
                )
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
    }

    private var assistantBubbleColor: Color {
        switch item.role {
        case "assistant":
            return Color(.secondarySystemGroupedBackground)
        default:
            return OpenChatDesignSystem.Surface.warningWash
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
    private var assistantActionBar: some View {
        if !isStreaming {
            MessageActionBar(
                content: item.content,
                showsRegenerate: item.role == "assistant",
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
        onEdit: {},
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
        onEdit: {},
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
        onEdit: {},
        onDelete: {},
        onRegenerate: {}
    )
    .padding()
}
