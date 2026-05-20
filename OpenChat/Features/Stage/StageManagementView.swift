import SwiftUI

struct StageManagementView: View {
    @State private var viewModel: StageManagementViewModel

    init(viewModel: StageManagementViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.stages.isEmpty {
                LoadingIndicator()
            } else if viewModel.stages.isEmpty {
                EmptyStateView(
                    title: String(localized: "No Stages"),
                    message: String(localized: "Enable Stage from a chat settings panel to manage it here."),
                    systemImage: "theatermasks"
                )
            } else {
                List(viewModel.stages) { item in
                    Button {
                        viewModel.openConversation(item)
                    } label: {
                        StageManagementRow(item: item)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("stage.management.row.\(item.stage.id)")
                }
            }
        }
        .navigationTitle(String(localized: "Stages"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await viewModel.loadStages() }
                } label: {
                    Label(String(localized: "Refresh"), systemImage: "arrow.clockwise")
                }
            }
        }
        .task { await viewModel.loadStages() }
        .overlay(alignment: .bottom) {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.regularMaterial)
            }
        }
    }
}

private struct StageManagementRow: View {
    let item: StageListItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(item.stage.title?.nilIfBlank ?? item.conversation.title)
                    .font(.headline)
                Spacer()
                stageStatus
            }

            HStack(spacing: 8) {
                Label(item.stage.directorModeValue.displayName, systemImage: "megaphone")
                Label(
                    String.localizedStringWithFormat(
                        String(localized: "%lld participants"),
                        Int64(item.participants.count)
                    ),
                    systemImage: "person.2"
                )
                Label(
                    String.localizedStringWithFormat(
                        String(localized: "%lld instructions"),
                        Int64(item.instructions.count)
                    ),
                    systemImage: "text.badge.checkmark"
                )
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if !item.participants.isEmpty {
                Text(item.participants.map(\.displayName).joined(separator: ", "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let latestInstruction = item.instructions.last {
                Text(latestInstruction.content)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 6)
    }

    private var stageStatus: some View {
        Text(item.stage.isEnabled ? String(localized: "Enabled") : String(localized: "Disabled"))
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(item.stage.isEnabled ? Color.green.opacity(0.15) : Color.gray.opacity(0.15), in: Capsule())
            .foregroundStyle(item.stage.isEnabled ? .green : .secondary)
    }
}

private extension DirectorMode {
    var displayName: String {
        switch self {
        case .silent:
            String(localized: "Silent")
        case .agent:
            String(localized: "Agent")
        case .userControlled:
            String(localized: "User Controlled")
        }
    }
}

#Preview {
    NavigationStack {
        StageManagementView(
            viewModel: StageManagementViewModel(
                databaseManager: DependencyContainer.preview().databaseManager,
                appState: AppState()
            )
        )
    }
}
