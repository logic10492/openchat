import SwiftUI

struct CharacterCardListView: View {
    @Environment(DependencyContainer.self) private var container
    @Environment(AppState.self) private var appState
    @State private var viewModel: CharacterCardListViewModel
    @State private var editingCard: CharacterCardRecord?
    @State private var selectedCard: CharacterCardRecord?
    @State private var isShowingImport = false

    init(viewModel: CharacterCardListViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        Group {
            if viewModel.filteredCards.isEmpty {
                EmptyStateView(
                    title: String(localized: "No Characters"),
                    message: String(localized: "Create a character card to guide conversations."),
                    systemImage: "person.text.rectangle"
                )
            } else {
                listContent
            }
        }
        .navigationTitle(String(localized: "Characters"))
        .searchable(text: searchBinding)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    isShowingImport = true
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .accessibilityLabel(String(localized: "Import Character"))

                Button {
                    editingCard = CharacterCardRecord(
                        id: "",
                        name: "",
                        avatar: nil,
                        personality: nil,
                        appearance: nil,
                        physique: nil,
                        speechStyle: nil,
                        backstory: nil,
                        systemPrompt: nil,
                        scenario: nil,
                        exampleDialogs: nil,
                        creatorNotes: nil,
                        tags: nil,
                        worldBookId: nil,
                        createdAt: .now,
                        updatedAt: .now
                    )
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .task {
            await viewModel.loadCards()
        }
        .sheet(item: $editingCard, onDismiss: reloadCards) { card in
            CharacterCardEditorRouterView(
                databaseManager: container.databaseManager,
                skillBundleStore: container.skillBundleStore,
                card: card,
                defaultWorldBookId: nil
            )
        }
        .sheet(isPresented: $isShowingImport, onDismiss: reloadCards) {
            CharacterCardImportView(
                onImportText: { text in
                    let parsedCard = try CharacterCardImportFormat.parse(text: text)
                    _ = try await viewModel.importCard(parsedCard)
                },
                onImportFile: { data, sourceFileName in
                    _ = try await viewModel.importFile(data: data, sourceFileName: sourceFileName)
                }
            )
        }
        .sheet(item: $selectedCard, onDismiss: reloadCards) { card in
            CharacterCardDetailView(
                card: card,
                onEdit: {
                    selectedCard = nil
                    editingCard = card
                }
            )
        }
    }

    // MARK: - List Content

    private var listContent: some View {
        List {
            ForEach(viewModel.filteredCards) { card in
                Button {
                    selectedCard = card
                } label: {
                    HStack(spacing: OpenChatDesignSystem.Spacing.sm) {
                        Circle()
                            .fill(OpenChatDesignSystem.Surface.accentWash)
                            .frame(width: 40, height: 40)
                            .overlay {
                                Image(systemName: "person.fill")
                                    .font(.system(size: OpenChatDesignSystem.IconSize.sm))
                                    .foregroundStyle(Color.accentColor)
                            }

                        VStack(alignment: .leading, spacing: OpenChatDesignSystem.Spacing.xxs) {
                            Text(card.name)
                                .font(OpenChatDesignSystem.Typography.rowTitle)
                            if !card.decodedTags.isEmpty {
                                Text(card.decodedTags.joined(separator: " · "))
                                    .font(OpenChatDesignSystem.Typography.metadata)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
                .swipeActions {
                    Button(String(localized: "Delete"), role: .destructive) {
                        Task { await viewModel.deleteCard(card) }
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Bindings

    private var searchBinding: Binding<String> {
        @Bindable var viewModel = viewModel
        return $viewModel.searchText
    }

    private func reloadCards() {
        Task {
            await viewModel.loadCards()
        }
    }
}

#Preview {
    NavigationStack {
        CharacterCardListView(
            viewModel: CharacterCardListViewModel(
                databaseManager: DependencyContainer.preview().databaseManager,
                appState: AppState(),
                skillBundleStore: DependencyContainer.preview().skillBundleStore
            )
        )
    }
    .environment(AppState())
    .environment(DependencyContainer.preview())
}
