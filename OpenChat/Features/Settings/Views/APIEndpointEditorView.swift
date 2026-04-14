import SwiftUI

struct APIEndpointEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: APIEndpointEditorViewModel

    init(viewModel: APIEndpointEditorViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "Name"), text: bind(\.name))
                    TextField(String(localized: "Base URL"), text: bind(\.baseURL))
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField(String(localized: "API Key"), text: bind(\.apiKey))
                }

                Section(String(localized: "Model")) {
                    modelSelectionContent
                }

                Section {
                    Stepper(value: bind(\.maxContextTokens), in: 512...128_000, step: 512) {
                        Text("\(String(localized: "Max Context Tokens")): \(viewModel.maxContextTokens)")
                    }
                    Toggle(String(localized: "Default Endpoint"), isOn: bind(\.isDefault))
                }

                Section {
                    Button(String(localized: "Test Connection")) {
                        Task { await viewModel.testConnection() }
                    }

                    if let testResult = viewModel.testResult {
                        switch testResult {
                        case .testing:
                            LoadingIndicator(String(localized: "Testing"))
                        case .success(let message):
                            Text(message).foregroundStyle(.green)
                        case .failure(let message):
                            Text(message).foregroundStyle(.red)
                        }
                    }
                }
            }
            .navigationTitle(viewModel.editingEndpoint == nil ? String(localized: "New Endpoint") : String(localized: "Edit Endpoint"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "Save")) {
                        Task {
                            try? await viewModel.save()
                            dismiss()
                        }
                    }
                    .disabled(!viewModel.isValid)
                }
            }
            .onChange(of: viewModel.baseURL) {
                viewModel.scheduleFetchModels()
            }
            .onChange(of: viewModel.apiKey) {
                viewModel.scheduleFetchModels()
            }
            .task {
                await viewModel.fetchAvailableModels()
            }
        }
    }

    @ViewBuilder
    private var modelSelectionContent: some View {
        if viewModel.isFetchingModels {
            HStack {
                Text(String(localized: "Loading models…"))
                    .foregroundStyle(.secondary)
                Spacer()
                ProgressView()
            }
        } else if !viewModel.availableModels.isEmpty && !viewModel.isCustomModelInput {
            Picker(String(localized: "Model"), selection: bind(\.modelName)) {
                ForEach(viewModel.availableModels, id: \.self) { model in
                    Text(model).tag(model)
                }
            }

            Button(String(localized: "Enter custom model name")) {
                viewModel.isCustomModelInput = true
            }
            .font(.footnote)
        } else {
            TextField(String(localized: "Model Name"), text: bind(\.modelName))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            if let errorMessage = viewModel.modelFetchError {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                if !viewModel.availableModels.isEmpty {
                    Button(String(localized: "Back to model list")) {
                        viewModel.isCustomModelInput = false
                    }
                    .font(.footnote)
                }

                Spacer()

                Button(String(localized: "Retry")) {
                    Task { await viewModel.fetchAvailableModels() }
                }
                .font(.footnote)
            }
        }
    }

    private func bind<Value>(_ keyPath: ReferenceWritableKeyPath<APIEndpointEditorViewModel, Value>) -> Binding<Value> {
        @Bindable var viewModel = viewModel
        return Binding(
            get: { viewModel[keyPath: keyPath] },
            set: { viewModel[keyPath: keyPath] = $0 }
        )
    }
}
