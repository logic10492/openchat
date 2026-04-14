import SwiftUI

struct WorldBookListView: View {
    @Environment(DependencyContainer.self) private var container
    @State private var viewModel: WorldBookListViewModel
    @State private var editingWorldBook: WorldBookRecord?

    init(viewModel: WorldBookListViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.worldBooks.isEmpty {
                    EmptyStateView(
                        title: String(localized: "No World Books"),
                        message: String(localized: "Add a world book to inject setting knowledge into prompts."),
                        systemImage: "books.vertical"
                    )
                } else {
                    List {
                        ForEach(viewModel.worldBooks) { worldBook in
                            Button {
                                editingWorldBook = worldBook
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(worldBook.name)
                                        Text(worldBook.description ?? "")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Toggle("", isOn: Binding(
                                        get: { worldBook.isEnabled },
                                        set: { _ in
                                            Task { await viewModel.toggleEnabled(worldBook) }
                                        }
                                    ))
                                    .labelsHidden()
                                }
                            }
                            .buttonStyle(.plain)
                            .swipeActions {
                                Button(String(localized: "Delete"), role: .destructive) {
                                    Task { await viewModel.deleteWorldBook(worldBook) }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "World Books"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editingWorldBook = WorldBookRecord(
                            id: "",
                            name: "",
                            description: nil,
                            isEnabled: true,
                            createdAt: .now,
                            updatedAt: .now
                        )
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .task {
                await viewModel.loadWorldBooks()
            }
            .sheet(item: $editingWorldBook, onDismiss: reload) { worldBook in
                WorldBookEditorView(
                    viewModel: WorldBookEditorViewModel(
                        databaseManager: container.databaseManager,
                        editingWorldBook: worldBook.id.isEmpty ? nil : worldBook
                    )
                )
            }
        }
    }

    private func reload() {
        Task {
            await viewModel.loadWorldBooks()
        }
    }
}
