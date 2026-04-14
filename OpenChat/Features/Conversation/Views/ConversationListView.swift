import SwiftUI

struct ConversationListView: View {
    @Environment(DependencyContainer.self) private var container
    @Environment(AppState.self) private var appState
    @State private var viewModel: ConversationListViewModel
    @State private var path: [String] = []

    init(viewModel: ConversationListViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if viewModel.isLoading && viewModel.conversations.isEmpty {
                    LoadingIndicator()
                } else if viewModel.conversations.isEmpty {
                    EmptyStateView(
                        title: String(localized: "No Conversations"),
                        message: String(localized: "Create a conversation to start chatting."),
                        systemImage: "bubble.left.and.bubble.right"
                    )
                } else {
                    List {
                        ForEach(viewModel.conversations) { conversation in
                            NavigationLink(value: conversation.id) {
                                ConversationRowView(conversation: conversation)
                            }
                        }
                        .onDelete { offsets in
                            Task {
                                for index in offsets {
                                    await viewModel.deleteConversation(viewModel.conversations[index])
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(String(localized: "Chats"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            if let conversation = await viewModel.createConversation() {
                                path = [conversation.id]
                            }
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .navigationDestination(for: String.self) { conversationID in
                if let conversation = viewModel.conversation(id: conversationID) {
                    ChatView(
                        viewModel: ChatViewModel(
                            conversation: conversation,
                            databaseManager: container.databaseManager,
                            apiClient: container.apiClient,
                            contextManager: container.contextManager,
                            appState: appState
                        )
                    )
                } else {
                    EmptyStateView(
                        title: String(localized: "Conversation Missing"),
                        message: String(localized: "The selected conversation is no longer available."),
                        systemImage: "exclamationmark.bubble"
                    )
                }
            }
        }
        .task {
            await viewModel.loadConversations()
        }
    }
}
