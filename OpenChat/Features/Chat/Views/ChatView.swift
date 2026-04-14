import SwiftUI

struct ChatView: View {
    @State private var viewModel: ChatViewModel
    @State private var isShowingSettings = false

    init(viewModel: ChatViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        VStack(spacing: 0) {
            messageList
            InputBarView(
                text: binding(\.inputText),
                isGenerating: viewModel.isGenerating,
                onSend: {
                    Task { await viewModel.sendMessage() }
                },
                onStop: {
                    viewModel.stopGenerating()
                }
            )
        }
        .background(Color(.systemBackground))
        .navigationTitle(viewModel.conversation.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if let tokenUsage = viewModel.tokenUsage {
                    Text("\(tokenUsage.totalUsed)/\(tokenUsage.totalBudget)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Button {
                    isShowingSettings = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
            }
        }
        .task {
            await viewModel.loadMessages()
            await viewModel.loadSettingsOptions()
        }
        .sheet(isPresented: $isShowingSettings) {
            ChatSettingsSheet(viewModel: viewModel)
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if viewModel.messages.isEmpty && !viewModel.isGenerating {
                    chatEmptyState
                } else {
                    LazyVStack(spacing: 24) {
                        ForEach(viewModel.messages) { item in
                            MessageBubbleView(
                                item: item,
                                isStreaming: isStreamingMessage(item),
                                onDelete: {
                                    Task { await viewModel.deleteMessage(item.id) }
                                },
                                onRegenerate: {
                                    Task { await viewModel.regenerateLastResponse() }
                                }
                            )
                            .id(item.id)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }
            }
            .onChange(of: viewModel.messages) { _, newMessages in
                if let last = newMessages.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var chatEmptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text(String(localized: "Send a message to start the conversation."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 80)
    }

    // MARK: - Helpers

    private func isStreamingMessage(_ item: MessageDisplayItem) -> Bool {
        viewModel.isGenerating && item.id == viewModel.messages.last?.id && item.role == "assistant"
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
                    worldBookId: nil,
                    apiEndpointId: nil,
                    contextStrategy: "truncation",
                    customScenario: nil,
                    modelParameters: nil,
                    isPinned: false,
                    createdAt: .now,
                    updatedAt: .now
                ),
                databaseManager: DependencyContainer.preview().databaseManager,
                apiClient: DependencyContainer.preview().apiClient,
                contextManager: DependencyContainer.preview().contextManager,
                appState: AppState()
            )
        )
    }
}
