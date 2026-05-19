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
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    Task { await viewModel.runReflect(task: .summarize) }
                } label: {
                    Label(String(localized: "Organize Memories"), systemImage: "wand.and.stars")
                }
                .disabled(viewModel.isReflectBusy || viewModel.memories.count < 2)

                Button(String(localized: "Clear All"), role: .destructive) {
                    showDeleteAllConfirmation = true
                }
                .disabled(viewModel.isReflectBusy || viewModel.memories.isEmpty)
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
        .safeAreaInset(edge: .bottom) {
            if viewModel.reflectDraft != nil || viewModel.reflectErrorMessage != nil || viewModel.errorMessage != nil {
                VStack(alignment: .leading, spacing: 8) {
                    if let draft = viewModel.reflectDraft {
                        draftPreview(draft)
                    }
                    if let errorMessage = viewModel.reflectErrorMessage ?? viewModel.errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.regularMaterial)
            }
        }
    }

    private var selectionHeader: some View {
        HStack {
            Text(
                String.localizedStringWithFormat(
                    String(localized: "%lld selected"),
                    Int64(viewModel.selectedMemoryIds.count)
                )
            )
            Spacer()
            if viewModel.reflectState == .running {
                Label(String(localized: "Generating Draft"), systemImage: "sparkles")
            } else if viewModel.reflectState == .applying {
                Label(String(localized: "Applying"), systemImage: "arrow.down.doc")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var listContent: some View {
        List {
            Section {
                selectionHeader
            }
            ForEach(viewModel.filteredMemories) { entry in
                HStack(spacing: 12) {
                    Button {
                        viewModel.toggleMemorySelection(entry.id)
                    } label: {
                        Image(systemName: viewModel.isMemorySelected(entry.id) ? "checkmark.circle.fill" : "circle")
                            .imageScale(.large)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "Select Memory"))
                    .disabled(viewModel.isReflectBusy)

                    memoryRow(entry)
                }
                    .swipeActions {
                        Button(String(localized: "Delete"), role: .destructive) {
                            Task { await viewModel.deleteMemory(entry.id) }
                        }
                    }
            }
        }
        .listStyle(.plain)
    }

    private func draftPreview(_ draft: MemoryReflectObservation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(localized: "Draft Observation"))
                    .font(.caption.weight(.semibold))
                Spacer()
                memoryTypeBadge(draft.memoryType)
            }

            Text(draft.content)
                .font(.subheadline)
                .lineLimit(4)

            HStack {
                Text(
                    String.localizedStringWithFormat(
                        String(localized: "Based on %lld memories"),
                        Int64(draft.basedOnMemoryIds.count)
                    )
                )
                if let confidence = draft.confidence {
                    Text(
                        String.localizedStringWithFormat(
                            String(localized: "Confidence %@"),
                            confidence.formatted(.percent.precision(.fractionLength(0)))
                        )
                    )
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            HStack {
                Button(String(localized: "Apply")) {
                    Task { await viewModel.applyReflectObservation() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canApplyReflectDraft)

                Button(String(localized: "Cancel")) {
                    viewModel.clearReflectDraft()
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isReflectBusy)
            }
        }
        .padding(.vertical, 4)
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
            ProgressView(value: Double(entry.importance), total: 100)
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
        case 0...30: .green
        case 31...69: .yellow
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
