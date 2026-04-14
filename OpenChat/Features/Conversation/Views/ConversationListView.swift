import SwiftUI

/// Standalone conversation list with its own NavigationStack.
/// Used when presented as a sheet or pushed onto a navigation stack.
/// The sidebar uses SidebarView directly which embeds conversation list inline.
struct ConversationListView: View {
    @Environment(DependencyContainer.self) private var container
    @Environment(AppState.self) private var appState
    @State private var viewModel: ConversationListViewModel

    init(viewModel: ConversationListViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
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
                List(viewModel.conversations, selection: conversationSelection) { conversation in
                    ConversationRowView(conversation: conversation)
                        .tag(conversation.id)
                        .swipeActions(edge: .trailing) {
                            Button(String(localized: "Delete"), role: .destructive) {
                                Task { await viewModel.deleteConversation(conversation) }
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
                            appState.selectedConversationID = conversation.id
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .task {
            await viewModel.loadConversations()
        }
    }

    private var conversationSelection: Binding<String?> {
        @Bindable var appState = appState
        return $appState.selectedConversationID
    }
}

#Preview {
    NavigationStack {
        ConversationListView(
            viewModel: ConversationListViewModel(
                databaseManager: DependencyContainer.preview().databaseManager,
                appState: AppState()
            )
        )
    }
    .environment(AppState())
    .environment(DependencyContainer.preview())
}
