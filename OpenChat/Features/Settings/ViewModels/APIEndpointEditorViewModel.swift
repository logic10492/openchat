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
    private let apiKeyStore: any APIKeyStore

    // MARK: - Endpoint fields
    var name = ""
    var baseURL = ""
    var apiKey = ""
    var isDefault = false
    private(set) var hasStoredAPIKey = false
    private(set) var isSaving = false
    var errorMessage: String?
    private var shouldDeleteStoredKey = false
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
    var newModelProviderDialect: APIProviderDialect = .openAICompatible

    // MARK: - Edit model sheet state
    var isShowingEditModel = false
    var editingModel: EndpointModelRecord?
    var editModelMaxContext = AppConstants.defaultMaxContextTokens
    var editModelApiMode: APIMode = .chatCompletions
    var editModelProviderDialect: APIProviderDialect = .openAICompatible

    init(
        databaseManager: DatabaseManager,
        apiClient: APIClient,
        apiKeyStore: any APIKeyStore = KeychainAPIKeyStore(),
        editingEndpoint: APIEndpointRecord? = nil
    ) {
        self.databaseManager = databaseManager
        self.apiClient = apiClient
        self.apiKeyStore = apiKeyStore
        self.editingEndpoint = editingEndpoint

        if let editingEndpoint {
            name = editingEndpoint.name
            baseURL = editingEndpoint.baseURL
            isDefault = editingEndpoint.isDefault
            hasStoredAPIKey = ((try? apiKeyStore.readKey(endpointId: editingEndpoint.id)) ?? nil) != nil ||
                editingEndpoint.apiKey?.nilIfBlank != nil
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
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let now = Date()
            let record = APIEndpointRecord(
                id: editingEndpoint?.id ?? UUID().uuidString,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                baseURL: baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
                apiKey: nil,
                isDefault: isDefault,
                createdAt: editingEndpoint?.createdAt ?? now,
                updatedAt: now
            )
            try await databaseManager.saveEndpoint(record)
            try updateStoredAPIKey(afterSaving: record)

            // Ensure the endpoint has at least one model
            if models.isEmpty {
                try await databaseManager.ensureDefaultModel(endpointId: record.id)
                models = try await databaseManager.fetchEndpointModels(endpointId: record.id)
            }

            return record
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func clearStoredAPIKey() {
        apiKey = ""
        hasStoredAPIKey = false
        shouldDeleteStoredKey = true
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
                apiKey: try resolvedAPIKeyForRequest(),
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
            let fetched = try await apiClient.fetchModels(baseURL: url, apiKey: try resolvedAPIKeyForRequest())
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
                do {
                    try await databaseManager.ensureDefaultModel(endpointId: endpointId)
                    models = try await databaseManager.fetchEndpointModels(endpointId: endpointId)
                } catch {
                    modelFetchError = error.localizedDescription
                }
            }
        }

        isFetchingModels = false
    }

    // MARK: - Model CRUD

    func addManualModel() async {
        guard let endpointId = editingEndpoint?.id, isAddModelValid else { return }

        let resolvedApiMode: APIMode = newModelProviderDialect == .deepSeekV4 ? .chatCompletions : newModelApiMode
        let resolvedContext = newModelProviderDialect == .deepSeekV4
            ? max(newModelMaxContext, 1_000_000)
            : newModelMaxContext

        let record = EndpointModelRecord(
            id: UUID().uuidString,
            endpointId: endpointId,
            modelId: newModelId.trimmingCharacters(in: .whitespacesAndNewlines),
            maxContextTokens: resolvedContext,
            apiMode: resolvedApiMode.rawValue,
            providerDialect: newModelProviderDialect.rawValue,
            isDefault: models.isEmpty,
            isManual: true,
            createdAt: Date()
        )

        do {
            try await databaseManager.saveEndpointModel(record)
            models = try await databaseManager.fetchEndpointModels(endpointId: endpointId)
        } catch {
            errorMessage = error.localizedDescription
        }

        // Reset add-model form
        newModelId = ""
        newModelMaxContext = AppConstants.defaultMaxContextTokens
        newModelApiMode = .chatCompletions
        newModelProviderDialect = .openAICompatible
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
            errorMessage = error.localizedDescription
        }
    }

    func setDefaultModel(_ id: String) async {
        guard let endpointId = editingEndpoint?.id else { return }
        do {
            try await databaseManager.setDefaultEndpointModel(id: id, endpointId: endpointId)
            models = try await databaseManager.fetchEndpointModels(endpointId: endpointId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func beginEditingModel(_ model: EndpointModelRecord) {
        editingModel = model
        editModelMaxContext = model.maxContextTokens
        editModelApiMode = model.apiModeValue
        editModelProviderDialect = model.providerDialectValue
        isShowingEditModel = true
    }

    func saveEditedModel() async {
        guard var model = editingModel else { return }
        model.providerDialectValue = editModelProviderDialect
        if editModelProviderDialect == .deepSeekV4 {
            model.apiModeValue = .chatCompletions
            model.maxContextTokens = max(editModelMaxContext, 1_000_000)
        } else {
            model.apiModeValue = editModelApiMode
            model.maxContextTokens = editModelMaxContext
        }
        model.isManual = true

        do {
            try await databaseManager.saveEndpointModel(model)
            models = try await databaseManager.fetchEndpointModels(endpointId: model.endpointId)
            resetEditModelForm()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cancelEditingModel() {
        resetEditModelForm()
    }

    private func resetEditModelForm() {
        editingModel = nil
        editModelMaxContext = AppConstants.defaultMaxContextTokens
        editModelApiMode = .chatCompletions
        editModelProviderDialect = .openAICompatible
        isShowingEditModel = false
    }

    private func updateStoredAPIKey(afterSaving record: APIEndpointRecord) throws {
        if shouldDeleteStoredKey {
            try apiKeyStore.deleteKey(endpointId: record.id)
            hasStoredAPIKey = false
            return
        }

        if let newKey = apiKey.nilIfBlank {
            try apiKeyStore.saveKey(newKey, endpointId: record.id)
            apiKey = ""
            hasStoredAPIKey = true
            return
        }

        if let legacyKey = editingEndpoint?.apiKey?.nilIfBlank,
           try apiKeyStore.readKey(endpointId: record.id) == nil {
            try apiKeyStore.saveKey(legacyKey, endpointId: record.id)
            hasStoredAPIKey = true
        }
    }

    private func resolvedAPIKeyForRequest() throws -> String? {
        if let typedKey = apiKey.nilIfBlank {
            return typedKey
        }
        guard let endpointId = editingEndpoint?.id else {
            return nil
        }
        return try apiKeyStore.readKey(endpointId: endpointId) ?? editingEndpoint?.apiKey?.nilIfBlank
    }
}
