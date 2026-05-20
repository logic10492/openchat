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
            CharacterCardEditorView(
                viewModel: CharacterCardEditorViewModel(
                    databaseManager: container.databaseManager,
                    editingCard: card.id.isEmpty ? nil : card
                )
            )
        }
        .sheet(isPresented: $isShowingImport, onDismiss: reloadCards) {
            CharacterCardImportView { parsedCard in
                _ = try await viewModel.importCard(parsedCard)
            }
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
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color.accentColor.opacity(0.12))
                            .frame(width: 40, height: 40)
                            .overlay {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(Color.accentColor)
                            }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(card.name)
                                .font(.subheadline.weight(.medium))
                            if !card.decodedTags.isEmpty {
                                Text(card.decodedTags.joined(separator: " · "))
                                    .font(.caption)
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
                appState: AppState()
            )
        )
    }
    .environment(AppState())
    .environment(DependencyContainer.preview())
}
