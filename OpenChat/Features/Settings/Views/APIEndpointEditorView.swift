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
                    SecureField(String(localized: "API Key"), text: bind(\.apiKey))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if viewModel.hasStoredAPIKey && viewModel.apiKey.isEmpty {
                        HStack {
                            Label(String(localized: "Stored API Key"), systemImage: "key.fill")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button(String(localized: "Clear")) {
                                viewModel.clearStoredAPIKey()
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }

                Section {
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

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                modelsSection
            }
            .navigationTitle(viewModel.editingEndpoint == nil ? String(localized: "New Endpoint") : String(localized: "Edit Endpoint"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "Save")) {
                        Task {
                            do {
                                _ = try await viewModel.save()
                                dismiss()
                            } catch {
                                // ViewModel owns the visible error message.
                            }
                        }
                    }
                    .disabled(!viewModel.isValid || viewModel.isSaving)
                }
            }
            .onChange(of: viewModel.baseURL) {
                viewModel.scheduleFetchModels()
            }
            .onChange(of: viewModel.apiKey) {
                viewModel.scheduleFetchModels()
            }
            .task {
                await viewModel.loadModels()
                await viewModel.fetchAndMergeModels()
            }
            .sheet(isPresented: bind(\.isShowingAddModel)) {
                addModelSheet
            }
            .sheet(isPresented: bind(\.isShowingEditModel), onDismiss: {
                viewModel.cancelEditingModel()
            }) {
                editModelSheet
            }
        }
    }

    // MARK: - Models Section

    @ViewBuilder
    private var modelsSection: some View {
        Section(String(localized: "Available Models")) {
            if viewModel.isFetchingModels && viewModel.models.isEmpty {
                HStack {
                    Text(String(localized: "Loading models…"))
                        .foregroundStyle(.secondary)
                    Spacer()
                    ProgressView()
                }
            }

            ForEach(viewModel.models) { model in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(model.modelId)
                                .font(.subheadline)
                            if model.isDefault {
                                Text(String(localized: "Default"))
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.blue.opacity(0.15), in: Capsule())
                            }
                            if model.isManual {
                                Text(String(localized: "Manual"))
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.orange.opacity(0.15), in: Capsule())
                            }
                        }
                        Text("\(model.maxContextTokens) tokens · \(model.apiModeValue == .responses ? String(localized: "Responses") : String(localized: "Chat Completions")) · \(model.providerDialectValue.displayName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .contextMenu {
                    Button(String(localized: "Edit Model")) {
                        viewModel.beginEditingModel(model)
                    }
                    if !model.isDefault {
                        Button(String(localized: "Set Default")) {
                            Task { await viewModel.setDefaultModel(model.id) }
                        }
                    }
                    Button(String(localized: "Delete"), role: .destructive) {
                        Task { await viewModel.deleteModel(model.id) }
                    }
                }
            }
            .onDelete { indexSet in
                Task {
                    for index in indexSet {
                        await viewModel.deleteModel(viewModel.models[index].id)
                    }
                }
            }

            if let errorMessage = viewModel.modelFetchError {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button(String(localized: "Add Model")) {
                    viewModel.isShowingAddModel = true
                }

                Spacer()

                if viewModel.isFetchingModels {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button(String(localized: "Refresh")) {
                        Task { await viewModel.fetchAndMergeModels() }
                    }
                    .font(.footnote)
                }
            }
        }
    }

    // MARK: - Add Model Sheet

    private var addModelSheet: some View {
        NavigationStack {
            Form {
                TextField(String(localized: "Model Name"), text: bind(\.newModelId))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                HStack {
                    Text(String(localized: "Max Context Tokens"))
                    Spacer()
                    TextField("", text: newModelMaxContextBinding)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 120)
                }

                Picker(String(localized: "Provider"), selection: bind(\.newModelProviderDialect)) {
                    ForEach(APIProviderDialect.allCases) { dialect in
                        Text(dialect.displayName).tag(dialect)
                    }
                }

                Picker(String(localized: "API Mode"), selection: bind(\.newModelApiMode)) {
                    Text("Chat Completions").tag(APIMode.chatCompletions)
                    Text("Responses").tag(APIMode.responses)
                }
                .disabled(viewModel.newModelProviderDialect == .deepSeekV4)
            }
            .navigationTitle(String(localized: "Add Model"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "Cancel")) {
                        viewModel.isShowingAddModel = false
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "Add")) {
                        Task { await viewModel.addManualModel() }
                    }
                    .disabled(!viewModel.isAddModelValid)
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Edit Model Sheet

    private var editModelSheet: some View {
        NavigationStack {
            Form {
                if let model = viewModel.editingModel {
                    LabeledContent(String(localized: "Model Name")) {
                        Text(model.modelId)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                HStack {
                    Text(String(localized: "Max Context Tokens"))
                    Spacer()
                    TextField("", text: editModelMaxContextBinding)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 120)
                }

                Picker(String(localized: "Provider"), selection: bind(\.editModelProviderDialect)) {
                    ForEach(APIProviderDialect.allCases) { dialect in
                        Text(dialect.displayName).tag(dialect)
                    }
                }

                Picker(String(localized: "API Mode"), selection: bind(\.editModelApiMode)) {
                    Text("Chat Completions").tag(APIMode.chatCompletions)
                    Text("Responses").tag(APIMode.responses)
                }
                .disabled(viewModel.editModelProviderDialect == .deepSeekV4)
            }
            .navigationTitle(String(localized: "Edit Model"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "Cancel")) {
                        viewModel.cancelEditingModel()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "Save")) {
                        Task { await viewModel.saveEditedModel() }
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Helpers

    private var newModelMaxContextBinding: Binding<String> {
        Binding(
            get: { String(viewModel.newModelMaxContext) },
            set: { newValue in
                let filtered = newValue.filter(\.isWholeNumber)
                if let value = Int(filtered) {
                    viewModel.newModelMaxContext = min(max(value, 1), 2_000_000)
                }
            }
        )
    }

    private var editModelMaxContextBinding: Binding<String> {
        Binding(
            get: { String(viewModel.editModelMaxContext) },
            set: { newValue in
                let filtered = newValue.filter(\.isWholeNumber)
                if let value = Int(filtered) {
                    viewModel.editModelMaxContext = min(max(value, 1), 2_000_000)
                }
            }
        )
    }

    private func bind<Value>(_ keyPath: ReferenceWritableKeyPath<APIEndpointEditorViewModel, Value>) -> Binding<Value> {
        @Bindable var viewModel = viewModel
        return Binding(
            get: { viewModel[keyPath: keyPath] },
            set: { viewModel[keyPath: keyPath] = $0 }
        )
    }
}
