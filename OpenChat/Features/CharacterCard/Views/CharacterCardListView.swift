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
        NavigationStack {
            Group {
                if viewModel.filteredCards.isEmpty {
                    EmptyStateView(
                        title: String(localized: "No Characters"),
                        message: String(localized: "Create a character card to guide conversations."),
                        systemImage: "person.text.rectangle"
                    )
                } else if viewModel.displayMode == .grid {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 16) {
                            ForEach(viewModel.filteredCards) { card in
                                Button {
                                    selectedCard = card
                                } label: {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Image(systemName: "person.crop.square")
                                            .font(.system(size: 36))
                                            .frame(maxWidth: .infinity)
                                        Text(card.name)
                                            .font(.headline)
                                            .multilineTextAlignment(.leading)
                                        Text(card.decodedTags.joined(separator: ", "))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 140)
                                    .openChatCardStyle()
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
                } else {
                    List {
                        ForEach(viewModel.filteredCards) { card in
                            Button {
                                selectedCard = card
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(card.name)
                                    Text(card.decodedTags.joined(separator: ", "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
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
                }
            }
            .navigationTitle(String(localized: "Characters"))
            .searchable(text: searchBinding)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Picker(String(localized: "Display"), selection: displayBinding) {
                        ForEach(CharacterCardListViewModel.DisplayMode.allCases) { mode in
                            Text(mode.rawValue.capitalized).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Button {
                        editingCard = nil
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
    }

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
