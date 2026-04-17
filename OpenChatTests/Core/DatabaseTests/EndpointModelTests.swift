import Foundation
import GRDB
import Testing

@testable import OpenChat

@Suite("DatabaseManager+EndpointModels")
struct EndpointModelTests {
    private func makeEndpointAndManager() async throws -> (DatabaseManager, APIEndpointRecord) {
        let manager = try TestHelpers.makeDatabaseManager()
        let now = Date()
        let endpoint = APIEndpointRecord(
            id: UUID().uuidString,
            name: "Test Endpoint",
            baseURL: "http://localhost:8080/v1",
            apiKey: nil,
            isDefault: true,
            createdAt: now,
            updatedAt: now
        )
        try await manager.saveEndpoint(endpoint)
        return (manager, endpoint)
    }

    @Test func test_save_and_fetch_models() async throws {
        let (manager, endpoint) = try await makeEndpointAndManager()
        let model = EndpointModelRecord(
            id: UUID().uuidString,
            endpointId: endpoint.id,
            modelId: "gpt-4o",
            maxContextTokens: 128_000,
            apiMode: "chatCompletions",
            isDefault: true,
            isManual: false,
            createdAt: .now
        )
        try await manager.saveEndpointModel(model)

        let models = try await manager.fetchEndpointModels(endpointId: endpoint.id)
        #expect(models.count == 1)
        #expect(models[0].modelId == "gpt-4o")
        #expect(models[0].maxContextTokens == 128_000)
        #expect(models[0].isDefault == true)
    }

    @Test func test_fetch_default_model() async throws {
        let (manager, endpoint) = try await makeEndpointAndManager()
        let m1 = EndpointModelRecord(
            id: UUID().uuidString, endpointId: endpoint.id, modelId: "model-a",
            maxContextTokens: 4096, apiMode: "chatCompletions",
            isDefault: false, isManual: false, createdAt: .now
        )
        let m2 = EndpointModelRecord(
            id: UUID().uuidString, endpointId: endpoint.id, modelId: "model-b",
            maxContextTokens: 8192, apiMode: "responses",
            isDefault: true, isManual: false, createdAt: .now
        )
        try await manager.saveEndpointModel(m1)
        try await manager.saveEndpointModel(m2)

        let defaultModel = try await manager.fetchDefaultModel(endpointId: endpoint.id)
        #expect(defaultModel?.modelId == "model-b")
    }

    @Test func test_fetch_default_model_falls_back_to_first() async throws {
        let (manager, endpoint) = try await makeEndpointAndManager()
        let m1 = EndpointModelRecord(
            id: UUID().uuidString, endpointId: endpoint.id, modelId: "only-model",
            maxContextTokens: 4096, apiMode: "chatCompletions",
            isDefault: false, isManual: false, createdAt: .now
        )
        try await manager.saveEndpointModel(m1)

        let result = try await manager.fetchDefaultModel(endpointId: endpoint.id)
        #expect(result?.modelId == "only-model")
    }

    @Test func test_set_default_model_unsets_others() async throws {
        let (manager, endpoint) = try await makeEndpointAndManager()
        let m1 = EndpointModelRecord(
            id: "m1", endpointId: endpoint.id, modelId: "model-a",
            maxContextTokens: 4096, apiMode: "chatCompletions",
            isDefault: true, isManual: false, createdAt: .now
        )
        let m2 = EndpointModelRecord(
            id: "m2", endpointId: endpoint.id, modelId: "model-b",
            maxContextTokens: 8192, apiMode: "chatCompletions",
            isDefault: false, isManual: false, createdAt: .now
        )
        try await manager.saveEndpointModel(m1)
        try await manager.saveEndpointModel(m2)

        try await manager.setDefaultEndpointModel(id: "m2", endpointId: endpoint.id)

        let models = try await manager.fetchEndpointModels(endpointId: endpoint.id)
        let defaultModels = models.filter(\.isDefault)
        #expect(defaultModels.count == 1)
        #expect(defaultModels[0].id == "m2")
    }

    @Test func test_delete_model() async throws {
        let (manager, endpoint) = try await makeEndpointAndManager()
        let model = EndpointModelRecord(
            id: "m1", endpointId: endpoint.id, modelId: "to-delete",
            maxContextTokens: 4096, apiMode: "chatCompletions",
            isDefault: true, isManual: false, createdAt: .now
        )
        try await manager.saveEndpointModel(model)
        try await manager.deleteEndpointModel(id: "m1")

        let models = try await manager.fetchEndpointModels(endpointId: endpoint.id)
        #expect(models.isEmpty)
    }

    @Test func test_ensure_default_model_inserts_when_empty() async throws {
        let (manager, endpoint) = try await makeEndpointAndManager()
        let modelsBefore = try await manager.fetchEndpointModels(endpointId: endpoint.id)
        #expect(modelsBefore.isEmpty)

        try await manager.ensureDefaultModel(endpointId: endpoint.id)

        let modelsAfter = try await manager.fetchEndpointModels(endpointId: endpoint.id)
        #expect(modelsAfter.count == 1)
        #expect(modelsAfter[0].modelId == "default")
        #expect(modelsAfter[0].isDefault == true)
        #expect(modelsAfter[0].isManual == true)
    }

    @Test func test_ensure_default_model_noop_when_has_models() async throws {
        let (manager, endpoint) = try await makeEndpointAndManager()
        let existing = EndpointModelRecord(
            id: UUID().uuidString, endpointId: endpoint.id, modelId: "existing",
            maxContextTokens: 4096, apiMode: "chatCompletions",
            isDefault: true, isManual: false, createdAt: .now
        )
        try await manager.saveEndpointModel(existing)
        try await manager.ensureDefaultModel(endpointId: endpoint.id)

        let models = try await manager.fetchEndpointModels(endpointId: endpoint.id)
        #expect(models.count == 1)
        #expect(models[0].modelId == "existing")
    }

    @Test func test_fetch_endpoint_model_by_model_id() async throws {
        let (manager, endpoint) = try await makeEndpointAndManager()
        let model = EndpointModelRecord(
            id: UUID().uuidString, endpointId: endpoint.id, modelId: "gpt-4o-mini",
            maxContextTokens: 128_000, apiMode: "chatCompletions",
            isDefault: true, isManual: false, createdAt: .now
        )
        try await manager.saveEndpointModel(model)

        let found = try await manager.fetchEndpointModel(endpointId: endpoint.id, modelId: "gpt-4o-mini")
        #expect(found != nil)
        #expect(found?.maxContextTokens == 128_000)

        let notFound = try await manager.fetchEndpointModel(endpointId: endpoint.id, modelId: "nonexistent")
        #expect(notFound == nil)
    }

    @Test func test_upsert_fetched_models_adds_new() async throws {
        let (manager, endpoint) = try await makeEndpointAndManager()

        let apiModels = [
            ModelObject(id: "llama-3", object: "model", ownedBy: "meta", contextLength: 8192),
            ModelObject(id: "gpt-4o", object: "model", ownedBy: "openai", contextLength: 128_000),
        ]
        try await manager.upsertFetchedModels(endpointId: endpoint.id, models: apiModels)

        let models = try await manager.fetchEndpointModels(endpointId: endpoint.id)
        #expect(models.count == 2)
        let ids = Set(models.map(\.modelId))
        #expect(ids.contains("llama-3"))
        #expect(ids.contains("gpt-4o"))

        // First one should be default
        let defaultModel = models.first(where: { $0.isDefault })
        #expect(defaultModel != nil)
    }

    @Test func test_upsert_preserves_manual_entries() async throws {
        let (manager, endpoint) = try await makeEndpointAndManager()

        // Add a manual model
        let manual = EndpointModelRecord(
            id: UUID().uuidString, endpointId: endpoint.id, modelId: "my-custom-model",
            maxContextTokens: 4096, apiMode: "chatCompletions",
            isDefault: true, isManual: true, createdAt: .now
        )
        try await manager.saveEndpointModel(manual)

        // Upsert API models (not including the manual one)
        let apiModels = [
            ModelObject(id: "llama-3", object: "model", ownedBy: "meta", contextLength: 8192),
        ]
        try await manager.upsertFetchedModels(endpointId: endpoint.id, models: apiModels)

        let models = try await manager.fetchEndpointModels(endpointId: endpoint.id)
        let ids = Set(models.map(\.modelId))
        #expect(ids.contains("my-custom-model"))
        #expect(ids.contains("llama-3"))
    }
}
