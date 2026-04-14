import SwiftUI

struct CharacterCardListView: View {
    @Environment(DependencyContainer.self) private var container
    @Environment(AppState.self) private var appState
    @State private var viewModel: CharacterCardListViewModel
    @State private var editingCard: CharacterCardRecord?
    @State private var selectedCard: CharacterCardRecord?

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
            } else if viewModel.displayMode == .grid {
                gridContent
            } else {
                listContent
            }
        }
        .navigationTitle(String(localized: "Characters"))
        .searchable(text: searchBinding)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Picker(String(localized: "Display"), selection: displayBinding) {
                    Image(systemName: "square.grid.2x2").tag(CharacterCardListViewModel.DisplayMode.grid)
                    Image(systemName: "list.bullet").tag(CharacterCardListViewModel.DisplayMode.list)
                }
                .pickerStyle(.segmented)

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

    // MARK: - Grid Content

    private var gridContent: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 16) {
                ForEach(viewModel.filteredCards) { card in
                    Button {
                        selectedCard = card
                    } label: {
                        VStack(spacing: 12) {
                            Circle()
                                .fill(Color.accentColor.opacity(0.12))
                                .frame(width: 56, height: 56)
                                .overlay {
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 24))
                                        .foregroundStyle(Color.accentColor)
                                }

                            VStack(spacing: 4) {
                                Text(card.name)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)

                                if !card.decodedTags.isEmpty {
                                    Text(card.decodedTags.joined(separator: " · "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 150)
                        .padding(12)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(String(localized: "Duplicate")) {
                            Task { await viewModel.duplicateCard(card) }
                        }
                        Button(String(localized: "Delete"), role: .destructive) {
                            Task { await viewModel.deleteCard(card) }
                        }
                    }
                }
            }
            .padding()
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

    private var displayBinding: Binding<CharacterCardListViewModel.DisplayMode> {
        @Bindable var viewModel = viewModel
        return $viewModel.displayMode
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
