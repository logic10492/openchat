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
                ChatNavigationToolbar(
                    viewModel: viewModel,
                    isShowingSettings: $isShowingSettings,
                    isShowingCharacterPicker: $isShowingCharacterPicker,
                    selectedCharacterPickerWorldBookID: $selectedCharacterPickerWorldBookID
                )
            }
            .task {
                await viewModel.loadMessages()
                await viewModel.loadSettingsOptions()
            }
            .toolbarBackground(.hidden, for: .navigationBar)
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
            ChatEdgeEffectViewport {
                ChatTimelineHostView(
                    viewModel: viewModel,
                    onEdit: beginEditing
                )
            }
        }
            .chatInputBar {
                ChatInputBarHostView(viewModel: viewModel)
            }
    }

    // MARK: - Helpers

    private func beginEditing(_ item: MessageDisplayItem) {
        guard item.role == "user", !viewModel.isGenerating else { return }
        editedMessageText = item.content
        editingMessage = EditableMessage(id: item.id)
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
