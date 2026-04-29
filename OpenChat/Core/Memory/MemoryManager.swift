import Foundation
import os.log

private let logger = Logger(subsystem: "com.openchat", category: "Memory")

struct MemoryManager: Sendable {
    private let databaseManager: DatabaseManager
    private let embeddingService: any EmbeddingProvider
    private let vectorStore: any MemoryVectorStore
    private let apiClient: APIClient

    private static let minimumMessagesForExtraction = 4
    private static let distanceThreshold: Float = 1.5

    init(
        databaseManager: DatabaseManager,
        embeddingService: any EmbeddingProvider,
        vectorStore: any MemoryVectorStore,
        apiClient: APIClient
    ) {
        self.databaseManager = databaseManager
        self.embeddingService = embeddingService
        self.vectorStore = vectorStore
        self.apiClient = apiClient
    }

    // MARK: - Extraction

    @discardableResult
    func extractMemories(from conversation: ConversationRecord) async throws -> [MemoryEntryRecord] {
        // Refresh conversation from DB to get latest characterCardId
        let freshConversation = try await databaseManager.fetchConversation(id: conversation.id)
        guard let current = freshConversation,
              let characterCardId = current.characterCardId else {
            logger.info("Skipping memory extraction: no character card bound to conversation \(conversation.id)")
            return []
        }

        // Incremental extraction: only process messages after the last extracted memory
        let lastExtractionDate = try await databaseManager.latestMemoryDate(
            conversationId: current.id
        )
        let allMessages = try await databaseManager.fetchMessages(conversationId: current.id)
        let messages: [MessageRecord]
        if let cutoff = lastExtractionDate {
            messages = allMessages.filter { $0.createdAt > cutoff }
        } else {
            messages = allMessages
        }

        guard messages.count >= Self.minimumMessagesForExtraction else {
            logger.info("Skipping memory extraction: only \(messages.count) new messages (need \(Self.minimumMessagesForExtraction))")
            return []
        }

        let endpoint = try await resolveEndpoint(for: current)
        let extractedMemories = try await callExtractionAPI(
            messages: messages,
            endpoint: endpoint
        )

        let now = Date()
        var saved: [MemoryEntryRecord] = []
        for extracted in extractedMemories {
            let entry = MemoryEntryRecord(
                id: UUID().uuidString,
                characterCardId: characterCardId,
                sourceConversationId: current.id,
                content: extracted.content,
                memoryType: extracted.resolvedType.rawValue,
                importance: extracted.resolvedImportance,
                createdAt: now,
                updatedAt: now
            )
            try await databaseManager.saveMemory(entry)
            saved.append(entry)

            do {
                let embedding = try embeddingService.embed(entry.content, isQuery: false)
                try await vectorStore.insert(entry: entry, embedding: embedding)
            } catch {
                logger.warning("Vector storage failed for memory \(entry.id): \(error.localizedDescription)")
            }
        }

        logger.info("Extracted \(saved.count) memories from conversation \(current.id)")
        return saved
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
    }

    func deleteAllMemories(for characterCardId: String) async throws {
        try await vectorStore.deleteAll(characterCardId: characterCardId)
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

        // Resolve model: conversation.modelName → default model for endpoint
        let model: EndpointModelRecord
        if let modelName = conversation.modelName,
           let found = try await databaseManager.fetchEndpointModel(endpointId: record.id, modelId: modelName) {
            model = found
        } else if let defaultModel = try await databaseManager.fetchDefaultModel(endpointId: record.id) {
            model = defaultModel
        } else {
            model = EndpointModelRecord(
                id: UUID().uuidString,
                endpointId: record.id,
                modelId: conversation.modelName ?? "default",
                maxContextTokens: AppConstants.defaultMaxContextTokens,
                apiMode: APIMode.chatCompletions.rawValue,
                providerDialect: APIProviderDialect.openAICompatible.rawValue,
                isDefault: true,
                isManual: true,
                createdAt: .now
            )
        }

        return try APIEndpointConfig(from: record, model: model)
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
        var cleaned = content
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Try to extract JSON array if there's surrounding text
        if let start = cleaned.firstIndex(of: "["),
           let end = cleaned.lastIndex(of: "]") {
            cleaned = String(cleaned[start...end])
        }

        guard let data = cleaned.data(using: .utf8) else {
            throw MemoryError.invalidExtractionResponse
        }

        do {
            return try JSONDecoder().decode([ExtractedMemory].self, from: data)
        } catch {
            logger.error("Failed to parse extraction response: \(error.localizedDescription)\nRaw content: \(cleaned.prefix(500))")
            throw MemoryError.extractionFailed(reason: "Failed to parse extraction response: \(error.localizedDescription)")
        }
    }
}

// MARK: - Extraction DTO

struct ExtractedMemory: Sendable {
    let content: String
    let type: String
    let importance: RawImportance

    var resolvedType: MemoryType {
        MemoryType(rawValue: type.lowercased()) ?? .event
    }

    var resolvedImportance: Int {
        importance.value.clamped(to: 0...100)
    }

    /// Handles LLM returning importance as either Int or String
    enum RawImportance: Sendable {
        case int(Int)
        case string(String)

        var value: Int {
            switch self {
            case .int(let v): v
            case .string(let s): Int(s) ?? 50
            }
        }
    }
}

extension ExtractedMemory: Decodable {
    enum CodingKeys: String, CodingKey {
        case content, type, importance
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        content = try container.decode(String.self, forKey: .content)
        type = (try? container.decode(String.self, forKey: .type)) ?? "event"
        if let intVal = try? container.decode(Int.self, forKey: .importance) {
            importance = .int(intVal)
        } else if let strVal = try? container.decode(String.self, forKey: .importance) {
            importance = .string(strVal)
        } else {
            importance = .int(50)
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
