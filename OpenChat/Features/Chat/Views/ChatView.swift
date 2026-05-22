import SwiftUI

struct ChatView: View {
    @State private var viewModel: ChatViewModel
    @State private var isShowingSettings = false
    @State private var isShowingRename = false
    @State private var renameText = ""
    @State private var shouldFollowStreaming = true
    @State private var followResumeGeneration = 0
    @State private var resumeFollowTask: Task<Void, Never>?
    @GestureState private var isTouchingMessageList = false

    init(viewModel: ChatViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        messageList
            .safeAreaInset(edge: .bottom, spacing: 0) {
                InputBarView(
                    text: binding(\.inputText),
                    inputRole: binding(\.stageInputRole),
                    responderIds: binding(\.stageResponderIds),
                    stageParticipants: viewModel.stageParticipants,
                    showsDirectorTools: viewModel.isStageEnabled,
                    isGenerating: viewModel.isGenerating,
                    onSend: {
                        Task { await viewModel.sendMessage() }
                    },
                    onStop: {
                        viewModel.stopGenerating()
                    },
                    onCustomizeResponders: {
                        viewModel.markStageResponderSelectionCustomized()
                    }
                )
                .padding(.bottom, 8)
            }
            .background(OpenChatDesignSystem.Surface.pageBackground)
            .navigationTitle(viewModel.conversation.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button {
                        renameText = viewModel.conversation.title
                        isShowingRename = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                if viewModel.isGeneratingTitle {
                    ProgressView()
                        .controlSize(.small)
                }
                if let tokenUsage = viewModel.tokenUsage {
                    Text("\(tokenUsage.totalUsed)/\(tokenUsage.totalBudget)")
                        .font(OpenChatDesignSystem.Typography.monoMetadata)
                        .foregroundStyle(.secondary)
                }
                Button {
                    isShowingSettings = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel(String(localized: "Chat Settings"))
                .accessibilityIdentifier("chat.settingsButton")
            }
        }
        .task {
            await viewModel.loadMessages()
            await viewModel.loadSettingsOptions()
        }
        .onDisappear {
            viewModel.triggerMemoryExtraction()
        }
        .sheet(isPresented: $isShowingSettings) {
            ChatSettingsSheet(viewModel: viewModel)
                .presentationDetents([.medium, .large])
        }
        .alert(String(localized: "Rename Conversation"), isPresented: $isShowingRename) {
            TextField(String(localized: "Title"), text: $renameText)
            Button(String(localized: "Cancel"), role: .cancel) {}
            Button(String(localized: "Save")) {
                Task { await viewModel.renameConversation(newTitle: renameText) }
            }
        }
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if viewModel.messages.isEmpty && !viewModel.isGenerating {
                    chatEmptyState
                } else {
                    LazyVStack(spacing: OpenChatDesignSystem.Spacing.lg) {
                        ForEach(viewModel.messages) { item in
                            MessageBubbleView(
                                item: item,
                                isStreaming: isStreamingMessage(item),
                                characterName: item.speakerName ?? viewModel.activeStageSpeakerName ?? viewModel.selectedCharacterName,
                                showDetailedStats: viewModel.showDetailedStats,
                                onDelete: {
                                    Task { await viewModel.deleteMessage(item.id) }
                                },
                                onRegenerate: {
                                    Task { await viewModel.regenerateLastResponse() }
                                }
                            )
                            .id(item.id)
                            .accessibilityIdentifier("chat.message.\(item.role).\(item.id)")
                        }

                        if viewModel.extractionPhase.isActive {
                            MemoryExtractionIndicator(
                                phase: viewModel.extractionPhase,
                                onDismiss: {
                                    withAnimation(.easeOut(duration: 0.3)) {
                                        viewModel.dismissExtractionIndicator()
                                    }
                                }
                            )
                            .id("extraction-indicator")
                        }

                        if viewModel.showDetailedStats, let diagnostics = viewModel.backgroundDiagnostics {
                            RetrievalTraceView(diagnostics: diagnostics)
                                .id("retrieval-trace")
                        }
                    }
                    .padding(.horizontal, OpenChatDesignSystem.Spacing.md)
                    .padding(.top, OpenChatDesignSystem.Spacing.md)
                    .padding(.bottom, OpenChatDesignSystem.Spacing.lg)
                }
            }
            .simultaneousGesture(scrollPauseGesture)
            .onChange(of: viewModel.messages.map(\.id)) { oldIDs, newIDs in
                guard newIDs.count > oldIDs.count, let lastID = newIDs.last else { return }
                if viewModel.isGenerating {
                    guard shouldFollowStreaming else { return }
                    proxy.scrollTo(lastID, anchor: .bottom)
                } else if oldIDs.isEmpty || viewModel.messages.last?.role == "user" {
                    proxy.scrollTo(lastID, anchor: .bottom)
                }
            }
            .onChange(of: viewModel.isGenerating) { _, isGenerating in
                if isGenerating {
                    shouldFollowStreaming = true
                    guard let lastID = viewModel.messages.last?.id else { return }
                    proxy.scrollTo(lastID, anchor: .bottom)
                } else {
                    shouldFollowStreaming = false
                    cancelFollowResume()
                }
            }
            .onChange(of: latestStreamingRevision) { _, _ in
                guard viewModel.isGenerating, shouldFollowStreaming, let last = viewModel.messages.last else { return }
                proxy.scrollTo(last.id, anchor: .bottom)
            }
            .onChange(of: followResumeGeneration) { _, _ in
                guard viewModel.isGenerating, shouldFollowStreaming, let last = viewModel.messages.last else { return }
                proxy.scrollTo(last.id, anchor: .bottom)
            }
            .onChange(of: isTouchingMessageList) { _, isTouching in
                if isTouching {
                    cancelFollowResume()
                } else if viewModel.isGenerating {
                    scheduleFollowResume()
                }
            }
            .onDisappear {
                cancelFollowResume()
            }
        }
    }

    // MARK: - Empty State

    private var chatEmptyState: some View {
        VStack(spacing: OpenChatDesignSystem.Spacing.sm) {
            Spacer()
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.tertiary)
            Text(String(localized: "Send a message to start the conversation."))
                .font(OpenChatDesignSystem.Typography.secondary)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 80)
        .accessibilityIdentifier("chat.emptyState")
    }

    // MARK: - Helpers

    private func isStreamingMessage(_ item: MessageDisplayItem) -> Bool {
        viewModel.isGenerating && item.id == viewModel.messages.last?.id && item.role == "assistant"
    }

    private var latestStreamingRevision: Int {
        guard viewModel.isGenerating, let last = viewModel.messages.last, last.role == "assistant" else {
            return -1
        }
        return last.contentRenderRevision
    }

    private var scrollPauseGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .updating($isTouchingMessageList) { _, state, _ in
                state = true
            }
            .onChanged { _ in
                if viewModel.isGenerating {
                    shouldFollowStreaming = false
                }
            }
            .onEnded { _ in
                if viewModel.isGenerating {
                    scheduleFollowResume()
                }
            }
    }

    private func cancelFollowResume() {
        resumeFollowTask?.cancel()
        resumeFollowTask = nil
    }

    private func scheduleFollowResume() {
        guard viewModel.isGenerating else {
            cancelFollowResume()
            return
        }
        cancelFollowResume()
        resumeFollowTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard viewModel.isGenerating else {
                    resumeFollowTask = nil
                    return
                }
                shouldFollowStreaming = true
                followResumeGeneration &+= 1
                resumeFollowTask = nil
            }
        }
    }

    private func binding<Value>(_ keyPath: ReferenceWritableKeyPath<ChatViewModel, Value>) -> Binding<Value> {
        @Bindable var viewModel = viewModel
        return Binding(
            get: { viewModel[keyPath: keyPath] },
            set: { viewModel[keyPath: keyPath] = $0 }
        )
    }
}

#Preview {
    NavigationStack {
        ChatView(
            viewModel: ChatViewModel(
                conversation: ConversationRecord(
                    id: "preview",
                    title: "Preview Chat",
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
                    lastExtractedSortOrder: nil,
                    createdAt: .now,
                    updatedAt: .now
                ),
                databaseManager: DependencyContainer.preview().databaseManager,
                apiClient: DependencyContainer.preview().apiClient,
                contextManager: DependencyContainer.preview().contextManager,
                memoryManager: DependencyContainer.preview().memoryManager,
                memoryReflectBackgroundWorker: DependencyContainer.preview().memoryReflectBackgroundWorker,
                worldBookEmbeddingIndexer: DependencyContainer.preview().worldBookEmbeddingIndexer,
                worldBookSource: DependencyContainer.preview().worldBookSource,
                backgroundManager: DependencyContainer.preview().backgroundManager,
                titleGenerator: DependencyContainer.preview().titleGenerator,
                appState: AppState()
            )
        )
    }
}
