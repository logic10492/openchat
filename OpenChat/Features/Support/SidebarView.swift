import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var appState
    @Environment(DependencyContainer.self) private var container
    @State private var viewModel: ConversationListViewModel
    @State private var isShowingCharacters = false
    @State private var isShowingWorldBooks = false
    @State private var isShowingStages = false
    @State private var renamingConversationID: String?
    @State private var renameText = ""

    init(viewModel: ConversationListViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        VStack(spacing: 0) {
            newChatButton
            conversationList
            Divider()
            bottomActions
        }
        .task {
            await viewModel.loadConversations()
        }
        .onChange(of: appState.conversationListNeedsRefresh) { _, needsRefresh in
            if needsRefresh {
                appState.conversationListNeedsRefresh = false
                Task { await viewModel.loadConversations() }
            }
        }
        .alert(
            String(localized: "Rename Conversation"),
            isPresented: renameAlertBinding
        ) {
            TextField(String(localized: "Title"), text: $renameText)
            Button(String(localized: "Cancel"), role: .cancel) {
                renamingConversationID = nil
            }
            Button(String(localized: "Save")) {
                if let id = renamingConversationID {
                    Task { await viewModel.renameConversation(id, newTitle: renameText) }
                }
                renamingConversationID = nil
            }
        }
        .sheet(isPresented: $isShowingCharacters) {
            NavigationStack {
                CharacterCardListView(
                    viewModel: CharacterCardListViewModel(
                        databaseManager: container.databaseManager,
                        appState: appState,
                        skillBundleStore: container.skillBundleStore
                    )
                )
            }
        }
        .sheet(isPresented: $isShowingWorldBooks) {
            NavigationStack {
                WorldBookListView(
                    viewModel: WorldBookListViewModel(
                        databaseManager: container.databaseManager,
                        appState: appState
                    )
                )
            }
        }
        .sheet(isPresented: $isShowingStages) {
            NavigationStack {
                StageManagementView(
                    viewModel: StageManagementViewModel(
                        databaseManager: container.databaseManager,
                        appState: appState
                    )
                )
            }
        }
        .sheet(isPresented: settingsBinding) {
            NavigationStack {
                SettingsView(
                    viewModel: SettingsViewModel(
                        databaseManager: container.databaseManager,
                        apiClient: container.apiClient,
                        apiKeyStore: container.apiKeyStore,
                        worldBookEmbeddingIndexer: container.worldBookEmbeddingIndexer,
                        appState: appState
                    )
                )
            }
        }
    }

    // MARK: - New Chat Button

    private var newChatButton: some View {
        Button {
            Task {
                if let conversation = await viewModel.createConversation() {
                    appState.selectedConversationID = conversation.id
                }
            }
        } label: {
            HStack {
                Image(systemName: "plus")
                Text(String(localized: "New Chat"))
                Spacer()
            }
            .font(OpenChatDesignSystem.Typography.rowTitle)
            .padding(.horizontal, OpenChatDesignSystem.Spacing.sm)
            .padding(.vertical, 10)
            .background(
                OpenChatDesignSystem.Surface.sidebarControl,
                in: RoundedRectangle(cornerRadius: OpenChatDesignSystem.Radius.sm, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("sidebar.newChat")
        .padding(.horizontal, OpenChatDesignSystem.Spacing.sm)
        .padding(.vertical, OpenChatDesignSystem.Spacing.xs)
    }

    // MARK: - Conversation List

    private var conversationList: some View {
        Group {
            if viewModel.isLoading && viewModel.conversations.isEmpty {
                LoadingIndicator()
                    .frame(maxHeight: .infinity)
            } else if viewModel.conversations.isEmpty {
                VStack(spacing: OpenChatDesignSystem.Spacing.xs) {
                    Text(String(localized: "No conversations yet"))
                        .font(OpenChatDesignSystem.Typography.secondary)
                        .foregroundStyle(.secondary)
                }
                .frame(maxHeight: .infinity)
            } else {
                List(viewModel.conversations, selection: conversationSelection) { conversation in
                    SidebarConversationRow(
                        conversation: conversation,
                        isSelected: appState.selectedConversationID == conversation.id
                    )
                    .accessibilityIdentifier("sidebar.conversation.\(conversation.id)")
                    .tag(conversation.id)
                    .listRowInsets(EdgeInsets(
                        top: OpenChatDesignSystem.Spacing.xxs,
                        leading: OpenChatDesignSystem.Spacing.xs,
                        bottom: OpenChatDesignSystem.Spacing.xxs,
                        trailing: OpenChatDesignSystem.Spacing.xs
                    ))
                    .swipeActions(edge: .trailing) {
                        Button(String(localized: "Delete"), role: .destructive) {
                            Task { await viewModel.deleteConversation(conversation) }
                        }
                    }
                    .contextMenu {
                        Button {
                            renameText = conversation.title
                            renamingConversationID = conversation.id
                        } label: {
                            Label(String(localized: "Rename"), systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            Task { await viewModel.deleteConversation(conversation) }
                        } label: {
                            Label(String(localized: "Delete"), systemImage: "trash")
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: - Bottom Actions

    private var bottomActions: some View {
        VStack(spacing: 0) {
            sidebarActionButton(
                title: String(localized: "Characters"),
                systemImage: "person.text.rectangle"
            ) {
                isShowingCharacters = true
            }

            sidebarActionButton(
                title: String(localized: "World Books"),
                systemImage: "books.vertical"
            ) {
                isShowingWorldBooks = true
            }

            sidebarActionButton(
                title: String(localized: "Stages"),
                systemImage: "theatermasks"
            ) {
                isShowingStages = true
            }

            sidebarActionButton(
                title: String(localized: "Settings"),
                systemImage: "gearshape"
            ) {
                appState.isShowingSettings = true
            }
        }
        .padding(.horizontal, OpenChatDesignSystem.Spacing.sm)
        .padding(.vertical, OpenChatDesignSystem.Spacing.xs)
    }

    private func sidebarActionButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: OpenChatDesignSystem.Spacing.xs) {
                Image(systemName: systemImage)
                    .frame(width: OpenChatDesignSystem.IconSize.md)
                Text(title)
                    .font(OpenChatDesignSystem.Typography.secondary)
                Spacer()
            }
            .openChatListRowStyle()
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .accessibilityIdentifier("sidebar.action.\(title)")
    }

    // MARK: - Bindings

    private var conversationSelection: Binding<String?> {
        @Bindable var appState = appState
        return $appState.selectedConversationID
    }

    private var settingsBinding: Binding<Bool> {
        @Bindable var appState = appState
        return $appState.isShowingSettings
    }

    private var renameAlertBinding: Binding<Bool> {
        Binding(
            get: { renamingConversationID != nil },
            set: { if !$0 { renamingConversationID = nil } }
        )
    }
}

// MARK: - Sidebar Conversation Row

struct SidebarConversationRow: View {
    let conversation: ConversationRecord
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: OpenChatDesignSystem.Spacing.xxs) {
            Text(conversation.title)
                .font(OpenChatDesignSystem.Typography.rowTitle)
                .lineLimit(1)
            Text(conversation.updatedAt.openChatRelativeTimestamp())
                .font(OpenChatDesignSystem.Typography.metadata)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, OpenChatDesignSystem.Spacing.xxs)
        .padding(.horizontal, OpenChatDesignSystem.Spacing.xxs)
        .openChatSidebarRow(isSelected: isSelected)
    }
}

#Preview {
    SidebarView(
        viewModel: ConversationListViewModel(
            databaseManager: DependencyContainer.preview().databaseManager,
            appState: AppState()
        )
    )
    .environment(AppState())
    .environment(DependencyContainer.preview())
    .frame(width: 280)
}
