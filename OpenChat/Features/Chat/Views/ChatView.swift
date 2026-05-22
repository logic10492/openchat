import SwiftUI

struct ChatView: View {
    @State private var viewModel: ChatViewModel
    @State private var isShowingSettings = false
    @State private var editingMessage: EditableMessage?
    @State private var editedMessageText = ""
    @State private var shouldFollowStreaming = true
    @State private var followResumeGeneration = 0
    @State private var resumeFollowTask: Task<Void, Never>?
    @State private var isShowingCharacterPicker = false
    @State private var selectedCharacterPickerWorldBookID: String?
    @GestureState private var isTouchingMessageList = false

    init(viewModel: ChatViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        chatContent
            .background(OpenChatDesignSystem.Surface.pageBackground)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    characterCapsuleControl
                        .offset(y: 3)
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    if viewModel.isGeneratingTitle {
                        ProgressView()
                            .controlSize(.small)
                            .offset(y: 3)
                    }
                    Button {
                        isShowingSettings = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .offset(y: 3)
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
            .sheet(item: $editingMessage) { message in
                EditMessageSheet(
                    text: $editedMessageText,
                    onCancel: {
                        editingMessage = nil
                    },
                    onSave: {
                        let newContent = editedMessageText
                        editingMessage = nil
                        Task {
                            await viewModel.editMessage(message.id, newContent: newContent)
                        }
                    }
                )
                .presentationDetents([.medium])
            }
    }

    // MARK: - Layout

    private var chatContent: some View {
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
                .padding(.bottom, OpenChatDesignSystem.Spacing.xs)
            }
    }

    // MARK: - Character Capsule

    @ViewBuilder
    private var characterCapsuleControl: some View {
        if viewModel.showsConversationCharacterPicker {
            Button {
                presentCharacterPicker()
            } label: {
                ChatHeaderCapsule(
                    title: viewModel.selectedCharacterName ?? String(localized: "Select Character"),
                    subtitle: viewModel.selectedCharacterWorldBookName
                )
            }
            .buttonStyle(.plain)
            .popover(
                isPresented: $isShowingCharacterPicker,
                attachmentAnchor: .rect(.bounds),
                arrowEdge: .top
            ) {
                CharacterPickerPopover(
                    worldBooks: viewModel.availableWorldBooks,
                    characterCards: viewModel.availableCharacterCards,
                    selectedCharacterCardID: viewModel.selectedCharacterCardID,
                    selectedWorldBookID: $selectedCharacterPickerWorldBookID,
                    onSelectCharacterCard: { id in
                        selectCharacterCard(id)
                        isShowingCharacterPicker = false
                    }
                )
                .presentationCompactAdaptation(.popover)
            }
            .accessibilityLabel(String(localized: "Select Character"))
            .accessibilityIdentifier("chat.characterCapsule")
        } else {
            Button {
                isShowingSettings = true
            } label: {
                ChatHeaderCapsule(
                    title: String(localized: "Stage"),
                    subtitle: stageCapsuleSubtitle
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Stage"))
            .accessibilityIdentifier("chat.stageCapsule")
        }
    }

    private var selectedCharacterWorldBookID: String? {
        guard let id = viewModel.selectedCharacterCardID,
              let card = viewModel.availableCharacterCards.first(where: { $0.id == id }),
              let worldBookId = card.worldBookId,
              viewModel.availableWorldBooks.contains(where: { $0.id == worldBookId })
        else { return nil }
        return worldBookId
    }

    private var stageCapsuleSubtitle: String? {
        let names = viewModel.activeStageParticipants.map(\.displayName)
        guard !names.isEmpty else { return nil }
        return names.joined(separator: ", ")
    }

    private func presentCharacterPicker() {
        selectedCharacterPickerWorldBookID = selectedCharacterWorldBookID
        isShowingCharacterPicker = true
    }

    private func selectCharacterCard(_ id: String?) {
        guard viewModel.showsConversationCharacterPicker,
              viewModel.selectedCharacterCardID != id
        else { return }
        viewModel.selectedCharacterCardID = id
        Task { await viewModel.saveConversationSettings() }
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
                                showDetailedStats: viewModel.showDetailedStats,
                                canEdit: !viewModel.isGenerating,
                                onEdit: {
                                    beginEditing(item)
                                },
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
                    .frame(maxWidth: 860)
                    .frame(maxWidth: .infinity)
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
        VStack(spacing: OpenChatDesignSystem.Spacing.md) {
            Spacer()
            VStack(spacing: OpenChatDesignSystem.Spacing.sm) {
                Image(systemName: "bubble.left.and.text.bubble.right")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(.tertiary)
                Text(String(localized: "Send a message to start the conversation."))
                    .font(OpenChatDesignSystem.Typography.secondary)
                    .foregroundStyle(.secondary)
            }
            .openChatCardStyle()
            .frame(maxWidth: 360)
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

    private func beginEditing(_ item: MessageDisplayItem) {
        guard item.role == "user", !viewModel.isGenerating else { return }
        editedMessageText = item.content
        editingMessage = EditableMessage(id: item.id)
    }

    private func binding<Value>(_ keyPath: ReferenceWritableKeyPath<ChatViewModel, Value>) -> Binding<Value> {
        @Bindable var viewModel = viewModel
        return Binding(
            get: { viewModel[keyPath: keyPath] },
            set: { viewModel[keyPath: keyPath] = $0 }
        )
    }
}

private struct EditableMessage: Identifiable {
    let id: String
}

private struct CharacterPickerPopover: View {
    let worldBooks: [WorldBookRecord]
    let characterCards: [CharacterCardRecord]
    let selectedCharacterCardID: String?
    @Binding var selectedWorldBookID: String?
    let onSelectCharacterCard: (String?) -> Void

    private var filteredCharacterCards: [CharacterCardRecord] {
        characterCards.filter { card in
            if let selectedWorldBookID {
                return card.worldBookId == selectedWorldBookID
            }
            return card.worldBookId == nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OpenChatDesignSystem.Spacing.sm) {
            worldBookSection
            Divider()
            characterSection
        }
        .padding(OpenChatDesignSystem.Spacing.sm)
        .frame(width: 320, alignment: .leading)
    }

    private var worldBookSection: some View {
        VStack(alignment: .leading, spacing: OpenChatDesignSystem.Spacing.xs) {
            sectionHeader(String(localized: "Available World Books"))

            VStack(spacing: OpenChatDesignSystem.Spacing.xxs) {
                pickerRow(
                    title: String(localized: "No World Book"),
                    systemImage: "book.closed",
                    isSelected: selectedWorldBookID == nil
                ) {
                    selectedWorldBookID = nil
                }

                ForEach(worldBooks) { book in
                    pickerRow(
                        title: book.name,
                        systemImage: book.isEnabled ? "book" : "book.closed",
                        isSelected: selectedWorldBookID == book.id
                    ) {
                        selectedWorldBookID = book.id
                    }
                }
            }
        }
    }

    private var characterSection: some View {
        VStack(alignment: .leading, spacing: OpenChatDesignSystem.Spacing.xs) {
            sectionHeader(String(localized: "World Book Characters"))

            VStack(spacing: OpenChatDesignSystem.Spacing.xxs) {
                pickerRow(
                    title: String(localized: "None"),
                    systemImage: "person.slash",
                    isSelected: selectedCharacterCardID == nil
                ) {
                    onSelectCharacterCard(nil)
                }

                if filteredCharacterCards.isEmpty {
                    Text(String(localized: "No Characters"))
                        .font(OpenChatDesignSystem.Typography.secondary)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, OpenChatDesignSystem.Spacing.sm)
                        .padding(.vertical, OpenChatDesignSystem.Spacing.xs)
                } else {
                    ForEach(filteredCharacterCards) { card in
                        pickerRow(
                            title: card.name,
                            systemImage: "person",
                            isSelected: selectedCharacterCardID == card.id
                        ) {
                            onSelectCharacterCard(card.id)
                        }
                    }
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(OpenChatDesignSystem.Typography.badge)
            .foregroundStyle(.secondary)
            .padding(.horizontal, OpenChatDesignSystem.Spacing.sm)
    }

    private func pickerRow(
        title: String,
        systemImage: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: OpenChatDesignSystem.Spacing.sm) {
                Image(systemName: systemImage)
                    .font(.subheadline)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(width: OpenChatDesignSystem.IconSize.md)

                Text(title)
                    .font(OpenChatDesignSystem.Typography.rowTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: OpenChatDesignSystem.Spacing.sm)

                Image(systemName: "checkmark")
                    .font(OpenChatDesignSystem.Typography.badge)
                    .foregroundStyle(Color.accentColor)
                    .opacity(isSelected ? 1 : 0)
            }
            .padding(.horizontal, OpenChatDesignSystem.Spacing.sm)
            .padding(.vertical, OpenChatDesignSystem.Spacing.xs)
            .background(
                isSelected ? OpenChatDesignSystem.Surface.accentWash : Color.clear,
                in: RoundedRectangle(cornerRadius: OpenChatDesignSystem.Radius.xs, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: OpenChatDesignSystem.Radius.xs, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct ChatHeaderCapsule: View {
    let title: String
    let subtitle: String?

    var body: some View {
        capsuleContent
            .modifier(ChatHeaderGlassCapsuleStyle())
    }

    private var capsuleContent: some View {
        HStack(spacing: OpenChatDesignSystem.Spacing.sm) {
            VStack(spacing: 1) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(OpenChatDesignSystem.Typography.badge)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
    }
}

private struct ChatHeaderGlassCapsuleStyle: ViewModifier {
    func body(content: Content) -> some View {
        let capsule = Capsule()
        content
            .padding(.horizontal, OpenChatDesignSystem.Spacing.md)
            .padding(.vertical, OpenChatDesignSystem.Spacing.xs)
            .frame(minWidth: 156, maxWidth: 252, minHeight: 48)
            .background {
                if #available(iOS 26.0, *) {
                    Color.clear
                } else {
                    capsule.fill(.ultraThinMaterial)
                }
            }
            .overlay {
                if #available(iOS 26.0, *) {
                    EmptyView()
                } else {
                    capsule
                        .stroke(Color.white.opacity(0.22), lineWidth: 0.5)
                        .blendMode(.overlay)
                }
            }
            .ifAvailableGlassEffect(in: capsule)
            .shadow(color: Color.black.opacity(0.10), radius: 10, x: 0, y: 4)
            .contentShape(capsule)
    }
}

private extension View {
    @ViewBuilder
    func ifAvailableGlassEffect<S: Shape>(in shape: S) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: shape)
        } else {
            self
        }
    }
}

private struct EditMessageSheet: View {
    @Binding var text: String
    let onCancel: () -> Void
    let onSave: () -> Void

    private var canSave: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .font(OpenChatDesignSystem.Typography.body)
                .scrollContentBackground(.hidden)
                .padding(OpenChatDesignSystem.Spacing.md)
                .background(OpenChatDesignSystem.Surface.pageBackground)
                .navigationTitle(String(localized: "Edit Message"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "Cancel"), action: onCancel)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "Save"), action: onSave)
                            .disabled(!canSave)
                    }
                }
        }
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
