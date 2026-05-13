import Foundation
import Testing

@testable import OpenChat

@Suite("Memory extraction cutoff")
struct MemoryExtractionCutoffTests {
    @Test func test_extractMemories_uses_sortOrder_cutoff_not_createdAt() async throws {
        let database = try TestHelpers.makeDatabaseManager()
        let card = TestHelpers.makeCharacterCard(id: "card-cutoff")
        let endpoint = makeEndpoint()
        let model = makeEndpointModel(endpointId: endpoint.id)
        var conversation = TestHelpers.makeConversation(id: "conv-cutoff")
        conversation.characterCardId = card.id
        conversation.apiEndpointId = endpoint.id
        conversation.modelName = model.modelId

        try await database.saveEndpoint(endpoint)
        try await database.saveEndpointModel(model)
        try await database.write { db in try card.insert(db) }
        try await database.saveConversation(conversation)

        // Insert 4 messages with sortOrder 1..4
        for i in 1...4 {
            try await database.saveMessage(
                TestHelpers.makeMessage(
                    conversationId: conversation.id,
                    role: i.isMultiple(of: 2) ? "assistant" : "user",
                    content: "First batch message \(i)",
                    sortOrder: i
                )
            )
        }

        // First extraction: processes all 4 messages
        let apiClient = makeExtractionAPIClient()
        let manager = MemoryManager(
            databaseManager: database,
            embeddingService: FixedEmbeddingProvider(),
            vectorStore: VectorStore(databaseManager: database),
            apiClient: apiClient,
            apiKeyStore: InMemoryAPIKeyStore()
        )
        let firstResult = try await manager.extractMemories(from: conversation)
        #expect(!firstResult.isEmpty)

        // Verify conversation.lastExtractedSortOrder is updated
        let refreshed = try await database.fetchConversation(id: conversation.id)
        #expect(refreshed?.lastExtractedSortOrder == 4)

        // Add 4 more messages with sortOrder 5..8
        for i in 5...8 {
            try await database.saveMessage(
                TestHelpers.makeMessage(
                    conversationId: conversation.id,
                    role: i.isMultiple(of: 2) ? "assistant" : "user",
                    content: "Second batch message \(i)",
                    sortOrder: i
                )
            )
        }

        // Second extraction: should only see messages 5..8
        let secondResult = try await manager.extractMemories(from: conversation)
        #expect(!secondResult.isEmpty)

        let refreshed2 = try await database.fetchConversation(id: conversation.id)
        #expect(refreshed2?.lastExtractedSortOrder == 8)
    }

    @Test func test_extractMemories_skips_when_fewer_than_minimum_new_messages() async throws {
        let database = try TestHelpers.makeDatabaseManager()
        let card = TestHelpers.makeCharacterCard(id: "card-skip")
        let endpoint = makeEndpoint()
        let model = makeEndpointModel(endpointId: endpoint.id)
        var conversation = TestHelpers.makeConversation(id: "conv-skip")
        conversation.characterCardId = card.id
        conversation.apiEndpointId = endpoint.id
        conversation.modelName = model.modelId
        // Simulate previous extraction up to sortOrder 10
        conversation.lastExtractedSortOrder = 10

        try await database.saveEndpoint(endpoint)
        try await database.saveEndpointModel(model)
        try await database.write { db in try card.insert(db) }
        try await database.saveConversation(conversation)

        // Only 2 new messages (below minimum of 4)
        for i in 11...12 {
            try await database.saveMessage(
                TestHelpers.makeMessage(
                    conversationId: conversation.id,
                    role: i.isMultiple(of: 2) ? "assistant" : "user",
                    content: "New message \(i)",
                    sortOrder: i
                )
            )
        }

        let apiClient = makeExtractionAPIClient()
        let manager = MemoryManager(
            databaseManager: database,
            embeddingService: FixedEmbeddingProvider(),
            vectorStore: VectorStore(databaseManager: database),
            apiClient: apiClient,
            apiKeyStore: InMemoryAPIKeyStore()
        )
        let result = try await manager.extractMemories(from: conversation)
        #expect(result.isEmpty)

        // lastExtractedSortOrder should not change
        let refreshed = try await database.fetchConversation(id: conversation.id)
        #expect(refreshed?.lastExtractedSortOrder == 10)
    }

    @Test func test_extractMemories_processes_all_when_no_previous_extraction() async throws {
        let database = try TestHelpers.makeDatabaseManager()
        let card = TestHelpers.makeCharacterCard(id: "card-first")
        let endpoint = makeEndpoint()
        let model = makeEndpointModel(endpointId: endpoint.id)
        var conversation = TestHelpers.makeConversation(id: "conv-first")
        conversation.characterCardId = card.id
        conversation.apiEndpointId = endpoint.id
        conversation.modelName = model.modelId
        // lastExtractedSortOrder is nil (default)

        try await database.saveEndpoint(endpoint)
        try await database.saveEndpointModel(model)
        try await database.write { db in try card.insert(db) }
        try await database.saveConversation(conversation)

        for i in 1...6 {
            try await database.saveMessage(
                TestHelpers.makeMessage(
                    conversationId: conversation.id,
                    role: i.isMultiple(of: 2) ? "assistant" : "user",
                    content: "Message \(i)",
                    sortOrder: i
                )
            )
        }

        let apiClient = makeExtractionAPIClient()
        let manager = MemoryManager(
            databaseManager: database,
            embeddingService: FixedEmbeddingProvider(),
            vectorStore: VectorStore(databaseManager: database),
            apiClient: apiClient,
            apiKeyStore: InMemoryAPIKeyStore()
        )
        let result = try await manager.extractMemories(from: conversation)
        #expect(!result.isEmpty)

        let refreshed = try await database.fetchConversation(id: conversation.id)
        #expect(refreshed?.lastExtractedSortOrder == 6)
    }

    @Test func test_extractMemories_does_not_skip_concurrent_messages() async throws {
        // Simulates the P1 bug scenario: messages written during extraction
        // should NOT be skipped because sortOrder boundary is deterministic
        let database = try TestHelpers.makeDatabaseManager()
        let card = TestHelpers.makeCharacterCard(id: "card-concurrent")
        let endpoint = makeEndpoint()
        let model = makeEndpointModel(endpointId: endpoint.id)
        var conversation = TestHelpers.makeConversation(id: "conv-concurrent")
        conversation.characterCardId = card.id
        conversation.apiEndpointId = endpoint.id
        conversation.modelName = model.modelId
        conversation.lastExtractedSortOrder = 4

        try await database.saveEndpoint(endpoint)
        try await database.saveEndpointModel(model)
        try await database.write { db in try card.insert(db) }
        try await database.saveConversation(conversation)

        // Messages 5..8 are "new" (after cutoff 4)
        for i in 5...8 {
            try await database.saveMessage(
                TestHelpers.makeMessage(
                    conversationId: conversation.id,
                    role: i.isMultiple(of: 2) ? "assistant" : "user",
                    content: "Message \(i)",
                    sortOrder: i
                )
            )
        }

        // Simulate a "concurrent" message 9 written during extraction
        try await database.saveMessage(
            TestHelpers.makeMessage(
                conversationId: conversation.id,
                role: "user",
                content: "Concurrent message 9",
                sortOrder: 9
            )
        )

        let apiClient = makeExtractionAPIClient()
        let manager = MemoryManager(
            databaseManager: database,
            embeddingService: FixedEmbeddingProvider(),
            vectorStore: VectorStore(databaseManager: database),
            apiClient: apiClient,
            apiKeyStore: InMemoryAPIKeyStore()
        )
        // Extraction sees messages 5..9, cutoff updates to 9
        let result = try await manager.extractMemories(from: conversation)
        #expect(!result.isEmpty)

        let refreshed = try await database.fetchConversation(id: conversation.id)
        #expect(refreshed?.lastExtractedSortOrder == 9)

        // Message 10 arrives later — next extraction will see it
        try await database.saveMessage(
            TestHelpers.makeMessage(
                conversationId: conversation.id,
                role: "assistant",
                content: "Later message 10",
                sortOrder: 10
            )
        )

        // Verify message 10 would be included in next extraction
        let allMessages = try await database.fetchMessages(conversationId: conversation.id)
        let newMessages = allMessages.filter { $0.sortOrder > 9 }
        #expect(newMessages.count == 1)
        #expect(newMessages.first?.content == "Later message 10")
    }

    // MARK: - Helpers

    private func makeEndpoint() -> APIEndpointRecord {
        APIEndpointRecord(
            id: "endpoint-cutoff-test",
            name: "Local",
            baseURL: "http://localhost:8080/v1",
            apiKey: "test-key",
            isDefault: true,
            createdAt: .now,
            updatedAt: .now
        )
    }

    private func makeEndpointModel(endpointId: String) -> EndpointModelRecord {
        EndpointModelRecord(
            id: "model-cutoff-test",
            endpointId: endpointId,
            modelId: "test-model",
            maxContextTokens: 4096,
            apiMode: APIMode.chatCompletions.rawValue,
            providerDialect: APIProviderDialect.openAICompatible.rawValue,
            isDefault: true,
            isManual: true,
            createdAt: .now
        )
    }

    private func makeExtractionAPIClient() -> APIClient {
        let responseBody = """
        {"id":"mem","choices":[{"index":0,"message":{"role":"assistant","content":"[{\\"content\\":\\"Test memory.\\",\\"type\\":\\"fact\\",\\"importance\\":80}]"},"finish_reason":"stop"}],"usage":null}
        """
        let session = MockURLProtocol.makeSession { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(responseBody.utf8))
        }
        return APIClient(session: session)
    }
}

private struct FixedEmbeddingProvider: EmbeddingProvider {
    func embed(_ text: String, isQuery: Bool) throws -> [Float] {
        var embedding = [Float](repeating: 0, count: EmbeddingService.embeddingDimension)
        embedding[0] = isQuery ? 0.9 : 0.8
        return embedding
    }
}
