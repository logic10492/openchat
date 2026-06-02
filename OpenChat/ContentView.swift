import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(DependencyContainer.self) private var container

    var body: some View {
        @Bindable var appState = appState
        NavigationSplitView(columnVisibility: $appState.columnVisibility) {
            SidebarView(
                viewModel: ConversationListViewModel(
                    databaseManager: container.databaseManager,
                    appState: appState
                )
            )
            .navigationTitle(String(localized: "OpenChat"))
            .navigationBarTitleDisplayMode(.inline)
        } detail: {
            detailView
        }
        .alert(
            String(localized: "Error"),
            isPresented: errorBinding
        ) {
            Button(String(localized: "OK"), role: .cancel) {
                appState.isShowingError = false
                appState.lastErrorMessage = nil
            }
        } message: {
            Text(appState.lastErrorMessage ?? String(localized: "Unknown error"))
        }
    }

    @ViewBuilder
    private var detailView: some View {
        if let conversationID = appState.selectedConversationID {
            ChatDetailContainer(conversationID: conversationID)
        } else {
            WelcomeView {
                createNewChat()
            }
        }
    }

    private func createNewChat() {
        Task {
            let viewModel = ConversationListViewModel(
                databaseManager: container.databaseManager,
                appState: appState
            )
            await viewModel.loadConversations()
            if let conversation = await viewModel.createConversation() {
                appState.selectedConversationID = conversation.id
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        @Bindable var appState = appState
        return $appState.isShowingError
    }
}

// MARK: - Chat Detail Container

/// Loads conversation from DB and shows ChatView, handling missing conversations.
private struct ChatDetailContainer: View {
    let conversationID: String
    @Environment(DependencyContainer.self) private var container
    @Environment(AppState.self) private var appState
    @State private var conversation: ConversationRecord?
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                LoadingIndicator()
            } else if let conversation {
                ChatView(
                    viewModel: ChatViewModel(
                        conversation: conversation,
                        databaseManager: container.databaseManager,
                        apiClient: container.apiClient,
                        contextManager: container.contextManager,
                        memoryManager: container.memoryManager,
                        memoryReflectBackgroundWorker: container.memoryReflectBackgroundWorker,
                        worldBookEmbeddingIndexer: container.worldBookEmbeddingIndexer,
                        worldBookSource: container.worldBookSource,
                        backgroundManager: container.backgroundManager,
                        titleGenerator: container.titleGenerator,
                        skillBundleMaterializer: container.skillBundleMaterializer,
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
        .task(id: conversationID) {
            isLoading = true
            conversation = try? await container.databaseManager.fetchConversation(id: conversationID)
            isLoading = false
        }
    }
}

#Preview {
    ContentView()
        .environment(AppState())
        .environment(DependencyContainer.preview())
}
