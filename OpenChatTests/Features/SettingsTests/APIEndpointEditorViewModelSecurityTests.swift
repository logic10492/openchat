import Foundation
import Testing

@testable import OpenChat

@MainActor
@Suite("API endpoint key storage")
struct APIEndpointEditorViewModelSecurityTests {
    @Test func test_save_new_endpoint_stores_key_outside_database() async throws {
        let database = try TestHelpers.makeDatabaseManager()
        let keyStore = InMemoryAPIKeyStore()
        let viewModel = APIEndpointEditorViewModel(
            databaseManager: database,
            apiClient: APIClient(),
            apiKeyStore: keyStore
        )
        viewModel.name = "Local"
        viewModel.baseURL = "http://localhost:8080/v1"
        viewModel.apiKey = "sk-secret"

        let saved = try await viewModel.save()

        let endpoint = try #require(await database.fetchEndpoint(id: saved.id))
        #expect(endpoint.apiKey == nil)
        #expect(try keyStore.readKey(endpointId: saved.id) == "sk-secret")
    }

    @Test func test_save_existing_endpoint_without_retyping_key_keeps_stored_key() async throws {
        let database = try TestHelpers.makeDatabaseManager()
        let keyStore = InMemoryAPIKeyStore()
        let now = Date()
        let endpoint = APIEndpointRecord(
            id: "endpoint-stored-key",
            name: "Local",
            baseURL: "http://localhost:8080/v1",
            apiKey: nil,
            isDefault: true,
            createdAt: now,
            updatedAt: now
        )
        try await database.saveEndpoint(endpoint)
        try keyStore.saveKey("sk-existing", endpointId: endpoint.id)

        let viewModel = APIEndpointEditorViewModel(
            databaseManager: database,
            apiClient: APIClient(),
            apiKeyStore: keyStore,
            editingEndpoint: endpoint
        )
        #expect(viewModel.apiKey.isEmpty)
        viewModel.name = "Renamed"

        _ = try await viewModel.save()

        let saved = try #require(await database.fetchEndpoint(id: endpoint.id))
        #expect(saved.name == "Renamed")
        #expect(saved.apiKey == nil)
        #expect(try keyStore.readKey(endpointId: endpoint.id) == "sk-existing")
    }

    @Test func test_clear_stored_key_removes_keychain_value() async throws {
        let database = try TestHelpers.makeDatabaseManager()
        let keyStore = InMemoryAPIKeyStore()
        let endpoint = APIEndpointRecord(
            id: "endpoint-clear-key",
            name: "Local",
            baseURL: "http://localhost:8080/v1",
            apiKey: nil,
            isDefault: true,
            createdAt: .now,
            updatedAt: .now
        )
        try await database.saveEndpoint(endpoint)
        try keyStore.saveKey("sk-existing", endpointId: endpoint.id)

        let viewModel = APIEndpointEditorViewModel(
            databaseManager: database,
            apiClient: APIClient(),
            apiKeyStore: keyStore,
            editingEndpoint: endpoint
        )
        viewModel.clearStoredAPIKey()

        _ = try await viewModel.save()

        #expect(try keyStore.readKey(endpointId: endpoint.id) == nil)
    }
}
