import Foundation
import Testing

@testable import OpenChat

private final class ExtractionRequestCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var body: APIRequest?

    func store(_ body: APIRequest) {
        lock.lock()
        defer { lock.unlock() }
        self.body = body
    }

    func load() -> APIRequest? {
        lock.lock()
        defer { lock.unlock() }
        return body
    }
}

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

private struct StaticVectorStore: MemoryVectorStore {
    let results: [(entryId: String, distance: Float)]

    func insert(entry: MemoryEntryRecord, embedding: [Float]) async throws {}
    func insert(entries: [(entry: MemoryEntryRecord, embedding: [Float])]) async throws {}

    func search(
        query: [Float],
        characterCardId: String,
        limit: Int
    ) async throws -> [(entryId: String, distance: Float)] {
        Array(results.prefix(limit))
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
            apiClient: apiClient,
            apiKeyStore: InMemoryAPIKeyStore()
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
            apiClient: apiClient,
            apiKeyStore: InMemoryAPIKeyStore()
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

    @Test func test_recallMemories_preserves_semantic_order_and_records_keyword_trace() async throws {
        let database = try TestHelpers.makeDatabaseManager()
        let card = try await saveMemoryCard(database: database, id: "card-semantic-trace")
        try await saveMemories(
            database: database,
            [
                TestHelpers.makeMemoryEntry(
                    id: "semantic-a",
                    characterCardId: card.id,
                    content: "Ava hid the brass lantern.",
                    memoryType: .event,
                    importance: 20
                ),
                TestHelpers.makeMemoryEntry(
                    id: "semantic-b",
                    characterCardId: card.id,
                    content: "Ava repaired the old gate.",
                    memoryType: .fact,
                    importance: 40
                ),
                TestHelpers.makeMemoryEntry(
                    id: "keyword-c",
                    characterCardId: card.id,
                    content: "The silver key opens the mirror room.",
                    memoryType: .fact,
                    importance: 100
                ),
            ]
        )
        let manager = MemoryManager(
            databaseManager: database,
            embeddingService: FixedEmbeddingProvider(),
            vectorStore: StaticVectorStore(
                results: [
                    ("semantic-a", 0.2),
                    ("semantic-b", 0.4),
                ]
            ),
            apiClient: APIClient(),
            apiKeyStore: InMemoryAPIKeyStore()
        )

        let result = try await manager.recallMemories(
            for: card.id,
            query: "silver key",
            limit: 5
        )

        #expect(result.entries.map(\.memory.id) == ["semantic-a", "semantic-b", "keyword-c"])
        #expect(result.entries[0].semanticDistance == 0.2)
        #expect(result.entries[2].keywordRank == 1)
        #expect(result.entries[2].reasons.contains(.keyword))
        #expect(result.trace.semanticCandidateCount == 2)
        #expect(result.trace.keywordCandidateCount == 1)
        #expect(result.trace.selectedIds == ["semantic-a", "semantic-b", "keyword-c"])
        #expect(result.trace.fallback == nil)
    }

    @Test func test_recallMemories_semantic_failure_returns_keyword_and_high_value_without_recent_noise() async throws {
        let database = try TestHelpers.makeDatabaseManager()
        let card = try await saveMemoryCard(database: database, id: "card-fallback")
        try await saveMemories(
            database: database,
            [
                TestHelpers.makeMemoryEntry(
                    id: "recent-noise",
                    characterCardId: card.id,
                    content: "Ava counted clouds yesterday.",
                    memoryType: .event,
                    importance: 10
                ),
                TestHelpers.makeMemoryEntry(
                    id: "keyword-memory",
                    characterCardId: card.id,
                    content: "Ava promised to remember the silver key.",
                    memoryType: .fact,
                    importance: 50
                ),
                TestHelpers.makeMemoryEntry(
                    id: "high-value",
                    characterCardId: card.id,
                    content: "Ava and the user became trusted partners.",
                    memoryType: .relationship,
                    importance: 90
                ),
            ]
        )
        let manager = MemoryManager(
            databaseManager: database,
            embeddingService: FailingEmbeddingProvider(),
            vectorStore: EmptyVectorStore(),
            apiClient: APIClient(),
            apiKeyStore: InMemoryAPIKeyStore()
        )

        let result = try await manager.recallMemories(
            for: card.id,
            query: "silver key",
            limit: 5
        )

        #expect(result.entries.map(\.memory.id) == ["keyword-memory", "high-value"])
        #expect(!result.entries.map(\.memory.id).contains("recent-noise"))
        #expect(result.trace.fallback == .semanticUnavailable)
        #expect(result.trace.keywordCandidateCount == 1)
        #expect(result.trace.recentCandidateCount == 1)
    }

    @Test func test_retrieveMemories_compatibility_returns_ordered_memory_records() async throws {
        let database = try TestHelpers.makeDatabaseManager()
        let card = try await saveMemoryCard(database: database, id: "card-compat")
        try await saveMemories(
            database: database,
            [
                TestHelpers.makeMemoryEntry(id: "first", characterCardId: card.id, content: "First memory."),
                TestHelpers.makeMemoryEntry(id: "second", characterCardId: card.id, content: "Second memory."),
            ]
        )
        let manager = MemoryManager(
            databaseManager: database,
            embeddingService: FixedEmbeddingProvider(),
            vectorStore: StaticVectorStore(
                results: [
                    ("second", 0.2),
                    ("first", 0.3),
                ]
            ),
            apiClient: APIClient(),
            apiKeyStore: InMemoryAPIKeyStore()
        )

        let memories = try await manager.retrieveMemories(for: card.id, query: "anything", limit: 2)

        #expect(memories.map(\.id) == ["second", "first"])
    }

    @Test func test_recallMemories_no_semantic_hit_prefers_keyword_over_recent_high_value() async throws {
        let database = try TestHelpers.makeDatabaseManager()
        let card = try await saveMemoryCard(database: database, id: "card-no-hit-keyword")
        try await saveMemories(
            database: database,
            [
                TestHelpers.makeMemoryEntry(
                    id: "keyword-first",
                    characterCardId: card.id,
                    content: "The crimson door needs the silver key.",
                    memoryType: .fact,
                    importance: 40
                ),
                TestHelpers.makeMemoryEntry(
                    id: "relationship-backup",
                    characterCardId: card.id,
                    content: "Ava trusts the user with secrets.",
                    memoryType: .relationship,
                    importance: 90
                ),
            ]
        )
        let manager = MemoryManager(
            databaseManager: database,
            embeddingService: FixedEmbeddingProvider(),
            vectorStore: StaticVectorStore(results: [("relationship-backup", 2.0)]),
            apiClient: APIClient(),
            apiKeyStore: InMemoryAPIKeyStore()
        )

        let result = try await manager.recallMemories(for: card.id, query: "silver key", limit: 5)

        #expect(result.entries.map(\.memory.id) == ["keyword-first"])
        #expect(result.trace.fallback == .noSemanticHit)
        #expect(result.trace.omitted.contains {
            $0.memoryId == "relationship-backup" && $0.reason == .distanceThreshold
        })
    }

    @Test func test_recallMemories_no_semantic_or_keyword_hit_returns_only_recent_high_value() async throws {
        let database = try TestHelpers.makeDatabaseManager()
        let card = try await saveMemoryCard(database: database, id: "card-high-value")
        try await saveMemories(
            database: database,
            [
                TestHelpers.makeMemoryEntry(
                    id: "noise",
                    characterCardId: card.id,
                    content: "Ava sharpened a pencil.",
                    memoryType: .event,
                    importance: 10
                ),
                TestHelpers.makeMemoryEntry(
                    id: "summary",
                    characterCardId: card.id,
                    content: "Ava summarized the chapter.",
                    memoryType: .summary,
                    importance: 20
                ),
                TestHelpers.makeMemoryEntry(
                    id: "important-fact",
                    characterCardId: card.id,
                    content: "Ava found the hidden archive.",
                    memoryType: .fact,
                    importance: 80
                ),
            ]
        )
        let manager = MemoryManager(
            databaseManager: database,
            embeddingService: FixedEmbeddingProvider(),
            vectorStore: EmptyVectorStore(),
            apiClient: APIClient(),
            apiKeyStore: InMemoryAPIKeyStore()
        )

        let result = try await manager.recallMemories(for: card.id, query: "unmatched query", limit: 5)

        #expect(result.entries.map(\.memory.id) == ["summary", "important-fact"])
        #expect(!result.entries.map(\.memory.id).contains("noise"))
        #expect(result.trace.fallback == .noSemanticHit)
    }

    @Test func test_recallMemories_empty_character_memories_returns_empty_index_trace() async throws {
        let database = try TestHelpers.makeDatabaseManager()
        let card = try await saveMemoryCard(database: database, id: "card-empty")
        let manager = MemoryManager(
            databaseManager: database,
            embeddingService: FixedEmbeddingProvider(),
            vectorStore: EmptyVectorStore(),
            apiClient: APIClient(),
            apiKeyStore: InMemoryAPIKeyStore()
        )

        let result = try await manager.recallMemories(for: card.id, query: "silver key", limit: 5)

        #expect(result.entries.isEmpty)
        #expect(result.trace.fallback == .emptyIndex)
        #expect(result.trace.selectedIds.isEmpty)
        #expect(result.trace.semanticCandidateCount == 0)
        #expect(result.trace.keywordCandidateCount == 0)
        #expect(result.trace.recentCandidateCount == 0)
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

    private func saveMemoryCard(
        database: DatabaseManager,
        id: String
    ) async throws -> CharacterCardRecord {
        let card = TestHelpers.makeCharacterCard(id: id)
        try await database.write { db in
            try card.insert(db)
        }
        return card
    }

    private func saveMemories(
        database: DatabaseManager,
        _ memories: [MemoryEntryRecord]
    ) async throws {
        for memory in memories {
            try await database.saveMemory(memory)
        }
    }

    // MARK: - Phase C: dedupe / validation / provenance

    @Test func test_extractMemories_v2_dedupe_keeps_higher_importance() async throws {
        let database = try TestHelpers.makeDatabaseManager()
        let card = TestHelpers.makeCharacterCard(id: "card-dedupe")
        let conversation = try await makeExtractableConversation(database: database, card: card)
        let apiClient = makeV2ExtractionAPIClientWithDedupe(memories: [
            (content: "Player likes tea", type: "fact", importance: 60, dedupeKey: "player-tea"),
            (content: "Player really likes tea", type: "fact", importance: 80, dedupeKey: "player-tea"),
        ])
        let manager = MemoryManager(
            databaseManager: database,
            embeddingService: FixedEmbeddingProvider(),
            vectorStore: VectorStore(databaseManager: database),
            apiClient: apiClient,
            apiKeyStore: InMemoryAPIKeyStore()
        )

        let result = try await manager.extractMemories(from: conversation)
        #expect(result.count == 1)
        #expect(result[0].content == "Player really likes tea")
        #expect(result[0].importance == 80)

        let provenance = try await database.fetchMemoryProvenance(memoryEntryId: result[0].id)
        #expect(provenance?.dedupeKey == "player-tea")
    }

    @Test func test_extractMemories_v2_skips_out_of_range_source() async throws {
        let database = try TestHelpers.makeDatabaseManager()
        let card = TestHelpers.makeCharacterCard(id: "card-range")
        let conversation = try await makeExtractableConversation(database: database, card: card)
        let apiClient = makeV2ExtractionAPIClientWithRange(memories: [
            (content: "Valid memory", type: "event", importance: 70, sourceStartSortOrder: 1),
            (content: "Invalid range memory", type: "event", importance: 90, sourceStartSortOrder: 999),
        ])
        let manager = MemoryManager(
            databaseManager: database,
            embeddingService: FixedEmbeddingProvider(),
            vectorStore: VectorStore(databaseManager: database),
            apiClient: apiClient,
            apiKeyStore: InMemoryAPIKeyStore()
        )

        let result = try await manager.extractMemories(from: conversation)
        #expect(result.count == 1)
        #expect(result[0].content == "Valid memory")

        let provenance = try await database.fetchMemoryProvenance(memoryEntryId: result[0].id)
        #expect(provenance?.sourceStartSortOrder == 1)
    }

    @Test func test_extractMemories_v2_filters_invalid_source_message_ids_in_provenance() async throws {
        let database = try TestHelpers.makeDatabaseManager()
        let card = TestHelpers.makeCharacterCard(id: "card-source-ids")
        let conversation = try await makeExtractableConversation(database: database, card: card)
        let messages = try await database.fetchMessages(conversationId: conversation.id)
        let validMessageId = try #require(messages.first?.id)
        let apiClient = makeV2ExtractionAPIClient(
            memories: [
                V2ExtractionMemory(
                    content: "Player trusts Ava with the silver key",
                    type: "relationship",
                    importance: 80,
                    sourceMessageIds: [validMessageId, "missing-message-id"]
                ),
            ]
        )
        let manager = MemoryManager(
            databaseManager: database,
            embeddingService: FixedEmbeddingProvider(),
            vectorStore: VectorStore(databaseManager: database),
            apiClient: apiClient,
            apiKeyStore: InMemoryAPIKeyStore()
        )

        let result = try await manager.extractMemories(from: conversation)

        #expect(result.count == 1)
        let provenance = try await database.fetchMemoryProvenance(memoryEntryId: result[0].id)
        #expect(provenance?.decodedSourceMessageIds == [validMessageId])
    }

    @Test func test_extractMemories_v2_skip_and_reinforce_do_not_insert_memory() async throws {
        let database = try TestHelpers.makeDatabaseManager()
        let card = TestHelpers.makeCharacterCard(id: "card-skip-reinforce")
        let conversation = try await makeExtractableConversation(database: database, card: card)
        let apiClient = makeV2ExtractionAPIClient(
            memories: [
                V2ExtractionMemory(content: "Should skip", action: "skip"),
                V2ExtractionMemory(content: "Should reinforce only", action: "reinforce"),
            ]
        )
        let manager = MemoryManager(
            databaseManager: database,
            embeddingService: FixedEmbeddingProvider(),
            vectorStore: VectorStore(databaseManager: database),
            apiClient: apiClient,
            apiKeyStore: InMemoryAPIKeyStore()
        )

        let result = try await manager.extractMemories(from: conversation)

        #expect(result.isEmpty)
        #expect(try await database.fetchMemoryCount(characterCardId: card.id) == 0)
        let provenanceCount = try await database.read { db in
            try MemoryEntryProvenanceRecord.fetchCount(db)
        }
        #expect(provenanceCount == 0)
    }

    @Test func test_extractMemories_v2_provenance_clamps_and_cleans_metadata() async throws {
        let database = try TestHelpers.makeDatabaseManager()
        let card = TestHelpers.makeCharacterCard(id: "card-provenance-cleanup")
        let conversation = try await makeExtractableConversation(database: database, card: card)
        let apiClient = makeV2ExtractionAPIClient(
            memories: [
                V2ExtractionMemory(
                    content: "Player keeps careful notes",
                    type: "fact",
                    importance: 60,
                    confidence: 1.4,
                    tags: [" relationship ", "", "Relationship", "plot"],
                    dedupeKey: " Player-Notes "
                ),
            ]
        )
        let manager = MemoryManager(
            databaseManager: database,
            embeddingService: FixedEmbeddingProvider(),
            vectorStore: VectorStore(databaseManager: database),
            apiClient: apiClient,
            apiKeyStore: InMemoryAPIKeyStore()
        )

        let result = try await manager.extractMemories(from: conversation)

        let provenance = try await database.fetchMemoryProvenance(memoryEntryId: result[0].id)
        #expect(provenance?.confidence == 1.0)
        #expect(provenance?.dedupeKey == "player-notes")
        #expect(provenance?.decodedTags == ["relationship", "plot"])
    }

    @Test func test_extractMemories_v2_request_includes_character_hints_and_message_boundaries() async throws {
        let database = try TestHelpers.makeDatabaseManager()
        let card = TestHelpers.makeCharacterCard(id: "card-request-shape", name: "Mira")
        let conversation = try await makeExtractableConversation(database: database, card: card)
        try await database.saveMemory(
            TestHelpers.makeMemoryEntry(
                id: "hint-relationship",
                characterCardId: card.id,
                content: "Mira trusts the player.",
                memoryType: .relationship,
                importance: 20
            )
        )
        try await database.saveMemory(
            TestHelpers.makeMemoryEntry(
                id: "hint-noise",
                characterCardId: card.id,
                content: "Mira counted clouds.",
                memoryType: .event,
                importance: 10
            )
        )
        let capture = ExtractionRequestCapture()
        let apiClient = makeV2ExtractionAPIClient(
            memories: [V2ExtractionMemory(content: "Mira and the player made a pact.")],
            capture: capture
        )
        let manager = MemoryManager(
            databaseManager: database,
            embeddingService: FixedEmbeddingProvider(),
            vectorStore: VectorStore(databaseManager: database),
            apiClient: apiClient,
            apiKeyStore: InMemoryAPIKeyStore()
        )

        _ = try await manager.extractMemories(from: conversation)

        let request = try #require(capture.load())
        let userMessage = try #require(request.messages.first { $0.role == "user" })
        let data = Data(userMessage.content.utf8)
        let input = try JSONDecoder().decode(MemoryExtractionInput.self, from: data)
        #expect(input.character?.id == card.id)
        #expect(input.character?.name == "Mira")
        #expect(input.existingMemoryHints.map(\.id) == ["hint-relationship"])
        #expect(input.messages.count == 4)
        #expect(input.messages.allSatisfy { !$0.id.isEmpty && $0.sortOrder > 0 })
    }

    @Test func test_extractMemories_vector_failure_does_not_leave_entry_or_provenance() async throws {
        let database = try TestHelpers.makeDatabaseManager()
        let card = TestHelpers.makeCharacterCard(id: "card-atomic")
        let conversation = try await makeExtractableConversation(database: database, card: card)
        let apiClient = makeV2ExtractionAPIClientWithRange(memories: [
            (content: "Should not persist", type: "fact", importance: 80, sourceStartSortOrder: nil),
        ])
        let manager = MemoryManager(
            databaseManager: database,
            embeddingService: FixedEmbeddingProvider(),
            vectorStore: FailingInsertVectorStore(),
            apiClient: apiClient,
            apiKeyStore: InMemoryAPIKeyStore()
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

        let provenanceCount = try await database.read { db in
            try MemoryEntryProvenanceRecord.fetchCount(db)
        }
        #expect(provenanceCount == 0)
    }

    private func makeV2ExtractionAPIClientWithRange(
        memories: [(content: String, type: String, importance: Int, sourceStartSortOrder: Int?)]
    ) -> APIClient {
        let memoryJSONs = memories.map { m in
            var parts: [String] = [
                "\\\"content\\\":\\\"\(m.content)\\\"",
                "\\\"type\\\":\\\"\(m.type)\\\"",
                "\\\"importance\\\":\(m.importance)"
            ]
            if let order = m.sourceStartSortOrder {
                parts.append("\\\"sourceStartSortOrder\\\":\(order)")
            }
            return "{" + parts.joined(separator: ",") + "}"
        }.joined(separator: ",")
        let responseBody = """
        {"id":"memory-extraction","choices":[{"index":0,"message":{"role":"assistant","content":"[\(memoryJSONs)]"},"finish_reason":"stop"}],"usage":null}
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

    private func makeV2ExtractionAPIClientWithDedupe(
        memories: [(content: String, type: String, importance: Int, dedupeKey: String)]
    ) -> APIClient {
        let memoryJSONs = memories.map { m in
            """
            {\\"content\\":\\"\(m.content)\\",\\"type\\":\\"\(m.type)\\",\\"importance\\":\(m.importance),\\"dedupeKey\\":\\"\(m.dedupeKey)\\"}
            """
        }.joined(separator: ",")
        let responseBody = """
        {"id":"memory-extraction","choices":[{"index":0,"message":{"role":"assistant","content":"[\(memoryJSONs)]"},"finish_reason":"stop"}],"usage":null}
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

    private func makeV2ExtractionAPIClient(
        memories: [V2ExtractionMemory],
        capture: ExtractionRequestCapture? = nil
    ) -> APIClient {
        let memoryJSONs = memories.map(\.jsonString).joined(separator: ",")
        let responseBody = """
        {"id":"memory-extraction","choices":[{"index":0,"message":{"role":"assistant","content":"[\(memoryJSONs)]"},"finish_reason":"stop"}],"usage":null}
        """
        let session = MockURLProtocol.makeSession { request in
            if let capture {
                let data = try request.openChatTestBodyData()
                capture.store(try JSONDecoder().decode(APIRequest.self, from: data))
            }
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

private struct V2ExtractionMemory {
    var content: String
    var type = "fact"
    var importance = 80
    var sourceStartSortOrder: Int?
    var sourceEndSortOrder: Int?
    var sourceMessageIds: [String] = []
    var confidence: Double?
    var tags: [String] = []
    var dedupeKey: String?
    var action: String?

    var jsonString: String {
        var parts: [String] = [
            #"\"content\":\"\#(content)\""#,
            #"\"type\":\"\#(type)\""#,
            #"\"importance\":\#(importance)"#
        ]
        if let sourceStartSortOrder {
            parts.append(#"\"sourceStartSortOrder\":\#(sourceStartSortOrder)"#)
        }
        if let sourceEndSortOrder {
            parts.append(#"\"sourceEndSortOrder\":\#(sourceEndSortOrder)"#)
        }
        if !sourceMessageIds.isEmpty {
            let ids = sourceMessageIds.map { #"\"\#($0)\""# }.joined(separator: ",")
            parts.append(#"\"sourceMessageIds\":[\#(ids)]"#)
        }
        if let confidence {
            parts.append(#"\"confidence\":\#(confidence)"#)
        }
        if !tags.isEmpty {
            let tagValues = tags.map { #"\"\#($0)\""# }.joined(separator: ",")
            parts.append(#"\"tags\":[\#(tagValues)]"#)
        }
        if let dedupeKey {
            parts.append(#"\"dedupeKey\":\"\#(dedupeKey)\""#)
        }
        if let action {
            parts.append(#"\"action\":\"\#(action)\""#)
        }
        return "{" + parts.joined(separator: ",") + "}"
    }
}

private extension URLRequest {
    func openChatTestBodyData() throws -> Data {
        if let httpBody {
            return httpBody
        }
        guard let httpBodyStream else {
            throw URLError(.cannotDecodeRawData)
        }

        httpBodyStream.open()
        defer { httpBodyStream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let bytesRead = buffer.withUnsafeMutableBufferPointer { pointer in
                httpBodyStream.read(pointer.baseAddress!, maxLength: pointer.count)
            }
            if bytesRead < 0 {
                throw httpBodyStream.streamError ?? URLError(.cannotDecodeRawData)
            }
            if bytesRead == 0 {
                break
            }
            data.append(contentsOf: buffer.prefix(bytesRead))
        }
        return data
    }
}
