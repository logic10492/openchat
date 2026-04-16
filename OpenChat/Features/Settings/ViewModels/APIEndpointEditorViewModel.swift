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

    var name = ""
    var baseURL = ""
    var apiKey = ""
    var modelName = AppConstants.defaultModelName
    var maxContextTokens = AppConstants.defaultMaxContextTokens
    var isDefault = false
    var apiMode: APIMode = .chatCompletions
    private(set) var testResult: TestResult?
    var fetchedModels: [ModelObject] = []
    var availableModels: [String] { fetchedModels.map(\.id) }
    private(set) var isFetchingModels = false
    private(set) var modelFetchError: String?
    var contextLengthAutoDetected = false
    var isCustomModelInput = false
    let editingEndpoint: APIEndpointRecord?
    private var fetchModelsTask: Task<Void, Never>?

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
            modelName = editingEndpoint.modelName
            maxContextTokens = editingEndpoint.maxContextTokens
            isDefault = editingEndpoint.isDefault
            apiMode = editingEndpoint.apiModeValue
        }
    }

    var isValid: Bool {
        name.nilIfBlank != nil &&
            URL(string: baseURL) != nil &&
            modelName.nilIfBlank != nil
    }

    func save() async throws -> APIEndpointRecord {
        let now = Date()
        let record = APIEndpointRecord(
            id: editingEndpoint?.id ?? UUID().uuidString,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            baseURL: baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
            apiKey: apiKey.nilIfBlank,
            modelName: modelName.trimmingCharacters(in: .whitespacesAndNewlines),
            maxContextTokens: maxContextTokens,
            isDefault: isDefault,
            apiMode: apiMode.rawValue,
            createdAt: editingEndpoint?.createdAt ?? now,
            updatedAt: now
        )
        try await databaseManager.saveEndpoint(record)
        return record
    }

    func testConnection() async {
        testResult = .testing
        do {
            guard let url = URL(string: baseURL) else {
                testResult = .failure(String(localized: "Base URL is invalid."))
                return
            }

            let config = APIEndpointConfig(
                baseURL: url,
                apiKey: apiKey.nilIfBlank,
                modelName: modelName,
                maxContextTokens: maxContextTokens,
                apiMode: apiMode
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

    func scheduleFetchModels() {
        fetchModelsTask?.cancel()
        fetchModelsTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await fetchAvailableModels()
        }
    }

    func applyContextLength(for modelID: String) {
        guard let model = fetchedModels.first(where: { $0.id == modelID }),
              let length = model.contextLength else {
            contextLengthAutoDetected = false
            return
        }
        maxContextTokens = length
        contextLengthAutoDetected = true
    }

    func fetchAvailableModels() async {
        guard let url = URL(string: baseURL), !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            fetchedModels = []
            modelFetchError = nil
            return
        }

        isFetchingModels = true
        modelFetchError = nil

        do {
            let models = try await apiClient.fetchModels(baseURL: url, apiKey: apiKey.nilIfBlank)
            fetchedModels = models
            if !fetchedModels.isEmpty && modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                modelName = fetchedModels[0].id
            }
            applyContextLength(for: modelName)
            isCustomModelInput = false
        } catch {
            guard !Task.isCancelled else { return }
            fetchedModels = []
            modelFetchError = error.localizedDescription
        }

        isFetchingModels = false
    }
}
