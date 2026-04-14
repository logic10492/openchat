import SwiftUI

struct WorldBookListView: View {
    @Environment(DependencyContainer.self) private var container
    @State private var viewModel: WorldBookListViewModel
    @State private var editingWorldBook: WorldBookRecord?

    init(viewModel: WorldBookListViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
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
                            HStack(spacing: 12) {
                                Image(systemName: "book.closed")
                                    .font(.title3)
                                    .foregroundStyle(worldBook.isEnabled ? Color.accentColor : Color(.systemGray3))
                                    .frame(width: 28)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(worldBook.name)
                                        .font(.subheadline.weight(.medium))
                                    if let desc = worldBook.description?.nilIfBlank {
                                        Text(desc)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
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
                .listStyle(.plain)
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

    private func reload() {
        Task {
            await viewModel.loadWorldBooks()
        }
    }
}

#Preview {
    NavigationStack {
        WorldBookListView(
            viewModel: WorldBookListViewModel(
                databaseManager: DependencyContainer.preview().databaseManager,
                appState: AppState()
            )
        )
    }
    .environment(DependencyContainer.preview())
}
