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
                TextField(String(localized: "Name"), text: bind(\.name))
                TextField(String(localized: "Base URL"), text: bind(\.baseURL))
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField(String(localized: "API Key"), text: bind(\.apiKey))
                TextField(String(localized: "Model Name"), text: bind(\.modelName))
                Stepper(value: bind(\.maxContextTokens), in: 512...128000, step: 512) {
                    Text("\(String(localized: "Max Context Tokens")): \(viewModel.maxContextTokens)")
                }
                Toggle(String(localized: "Default Endpoint"), isOn: bind(\.isDefault))

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
