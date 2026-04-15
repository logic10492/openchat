import SwiftUI

struct MemoryListView: View {
    @State private var viewModel: MemoryListViewModel
    @State private var showDeleteAllConfirmation = false

    init(viewModel: MemoryListViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        Group {
            if viewModel.filteredMemories.isEmpty {
                EmptyStateView(
                    title: String(localized: "No Memories"),
                    message: String(localized: "Memories are created automatically from conversations."),
                    systemImage: "brain"
                )
            } else {
                listContent
            }
        }
        .navigationTitle(String(localized: "Memories"))
        .searchable(text: searchBinding)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(String(localized: "Clear All"), role: .destructive) {
                    showDeleteAllConfirmation = true
                }
                .disabled(viewModel.memories.isEmpty)
            }
        }
        .confirmationDialog(
            String(localized: "Delete All Memories?"),
            isPresented: $showDeleteAllConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Delete All"), role: .destructive) {
                Task { await viewModel.deleteAllMemories() }
            }
        } message: {
            Text(String(localized: "This action cannot be undone."))
        }
        .task { await viewModel.loadMemories() }
    }

    private var listContent: some View {
        List {
            ForEach(viewModel.filteredMemories) { entry in
                memoryRow(entry)
                    .swipeActions {
                        Button(String(localized: "Delete"), role: .destructive) {
                            Task { await viewModel.deleteMemory(entry.id) }
                        }
                    }
            }
        }
        .listStyle(.plain)
    }

    private func memoryRow(_ entry: MemoryEntryRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                memoryTypeBadge(entry.memoryTypeValue)
                Spacer()
                Text(entry.createdAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(entry.content)
                .font(.subheadline)
                .lineLimit(4)
            ProgressView(value: Double(entry.importance), total: 10)
                .tint(importanceColor(entry.importance))
        }
        .padding(.vertical, 4)
    }

    private func memoryTypeBadge(_ type: MemoryType) -> some View {
        Text(type.displayName)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(type.badgeColor.opacity(0.15), in: Capsule())
            .foregroundStyle(type.badgeColor)
    }

    private func importanceColor(_ importance: Int) -> Color {
        switch importance {
        case 0...3: .green
        case 4...6: .yellow
        default: .red
        }
    }

    private var searchBinding: Binding<String> {
        @Bindable var viewModel = viewModel
        return $viewModel.searchText
    }
}

private extension MemoryType {
    var displayName: String {
        switch self {
        case .event: String(localized: "Event")
        case .fact: String(localized: "Fact")
        case .relationship: String(localized: "Relationship")
        case .summary: String(localized: "Summary")
        }
    }

    var badgeColor: Color {
        switch self {
        case .event: .blue
        case .fact: .orange
        case .relationship: .pink
        case .summary: .purple
        }
    }
}
