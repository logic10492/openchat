import Foundation
import Observation

@MainActor
@Observable
final class APIEndpointEditorViewModel {
    enum TestResult: Equatable {
        case testing
        case success(String)
        case failure(String)
    }

    private let databaseManager: DatabaseManager
    private let apiClient: APIClient

    // MARK: - Endpoint fields
    var name = ""
    var baseURL = ""
    var apiKey = ""
    var isDefault = false
    private(set) var testResult: TestResult?

    let editingEndpoint: APIEndpointRecord?

    // MARK: - Model list management
    var models: [EndpointModelRecord] = []
    var fetchedAPIModels: [ModelObject] = []
    private(set) var isFetchingModels = false
    private(set) var modelFetchError: String?
    private var fetchModelsTask: Task<Void, Never>?

    // MARK: - Add model sheet state
    var isShowingAddModel = false
    var newModelId = ""
    var newModelMaxContext = AppConstants.defaultMaxContextTokens
    var newModelApiMode: APIMode = .chatCompletions

    // MARK: - Edit model sheet state
    var isShowingEditModel = false
    var editingModel: EndpointModelRecord?
    var editModelMaxContext = AppConstants.defaultMaxContextTokens
    var editModelApiMode: APIMode = .chatCompletions

    init(
        databaseManager: DatabaseManager,
        apiClient: APIClient,
        editingEndpoint: APIEndpointRecord? = nil
    ) {
        self.databaseManager = databaseManager
        self.apiClient = apiClient
        self.editingEndpoint = editingEndpoint

        if let editingEndpoint {
            name = editingEndpoint.name
            baseURL = editingEndpoint.baseURL
            apiKey = editingEndpoint.apiKey ?? ""
            isDefault = editingEndpoint.isDefault
        }
    }

    var isValid: Bool {
        name.nilIfBlank != nil &&
            URL(string: baseURL) != nil
    }

    var isAddModelValid: Bool {
        newModelId.nilIfBlank != nil
    }

    // MARK: - Endpoint persistence

    func save() async throws -> APIEndpointRecord {
        let now = Date()
        let record = APIEndpointRecord(
            id: editingEndpoint?.id ?? UUID().uuidString,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            baseURL: baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
            apiKey: apiKey.nilIfBlank,
            isDefault: isDefault,
            createdAt: editingEndpoint?.createdAt ?? now,
            updatedAt: now
        )
        try await databaseManager.saveEndpoint(record)

        // Ensure the endpoint has at least one model
        if models.isEmpty {
            try await databaseManager.ensureDefaultModel(endpointId: record.id)
            models = try await databaseManager.fetchEndpointModels(endpointId: record.id)
        }

        return record
    }

    // MARK: - Connection test

    func testConnection() async {
        testResult = .testing
        do {
            guard let url = URL(string: baseURL) else {
                testResult = .failure(String(localized: "Base URL is invalid."))
                return
            }

            // Use default model for test, or a placeholder
            let defaultModel = models.first(where: { $0.isDefault }) ?? models.first
            let modelName = defaultModel?.modelId ?? "default"
            let maxCtx = defaultModel?.maxContextTokens ?? AppConstants.defaultMaxContextTokens
            let apiMode = defaultModel?.apiModeValue ?? .chatCompletions
            let providerDialect = defaultModel?.providerDialectValue ?? .openAICompatible

            let config = APIEndpointConfig(
                baseURL: url,
                apiKey: apiKey.nilIfBlank,
                modelName: modelName,
                maxContextTokens: maxCtx,
                apiMode: apiMode,
                providerDialect: providerDialect
            )

            _ = try await apiClient.sendMessage(
                messages: [ChatMessage(role: "user", content: "Hi")],
                endpoint: config,
                parameters: ModelParameters(maxTokens: 1)
            )
            testResult = .success(String(localized: "Connection succeeded."))
        } catch {
            testResult = .failure(error.localizedDescription)
        }
    }

    // MARK: - Model list loading

    func loadModels() async {
        guard let endpointId = editingEndpoint?.id else { return }
        do {
            models = try await databaseManager.fetchEndpointModels(endpointId: endpointId)
        } catch {
            models = []
        }
    }

    // MARK: - Fetch models from API

    func scheduleFetchModels() {
        fetchModelsTask?.cancel()
        fetchModelsTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await fetchAndMergeModels()
        }
    }

    func fetchAndMergeModels() async {
        guard let url = URL(string: baseURL), !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            fetchedAPIModels = []
            modelFetchError = nil
            return
        }

        isFetchingModels = true
        modelFetchError = nil

        do {
            let fetched = try await apiClient.fetchModels(baseURL: url, apiKey: apiKey.nilIfBlank)
            fetchedAPIModels = fetched

            // If endpoint is already saved, persist models to DB
            if let endpointId = editingEndpoint?.id {
                try await databaseManager.upsertFetchedModels(endpointId: endpointId, models: fetched)
                models = try await databaseManager.fetchEndpointModels(endpointId: endpointId)

                // If still empty after fetch, insert "default"
                if models.isEmpty {
                    try await databaseManager.ensureDefaultModel(endpointId: endpointId)
                    models = try await databaseManager.fetchEndpointModels(endpointId: endpointId)
                }
            }
        } catch {
            guard !Task.isCancelled else { return }
            fetchedAPIModels = []
            modelFetchError = error.localizedDescription

            // On fetch failure, ensure there's at least a "default" model
            if let endpointId = editingEndpoint?.id, models.isEmpty {
                try? await databaseManager.ensureDefaultModel(endpointId: endpointId)
                models = (try? await databaseManager.fetchEndpointModels(endpointId: endpointId)) ?? []
            }
        }

        isFetchingModels = false
    }

    // MARK: - Model CRUD

    func addManualModel() async {
        guard let endpointId = editingEndpoint?.id, isAddModelValid else { return }

        let record = EndpointModelRecord(
            id: UUID().uuidString,
            endpointId: endpointId,
            modelId: newModelId.trimmingCharacters(in: .whitespacesAndNewlines),
            maxContextTokens: newModelMaxContext,
            apiMode: newModelApiMode.rawValue,
            providerDialect: APIProviderDialect.openAICompatible.rawValue,
            isDefault: models.isEmpty,
            isManual: true,
            createdAt: Date()
        )

        do {
            try await databaseManager.saveEndpointModel(record)
            models = try await databaseManager.fetchEndpointModels(endpointId: endpointId)
        } catch {
            // Duplicate model — silently ignore
        }

        // Reset add-model form
        newModelId = ""
        newModelMaxContext = AppConstants.defaultMaxContextTokens
        newModelApiMode = .chatCompletions
        isShowingAddModel = false
    }

    func deleteModel(_ id: String) async {
        guard let endpointId = editingEndpoint?.id else { return }
        do {
            try await databaseManager.deleteEndpointModel(id: id)
            models = try await databaseManager.fetchEndpointModels(endpointId: endpointId)
            // Ensure at least one model remains
            if models.isEmpty {
                try await databaseManager.ensureDefaultModel(endpointId: endpointId)
                models = try await databaseManager.fetchEndpointModels(endpointId: endpointId)
            }
        } catch {
            // ignore
        }
    }

    func setDefaultModel(_ id: String) async {
        guard let endpointId = editingEndpoint?.id else { return }
        do {
            try await databaseManager.setDefaultEndpointModel(id: id, endpointId: endpointId)
            models = try await databaseManager.fetchEndpointModels(endpointId: endpointId)
        } catch {
            // ignore
        }
    }

    func beginEditingModel(_ model: EndpointModelRecord) {
        editingModel = model
        editModelMaxContext = model.maxContextTokens
        editModelApiMode = model.apiModeValue
        isShowingEditModel = true
    }

    func saveEditedModel() async {
        guard var model = editingModel else { return }
        model.maxContextTokens = editModelMaxContext
        model.apiModeValue = editModelApiMode
        model.isManual = true

        do {
            try await databaseManager.saveEndpointModel(model)
            models = try await databaseManager.fetchEndpointModels(endpointId: model.endpointId)
            resetEditModelForm()
        } catch {
            // Keep the sheet open so the user can retry.
        }
    }

    func cancelEditingModel() {
        resetEditModelForm()
    }

    private func resetEditModelForm() {
        editingModel = nil
        editModelMaxContext = AppConstants.defaultMaxContextTokens
        editModelApiMode = .chatCompletions
        isShowingEditModel = false
    }
}
