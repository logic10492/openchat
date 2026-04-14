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
    private(set) var testResult: TestResult?
    let editingEndpoint: APIEndpointRecord?

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
                maxContextTokens: maxContextTokens
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
}
