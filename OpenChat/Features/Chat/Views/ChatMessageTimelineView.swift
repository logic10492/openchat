import SwiftUI

struct ChatMessageTimelineView: View {
    let messages: [MessageDisplayItem]
    let isGenerating: Bool
    let showDetailedStats: Bool
    let extractionPhase: MemoryExtractionPhase
    let backgroundDiagnostics: BackgroundDiagnostics?
    let onEdit: (MessageDisplayItem) -> Void
    let onDelete: (String) -> Void
    let onRegenerate: () -> Void
    let onDismissExtraction: () -> Void

    @State private var shouldFollowStreaming = true
    @State private var followResumeGeneration = 0
    @State private var resumeFollowTask: Task<Void, Never>?
    @GestureState private var isTouchingMessageList = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if messages.isEmpty && !isGenerating {
                    ChatEmptyConversationView()
                } else {
                    timelineStack
                }
            }
            .openChatScrollEdgeEffects()
            .simultaneousGesture(scrollPauseGesture)
            .onChange(of: messages.map(\.id)) { oldIDs, newIDs in
                guard newIDs.count > oldIDs.count, let lastID = newIDs.last else { return }
                if isGenerating {
                    guard shouldFollowStreaming else { return }
                    proxy.scrollTo(lastID, anchor: .bottom)
                } else if oldIDs.isEmpty || messages.last?.role == "user" {
                    proxy.scrollTo(lastID, anchor: .bottom)
                }
            }
            .onChange(of: isGenerating) { _, isGenerating in
                if isGenerating {
                    shouldFollowStreaming = true
                    guard let lastID = messages.last?.id else { return }
                    proxy.scrollTo(lastID, anchor: .bottom)
                } else {
                    shouldFollowStreaming = false
                    cancelFollowResume()
                }
            }
            .onChange(of: latestStreamingRevision) { _, _ in
                guard isGenerating, shouldFollowStreaming, let last = messages.last else { return }
                proxy.scrollTo(last.id, anchor: .bottom)
            }
            .onChange(of: followResumeGeneration) { _, _ in
                guard isGenerating, shouldFollowStreaming, let last = messages.last else { return }
                proxy.scrollTo(last.id, anchor: .bottom)
            }
            .onChange(of: isTouchingMessageList) { _, isTouching in
                if isTouching {
                    cancelFollowResume()
                } else if isGenerating {
                    scheduleFollowResume()
                }
            }
            .onDisappear {
                cancelFollowResume()
            }
        }
    }

    private var timelineStack: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(messages.enumerated()), id: \.element.id) { index, item in
                if shouldShowDateSeparator(at: index) {
                    ChatDateSeparator(date: item.createdAt)
                        .id("date-separator-\(item.id)")
                        .padding(.top, index == 0 ? OpenChatDesignSystem.Spacing.sm : OpenChatDesignSystem.Spacing.lg)
                        .padding(.bottom, OpenChatDesignSystem.Spacing.sm)
                }

                MessageBubbleView(
                    item: item,
                    isStreaming: isStreamingMessage(item),
                    showDetailedStats: showDetailedStats,
                    canEdit: !isGenerating,
                    isGroupedWithPrevious: isGroupedWithPrevious(at: index),
                    isGroupedWithNext: isGroupedWithNext(at: index),
                    onEdit: {
                        onEdit(item)
                    },
                    onDelete: {
                        onDelete(item.id)
                    },
                    onRegenerate: onRegenerate
                )
                .id(item.id)
                .padding(.top, rowTopPadding(at: index))
                .accessibilityIdentifier("chat.message.\(item.role).\(item.id)")
            }

            if extractionPhase.isActive {
                MemoryExtractionIndicator(
                    phase: extractionPhase,
                    onDismiss: {
                        withAnimation(.easeOut(duration: 0.3)) {
                            onDismissExtraction()
                        }
                    }
                )
                .id("extraction-indicator")
            }

            if showDetailedStats, let backgroundDiagnostics {
                RetrievalTraceView(diagnostics: backgroundDiagnostics)
                    .id("retrieval-trace")
            }
        }
        .frame(maxWidth: 920)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, OpenChatDesignSystem.Spacing.sm)
        .padding(.top, OpenChatDesignSystem.Spacing.sm)
        .padding(.bottom, OpenChatDesignSystem.Spacing.lg)
    }

    private func isStreamingMessage(_ item: MessageDisplayItem) -> Bool {
        isGenerating && item.id == messages.last?.id && item.role == "assistant"
    }

    private var latestStreamingRevision: Int {
        guard isGenerating, let last = messages.last, last.role == "assistant" else {
            return -1
        }
        return last.contentRenderRevision
    }

    private func shouldShowDateSeparator(at index: Int) -> Bool {
        guard messages.indices.contains(index) else { return false }
        guard index > 0 else { return true }
        return !Calendar.current.isDate(messages[index].createdAt, inSameDayAs: messages[index - 1].createdAt)
    }

    private func isGroupedWithPrevious(at index: Int) -> Bool {
        guard messages.indices.contains(index), index > 0 else { return false }
        return shouldGroup(messages[index], with: messages[index - 1])
    }

    private func isGroupedWithNext(at index: Int) -> Bool {
        guard messages.indices.contains(index), messages.indices.contains(index + 1) else { return false }
        return shouldGroup(messages[index], with: messages[index + 1])
    }

    private func rowTopPadding(at index: Int) -> CGFloat {
        isGroupedWithPrevious(at: index) ? 2 : 7
    }

    private func shouldGroup(_ lhs: MessageDisplayItem, with rhs: MessageDisplayItem) -> Bool {
        guard lhs.role == rhs.role,
              lhs.speakerId == rhs.speakerId,
              lhs.speakerName == rhs.speakerName,
              Calendar.current.isDate(lhs.createdAt, inSameDayAs: rhs.createdAt)
        else { return false }
        return abs(lhs.createdAt.timeIntervalSince(rhs.createdAt)) < 5 * 60
    }

    private var scrollPauseGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .updating($isTouchingMessageList) { _, state, _ in
                state = true
            }
            .onChanged { _ in
                if isGenerating {
                    shouldFollowStreaming = false
                }
            }
            .onEnded { _ in
                if isGenerating {
                    scheduleFollowResume()
                }
            }
    }

    private func cancelFollowResume() {
        resumeFollowTask?.cancel()
        resumeFollowTask = nil
    }

    private func scheduleFollowResume() {
        guard isGenerating else {
            cancelFollowResume()
            return
        }
        cancelFollowResume()
        resumeFollowTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard isGenerating else {
                    resumeFollowTask = nil
                    return
                }
                shouldFollowStreaming = true
                followResumeGeneration &+= 1
                resumeFollowTask = nil
            }
        }
    }
}

private struct ChatEmptyConversationView: View {
    var body: some View {
        VStack(spacing: OpenChatDesignSystem.Spacing.md) {
            Spacer()
            VStack(spacing: OpenChatDesignSystem.Spacing.sm) {
                Image(systemName: "bubble.left.and.text.bubble.right")
                    .font(.system(size: 42, weight: .light))
                    .foregroundStyle(.secondary)
                Text(String(localized: "Send a message to start the conversation."))
                    .font(OpenChatDesignSystem.Typography.secondary)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 360)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 80)
        .accessibilityIdentifier("chat.emptyState")
    }
}

#Preview("Telegram Stage Timeline") {
    ZStack {
        ChatConversationBackground()
        ChatMessageTimelineView(
            messages: MessageDisplayItem.stagePreviewMessages(),
            isGenerating: false,
            showDetailedStats: false,
            extractionPhase: .idle,
            backgroundDiagnostics: nil,
            onEdit: { _ in },
            onDelete: { _ in },
            onRegenerate: {},
            onDismissExtraction: {}
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
