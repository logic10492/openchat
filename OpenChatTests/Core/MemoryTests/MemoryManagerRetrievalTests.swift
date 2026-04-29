import Foundation
import Testing

@testable import OpenChat

private struct FixedEmbeddingProvider: EmbeddingProvider {
    func embed(_ text: String, isQuery: Bool) throws -> [Float] {
        var embedding = [Float](repeating: 0, count: EmbeddingService.embeddingDimension)
        embedding[0] = isQuery ? 0.9 : 0.8
        return embedding
    }
}

private struct FailingEmbeddingProvider: EmbeddingProvider {
    func embed(_ text: String, isQuery: Bool) throws -> [Float] {
        throw MemoryError.modelLoadFailed(
            underlying: NSError(
                domain: "TestEmbedding",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "forced failure"]
            )
        )
    }
}

private final class FailingSecondEmbeddingProvider: @unchecked Sendable, EmbeddingProvider {
    private let lock = NSLock()
    private var callCount = 0

    func embed(_ text: String, isQuery: Bool) throws -> [Float] {
        lock.lock()
        callCount += 1
        let currentCall = callCount
        lock.unlock()

        if currentCall == 2 {
            return [Float](repeating: 0, count: EmbeddingService.embeddingDimension - 1)
        }

        var embedding = [Float](repeating: 0, count: EmbeddingService.embeddingDimension)
        embedding[0] = Float(currentCall)
        return embedding
    }
}

private struct EmptyVectorStore: MemoryVectorStore {
    func insert(entry: MemoryEntryRecord, embedding: [Float]) async throws {}
    func insert(entries: [(entry: MemoryEntryRecord, embedding: [Float])]) async throws {}

    func search(
        query: [Float],
        characterCardId: String,
        limit: Int
    ) async throws -> [(entryId: String, distance: Float)] {
        []
    }

    func delete(entryId: String) async throws {}
    func deleteAll(characterCardId: String) async throws {}
}

private struct FailingInsertVectorStore: MemoryVectorStore {
    func insert(entry: MemoryEntryRecord, embedding: [Float]) async throws {
        throw MemoryError.vectorStoreError(
            underlying: NSError(
                domain: "TestVectorStore",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "forced insert failure"]
            )
        )
    }

    func insert(entries: [(entry: MemoryEntryRecord, embedding: [Float])]) async throws {
        throw MemoryError.vectorStoreError(
            underlying: NSError(
                domain: "TestVectorStore",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "forced batch insert failure"]
            )
        )
    }

    func search(
        query: [Float],
        characterCardId: String,
        limit: Int
    ) async throws -> [(entryId: String, distance: Float)] {
        []
    }

    func delete(entryId: String) async throws {}
    func deleteAll(characterCardId: String) async throws {}
}

@Suite("MemoryManager retrieval")
struct MemoryManagerRetrievalTests {
    @Test func test_extractMemories_does_not_leave_memory_when_vector_insert_fails() async throws {
        let database = try TestHelpers.makeDatabaseManager()
        let card = TestHelpers.makeCharacterCard(id: "card-extraction")
        let conversation = try await makeExtractableConversation(
            database: database,
            card: card
        )
        let apiClient = makeExtractionAPIClient()
        let manager = MemoryManager(
            databaseManager: database,
            embeddingService: FixedEmbeddingProvider(),
            vectorStore: FailingInsertVectorStore(),
            apiClient: apiClient
        )

        do {
            _ = try await manager.extractMemories(from: conversation)
            Issue.record("Expected vector insert failure to abort extraction")
        } catch let error as MemoryError {
            guard case .embeddingFailed = error else {
                Issue.record("Expected MemoryError.embeddingFailed, got \(error)")
                return
            }
        } catch {
            Issue.record("Expected MemoryError.embeddingFailed, got \(error)")
        }

        let memoryCount = try await database.fetchMemoryCount(characterCardId: card.id)
        #expect(memoryCount == 0)
    }

    @Test func test_extractMemories_rolls_back_batch_when_later_embedding_is_invalid() async throws {
        let database = try TestHelpers.makeDatabaseManager()
        let card = TestHelpers.makeCharacterCard(id: "card-batch-extraction")
        let conversation = try await makeExtractableConversation(
            database: database,
            card: card
        )
        let apiClient = makeExtractionAPIClient(memoryCount: 2)
        let manager = MemoryManager(
            databaseManager: database,
            embeddingService: FailingSecondEmbeddingProvider(),
            vectorStore: VectorStore(databaseManager: database),
            apiClient: apiClient
        )

        do {
            _ = try await manager.extractMemories(from: conversation)
            Issue.record("Expected invalid second embedding to abort extraction")
        } catch let error as MemoryError {
            guard case .embeddingFailed = error else {
                Issue.record("Expected MemoryError.embeddingFailed, got \(error)")
                return
            }
        } catch {
            Issue.record("Expected MemoryError.embeddingFailed, got \(error)")
        }

        let memoryCount = try await database.fetchMemoryCount(characterCardId: card.id)
        #expect(memoryCount == 0)
    }

    @Test func test_retrieveMemories_falls_back_to_recent_memories_when_embedding_fails() async throws {
        let database = try TestHelpers.makeDatabaseManager()
        let card = TestHelpers.makeCharacterCard(id: "card-fallback")
        try await database.write { db in
            try card.insert(db)
        }
        let recent = TestHelpers.makeMemoryEntry(
            id: "recent-memory",
            characterCardId: card.id,
            content: "Ava promised to remember the silver key.",
            memoryType: .fact,
            importance: 80
        )
        try await database.saveMemory(recent)
        let manager = MemoryManager(
            databaseManager: database,
            embeddingService: FailingEmbeddingProvider(),
            vectorStore: EmptyVectorStore(),
            apiClient: APIClient()
        )

        let memories = try await manager.retrieveMemories(
            for: card.id,
            query: "silver key",
            limit: 5
        )

        #expect(memories.map(\.id) == ["recent-memory"])
    }

    private func makeExtractableConversation(
        database: DatabaseManager,
        card: CharacterCardRecord
    ) async throws -> ConversationRecord {
        let now = Date()
        let endpoint = APIEndpointRecord(
            id: "endpoint-memory-extraction",
            name: "Local",
            baseURL: "http://localhost:8080/v1",
            apiKey: "test-key",
            isDefault: true,
            createdAt: now,
            updatedAt: now
        )
        let model = EndpointModelRecord(
            id: "model-memory-extraction",
            endpointId: endpoint.id,
            modelId: "test-model",
            maxContextTokens: 4096,
            apiMode: APIMode.chatCompletions.rawValue,
            providerDialect: APIProviderDialect.openAICompatible.rawValue,
            isDefault: true,
            isManual: true,
            createdAt: now
        )
        var conversation = TestHelpers.makeConversation()
        conversation.characterCardId = card.id
        conversation.apiEndpointId = endpoint.id
        conversation.modelName = model.modelId

        try await database.saveEndpoint(endpoint)
        try await database.saveEndpointModel(model)
        try await database.write { db in
            try card.insert(db)
        }
        try await database.saveConversation(conversation)
        for index in 1...4 {
            try await database.saveMessage(
                TestHelpers.makeMessage(
                    conversationId: conversation.id,
                    role: index.isMultiple(of: 2) ? "assistant" : "user",
                    content: "Conversation detail \(index)",
                    sortOrder: index
                )
            )
        }
        return conversation
    }

    private func makeExtractionAPIClient(memoryCount: Int = 1) -> APIClient {
        let memories = (1...memoryCount).map { index in
            """
            {\\"content\\":\\"Memory fact \(index).\\",\\"type\\":\\"fact\\",\\"importance\\":80}
            """
        }.joined(separator: ",")
        let responseBody = """
        {"id":"memory-extraction","choices":[{"index":0,"message":{"role":"assistant","content":"[\(memories)]"},"finish_reason":"stop"}],"usage":null}
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
