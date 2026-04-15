import Foundation

struct MemoryManager: Sendable {
    private let databaseManager: DatabaseManager
    private let embeddingService: EmbeddingService
    private let vectorStore: VectorStore
    private let apiClient: APIClient

    private static let minimumMessagesForExtraction = 4
    private static let distanceThreshold: Float = 1.5

    init(
        databaseManager: DatabaseManager,
        embeddingService: EmbeddingService,
        vectorStore: VectorStore,
        apiClient: APIClient
    ) {
        self.databaseManager = databaseManager
        self.embeddingService = embeddingService
        self.vectorStore = vectorStore
        self.apiClient = apiClient
    }

    // MARK: - Extraction

    func extractMemories(from conversation: ConversationRecord) async throws {
        guard let characterCardId = conversation.characterCardId else { return }

        let alreadyExtracted = try await databaseManager.hasMemoriesForConversation(
            conversationId: conversation.id
        )
        guard !alreadyExtracted else { return }

        let messages = try await databaseManager.fetchMessages(conversationId: conversation.id)
        guard messages.count >= Self.minimumMessagesForExtraction else { return }

        let endpoint = try await resolveEndpoint(for: conversation)
        let extractedMemories = try await callExtractionAPI(
            messages: messages,
            endpoint: endpoint
        )

        let now = Date()
        for extracted in extractedMemories {
            let entry = MemoryEntryRecord(
                id: UUID().uuidString,
                characterCardId: characterCardId,
                sourceConversationId: conversation.id,
                content: extracted.content,
                memoryType: extracted.type.rawValue,
                importance: extracted.importance,
                createdAt: now,
                updatedAt: now
            )
            try await databaseManager.saveMemory(entry)

            do {
                let embedding = try embeddingService.embed(entry.content, isQuery: false)
                try await vectorStore.insert(entryId: entry.id, embedding: embedding)
            } catch {
                // Vector storage failure is non-fatal; memory is still in DB
            }
        }
    }

    // MARK: - Retrieval

    func retrieveMemories(
        for characterCardId: String,
        query: String,
        limit: Int = 5
    ) async throws -> [MemoryEntryRecord] {
        let queryEmbedding = try embeddingService.embed(query, isQuery: true)
        let results = try await vectorStore.search(
            query: queryEmbedding,
            characterCardId: characterCardId,
            limit: limit
        )

        let filtered = results.filter { $0.distance < Self.distanceThreshold }
        guard !filtered.isEmpty else {
            return try await retrieveRecentSummary(for: characterCardId, limit: limit)
        }

        let ids = filtered.map(\.entryId)
        let entries = try await databaseManager.fetchMemories(ids: ids)

        // Merge with recent summaries and deduplicate
        let summaries = try await retrieveRecentSummary(for: characterCardId, limit: 2)
        let existingIDs = Set(entries.map(\.id))
        let uniqueSummaries = summaries.filter { !existingIDs.contains($0.id) }

        return entries + uniqueSummaries
    }

    func retrieveRecentSummary(
        for characterCardId: String,
        limit: Int = 5
    ) async throws -> [MemoryEntryRecord] {
        try await databaseManager.fetchRecentMemories(
            characterCardId: characterCardId,
            limit: limit
        )
    }

    // MARK: - Deletion

    func deleteMemory(id: String) async throws {
        try await vectorStore.delete(entryId: id)
        try await databaseManager.deleteMemory(id: id)
    }

    func deleteAllMemories(for characterCardId: String) async throws {
        try await vectorStore.deleteAll(characterCardId: characterCardId)
        try await databaseManager.deleteAllMemories(characterCardId: characterCardId)
    }

    // MARK: - Private

    private func resolveEndpoint(for conversation: ConversationRecord) async throws -> APIEndpointConfig {
        let record: APIEndpointRecord?
        if let endpointId = conversation.apiEndpointId {
            record = try await databaseManager.fetchEndpoint(id: endpointId)
        } else {
            record = try await databaseManager.fetchDefaultEndpoint()
        }
        guard let record else {
            throw APIError.noEndpointConfigured
        }
        return try APIEndpointConfig(from: record)
    }

    private func callExtractionAPI(
        messages: [MessageRecord],
        endpoint: APIEndpointConfig
    ) async throws -> [ExtractedMemory] {
        let conversationText = messages.map { "\($0.role): \($0.content)" }.joined(separator: "\n")
        let systemPrompt = """
            You are a memory extraction assistant. Analyze the following conversation \
            and extract key memories. Return a JSON array with the following structure:

            [
              {
                "content": "Brief description of the memory",
                "type": "event|fact|relationship|summary",
                "importance": 0-100
              }
            ]

            Rules:
            - Extract important events, facts about the user, relationship changes, and conversation summaries
            - importance: 90-100 for critical plot points, 50-70 for general events, 30-50 for minor details
            - Keep each memory concise (1-2 sentences)
            - Return ONLY the JSON array, no other text
            """

        let apiMessages = [
            ChatMessage(role: "system", content: systemPrompt),
            ChatMessage(role: "user", content: conversationText),
        ]

        let parameters = ModelParameters(
            temperature: 0.3,
            topP: 0.9,
            maxTokens: 2048,
            frequencyPenalty: 0,
            presencePenalty: 0,
            stop: nil
        )

        let response = try await apiClient.sendMessage(
            messages: apiMessages,
            endpoint: endpoint,
            parameters: parameters
        )

        guard let content = response.choices.first?.message.content else {
            throw MemoryError.invalidExtractionResponse
        }

        return try parseExtractedMemories(content)
    }

    private func parseExtractedMemories(_ content: String) throws -> [ExtractedMemory] {
        // Try to find JSON array in response (may have markdown fences)
        let cleaned = content
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8) else {
            throw MemoryError.invalidExtractionResponse
        }

        do {
            return try JSONDecoder().decode([ExtractedMemory].self, from: data)
        } catch {
            throw MemoryError.extractionFailed(reason: "Failed to parse extraction response: \(error.localizedDescription)")
        }
    }
}

// MARK: - Extraction DTO

private struct ExtractedMemory: Codable {
    let content: String
    let type: MemoryType
    let importance: Int
}
