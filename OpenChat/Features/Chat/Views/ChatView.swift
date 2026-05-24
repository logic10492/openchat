import SwiftUI

struct ChatView: View {
    @State private var viewModel: ChatViewModel
    @State private var isShowingSettings = false
    @State private var editingMessage: EditableMessage?
    @State private var editedMessageText = ""
    @State private var isShowingCharacterPicker = false
    @State private var selectedCharacterPickerWorldBookID: String?

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
        ZStack {
            ChatConversationBackground()
            messageList
        }
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
        ChatMessageTimelineView(
            messages: viewModel.messages,
            isGenerating: viewModel.isGenerating,
            showDetailedStats: viewModel.showDetailedStats,
            extractionPhase: viewModel.extractionPhase,
            backgroundDiagnostics: viewModel.backgroundDiagnostics,
            onEdit: { item in
                beginEditing(item)
            },
            onDelete: { id in
                Task { await viewModel.deleteMessage(id) }
            },
            onRegenerate: {
                Task { await viewModel.regenerateLastResponse() }
            },
            onDismissExtraction: {
                viewModel.dismissExtractionIndicator()
            }
        )
    }

    // MARK: - Helpers

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
