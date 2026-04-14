import SwiftUI

struct SettingsView: View {
    @Environment(DependencyContainer.self) private var container
    @State private var viewModel: SettingsViewModel
    @State private var editingEndpoint: APIEndpointRecord?

    init(viewModel: SettingsViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "API Endpoints")) {
                    ForEach(viewModel.endpoints) { endpoint in
                        Button {
                            editingEndpoint = endpoint
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(endpoint.name)
                                    if endpoint.isDefault {
                                        Text(String(localized: "Default"))
                                            .font(.caption)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(.blue.opacity(0.15), in: Capsule())
                                    }
                                }
                                Text(endpoint.baseURL)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(String(localized: "Set Default")) {
                                Task { await viewModel.setDefaultEndpoint(endpoint.id) }
                            }
                            Button(String(localized: "Delete"), role: .destructive) {
                                Task { await viewModel.deleteEndpoint(endpoint.id) }
                            }
                        }
                    }

                    Button(String(localized: "Add Endpoint")) {
                        editingEndpoint = APIEndpointRecord(
                            id: "",
                            name: "",
                            baseURL: "",
                            apiKey: nil,
                            modelName: AppConstants.defaultModelName,
                            maxContextTokens: AppConstants.defaultMaxContextTokens,
                            isDefault: viewModel.endpoints.isEmpty,
                            createdAt: .now,
                            updatedAt: .now
                        )
                    }
                }

                Section(String(localized: "Model Defaults")) {
                    ModelParametersView(viewModel: viewModel)
                }

                Section(String(localized: "Data")) {
                    DataManagementView(viewModel: viewModel)
                }
            }
            .navigationTitle(String(localized: "Settings"))
            .task {
                await viewModel.loadEndpoints()
            }
            .sheet(item: $editingEndpoint, onDismiss: reload) { endpoint in
                APIEndpointEditorView(
                    viewModel: APIEndpointEditorViewModel(
                        databaseManager: container.databaseManager,
                        apiClient: container.apiClient,
                        editingEndpoint: endpoint.id.isEmpty ? nil : endpoint
                    )
                )
            }
        }
    }

    private func reload() {
        Task {
            await viewModel.loadEndpoints()
        }
    }
}
