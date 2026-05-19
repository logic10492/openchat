import Foundation
import os.log

private let logger = Logger(subsystem: "com.openchat", category: "Memory")

struct MemoryManager: Sendable {
    private let databaseManager: DatabaseManager
    private let embeddingService: any EmbeddingProvider
    private let vectorStore: any MemoryVectorStore
    private let apiClient: APIClient
    private let apiKeyStore: any APIKeyStore

    static let minimumMessagesForExtraction = 4
    private static let distanceThreshold: Float = 1.5

    init(
        databaseManager: DatabaseManager,
        embeddingService: any EmbeddingProvider,
        vectorStore: any MemoryVectorStore,
        apiClient: APIClient,
        apiKeyStore: any APIKeyStore = KeychainAPIKeyStore()
    ) {
        self.databaseManager = databaseManager
        self.embeddingService = embeddingService
        self.vectorStore = vectorStore
        self.apiClient = apiClient
        self.apiKeyStore = apiKeyStore
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

        // Incremental extraction: only process messages after last extracted sortOrder
        let cutoff = current.lastExtractedSortOrder
        let allMessages = try await databaseManager.fetchMessages(conversationId: current.id)
        let messages: [MessageRecord]
        if let cutoff {
            messages = allMessages.filter { $0.sortOrder > cutoff }
        } else {
            messages = allMessages
        }

        guard messages.count >= Self.minimumMessagesForExtraction else {
            logger.info("Skipping memory extraction: only \(messages.count) new messages (need \(Self.minimumMessagesForExtraction))")
            return []
        }

        let endpoint = try await resolveEndpoint(for: current)
        let characterCard = try await databaseManager.fetchCharacterCard(id: characterCardId)
        let existingHints = try await fetchExistingMemoryHints(characterCardId: characterCardId)

        let extractedMemories = try await callExtractionAPI(
            messages: messages,
            characterCard: characterCard,
            existingMemoryHints: existingHints,
            endpoint: endpoint
        )

        let validMemories = validateAndFilter(
            extracted: extractedMemories,
            messageBatch: messages
        )
        let dedupedMemories = dedupeWithinBatch(validMemories)

        let now = Date()
        let modelName = endpoint.modelName
        let promptVersion = "v2"
        var entries: [(entry: MemoryEntryRecord, embedding: [Float])] = []
        var provenances: [String: MemoryEntryProvenanceRecord] = [:]

        do {
            for extracted in dedupedMemories {
                let entryId = UUID().uuidString
                let entry = MemoryEntryRecord(
                    id: entryId,
                    characterCardId: characterCardId,
                    sourceConversationId: current.id,
                    content: extracted.content,
                    memoryType: extracted.resolvedType.rawValue,
                    importance: extracted.resolvedImportance,
                    createdAt: now,
                    updatedAt: now
                )
                let embedding = try embeddingService.embed(entry.content, isQuery: false)
                entries.append((entry: entry, embedding: embedding))

                let provenance = makeProvenance(
                    memoryEntryId: entryId,
                    extracted: extracted,
                    modelName: modelName,
                    promptVersion: promptVersion,
                    now: now
                )
                provenances[entryId] = provenance
            }

            try await vectorStore.insert(entries: entries, provenances: provenances)
        } catch {
            logger.error("Memory vectorization failed for extracted memory in conversation \(current.id): \(error.localizedDescription)")
            throw MemoryError.embeddingFailed(underlying: error)
        }

        let saved = entries.map(\.entry)
        logger.info("Extracted \(saved.count) memories from conversation \(current.id)")

        // Update extraction boundary so next extraction only processes newer messages
        if let maxSortOrder = messages.map(\.sortOrder).max() {
            var updated = current
            updated.lastExtractedSortOrder = maxSortOrder
            updated.updatedAt = Date()
            try await databaseManager.saveConversation(updated)
        }

        return saved
    }

    // MARK: - Retrieval

    func retrieveMemories(
        for characterCardId: String,
        query: String,
        limit: Int = 5
    ) async throws -> [MemoryEntryRecord] {
        let result = try await recallMemories(
            for: characterCardId,
            query: query,
            limit: limit
        )
        return result.entries.map(\.memory)
    }

    func recallMemories(
        for characterCardId: String,
        query: String,
        limit: Int = 5
    ) async throws -> MemoryRecallResult {
        let normalizedLimit = max(limit, 0)
        guard normalizedLimit > 0 else {
            return MemoryRecallResult(
                entries: [],
                trace: MemoryRecallTrace(
                    query: query,
                    semanticCandidateCount: 0,
                    keywordCandidateCount: 0,
                    recentCandidateCount: 0,
                    selectedIds: [],
                    omitted: [],
                    fallback: .emptyIndex
                )
            )
        }

        var omitted: [MemoryRecallOmission] = []
        var semanticUnavailable = false
        var semanticCandidates: [SemanticRecallCandidate] = []
        do {
            let queryEmbedding = try embeddingService.embed(query, isQuery: true)
            let results = try await vectorStore.search(
                query: queryEmbedding,
                characterCardId: characterCardId,
                limit: max(normalizedLimit * 2, 20)
            )
            let filtered = results.filter { result in
                let isIncluded = result.distance < Self.distanceThreshold
                if !isIncluded {
                    omitted.append(
                        MemoryRecallOmission(
                            memoryId: result.entryId,
                            reason: .distanceThreshold
                        )
                    )
                }
                return isIncluded
            }
            semanticCandidates = try await makeSemanticCandidates(from: filtered)
        } catch {
            semanticUnavailable = true
            logger.warning("Semantic memory retrieval failed; falling back to keyword and high-value memories for character \(characterCardId): \(error.localizedDescription)")
        }

        let allMemories = try await databaseManager.fetchMemories(characterCardId: characterCardId)
        let keywordCandidates = makeKeywordCandidates(from: allMemories, query: query)
        let recentCandidates = try await makeRecentHighValueCandidates(
            characterCardId: characterCardId,
            limit: min(normalizedLimit, 3)
        )

        let fallback = makeFallback(
            hasMemories: !allMemories.isEmpty,
            semanticUnavailable: semanticUnavailable,
            semanticCandidateCount: semanticCandidates.count,
            keywordCandidateCount: keywordCandidates.count,
            recentCandidateCount: recentCandidates.count
        )
        let fused = fuseCandidates(
            semantic: semanticCandidates,
            keyword: keywordCandidates,
            recent: recentCandidates,
            fallback: fallback,
            limit: normalizedLimit,
            omitted: &omitted
        )

        let selectedIds = fused.map { $0.memory.id }
        let finalFallback: MemoryRecallFallback?
        if selectedIds.isEmpty {
            finalFallback = .emptyIndex
        } else {
            finalFallback = fallback == .emptyIndex ? nil : fallback
        }

        return MemoryRecallResult(
            entries: fused.enumerated().map { index, candidate in
                MemoryRecallEntry(
                    memory: candidate.memory,
                    finalRank: index + 1,
                    semanticRank: candidate.semanticRank,
                    semanticDistance: candidate.semanticDistance,
                    keywordRank: candidate.keywordRank,
                    recencyRank: candidate.recencyRank,
                    reasons: candidate.reasons
                )
            },
            trace: MemoryRecallTrace(
                query: query,
                semanticCandidateCount: semanticCandidates.count,
                keywordCandidateCount: keywordCandidates.count,
                recentCandidateCount: recentCandidates.count,
                selectedIds: selectedIds,
                omitted: omitted,
                fallback: finalFallback
            )
        )
    }

    // MARK: - Reflect Apply

    @discardableResult
    func applyReflectObservation(
        _ observation: MemoryReflectObservation,
        characterCardId: String
    ) async throws -> MemoryEntryRecord {
        guard observation.suggestedAction == .insertObservation else {
            throw MemoryReflectApplyError.unsupportedAction(observation.suggestedAction)
        }

        let sourceMemories = try await databaseManager.fetchMemories(ids: observation.basedOnMemoryIds)
        let sourceMemoriesById = Dictionary(uniqueKeysWithValues: sourceMemories.map { ($0.id, $0) })
        let missingIds = observation.basedOnMemoryIds.filter { sourceMemoriesById[$0] == nil }
        guard missingIds.isEmpty else {
            throw MemoryReflectError.missingSourceMemories(missingIds)
        }

        for memory in sourceMemories where memory.characterCardId != characterCardId {
            throw MemoryReflectError.crossCharacterMemory(
                id: memory.id,
                expectedCharacterCardId: characterCardId,
                actualCharacterCardId: memory.characterCardId
            )
        }

        let now = Date()
        let entry = MemoryEntryRecord(
            id: UUID().uuidString,
            characterCardId: characterCardId,
            sourceConversationId: nil,
            content: observation.content,
            memoryType: observation.memoryType.rawValue,
            importance: 60,
            createdAt: now,
            updatedAt: now
        )
        var seenBasedOnIds = Set<String>()
        let basedOnIds = observation.basedOnMemoryIds.filter { id in
            seenBasedOnIds.insert(id).inserted
        }
        let links = basedOnIds.map { basedOnId in
            MemoryEntryLinkRecord(
                fromMemoryEntryId: entry.id,
                toMemoryEntryId: basedOnId,
                relation: .summarizes,
                createdAt: now
            )
        }

        let embedding: [Float]
        do {
            embedding = try embeddingService.embed(entry.content, isQuery: false)
        } catch {
            throw MemoryError.embeddingFailed(underlying: error)
        }

        try await vectorStore.insert(entry: entry, embedding: embedding, links: links)
        return entry
    }

    private func makeSemanticCandidates(
        from results: [(entryId: String, distance: Float)]
    ) async throws -> [SemanticRecallCandidate] {
        let ids = results.map(\.entryId)
        let entriesById = Dictionary(
            uniqueKeysWithValues: try await databaseManager.fetchMemories(ids: ids).map { ($0.id, $0) }
        )

        return results.enumerated().compactMap { index, result in
            guard let entry = entriesById[result.entryId] else { return nil }
            return SemanticRecallCandidate(
                memory: entry,
                rank: index + 1,
                distance: result.distance
            )
        }
    }

    private func makeKeywordCandidates(
        from memories: [MemoryEntryRecord],
        query: String
    ) -> [KeywordRecallCandidate] {
        let keywords = keywordTokens(from: query)
        guard !keywords.isEmpty else { return [] }

        let ranked = memories.compactMap { memory -> KeywordRanking? in
            let content = memory.content.lowercased()
            let matches = keywords.compactMap { keyword -> Int? in
                guard let range = content.range(of: keyword) else { return nil }
                return content.distance(from: content.startIndex, to: range.lowerBound)
            }
            guard !matches.isEmpty else { return nil }
            return KeywordRanking(
                memory: memory,
                matchCount: matches.count,
                firstMatch: matches.min() ?? Int.max
            )
        }

        return ranked
            .sorted { lhs, rhs in
                if lhs.matchCount != rhs.matchCount {
                    return lhs.matchCount > rhs.matchCount
                }
                if lhs.firstMatch != rhs.firstMatch {
                    return lhs.firstMatch < rhs.firstMatch
                }
                if lhs.memory.importance != rhs.memory.importance {
                    return lhs.memory.importance > rhs.memory.importance
                }
                return lhs.memory.createdAt > rhs.memory.createdAt
            }
            .enumerated()
            .map { index, ranking in
                KeywordRecallCandidate(memory: ranking.memory, rank: index + 1)
            }
    }

    private func makeRecentHighValueCandidates(
        characterCardId: String,
        limit: Int
    ) async throws -> [RecentRecallCandidate] {
        try await databaseManager.fetchRecentHighValueMemories(
            characterCardId: characterCardId,
            limit: limit
        )
        .enumerated()
        .map { index, memory in
            RecentRecallCandidate(memory: memory, rank: index + 1)
        }
    }

    private func makeFallback(
        hasMemories: Bool,
        semanticUnavailable: Bool,
        semanticCandidateCount: Int,
        keywordCandidateCount: Int,
        recentCandidateCount: Int
    ) -> MemoryRecallFallback? {
        guard hasMemories else { return .emptyIndex }
        guard semanticCandidateCount == 0 else { return nil }

        if keywordCandidateCount == 0, recentCandidateCount == 0 {
            return .emptyIndex
        }

        return semanticUnavailable ? .semanticUnavailable : .noSemanticHit
    }

    private func fuseCandidates(
        semantic: [SemanticRecallCandidate],
        keyword: [KeywordRecallCandidate],
        recent: [RecentRecallCandidate],
        fallback: MemoryRecallFallback?,
        limit: Int,
        omitted: inout [MemoryRecallOmission]
    ) -> [FusedRecallCandidate] {
        var byId: [String: FusedRecallCandidate] = [:]
        var order: [String] = []

        func merge(_ candidate: FusedRecallCandidate) {
            if let existing = byId[candidate.memory.id] {
                byId[candidate.memory.id] = existing.merging(candidate)
                omitted.append(
                    MemoryRecallOmission(
                        memoryId: candidate.memory.id,
                        reason: .duplicate
                    )
                )
            } else {
                byId[candidate.memory.id] = candidate
                order.append(candidate.memory.id)
            }
        }

        if fallback != .semanticUnavailable, fallback != .noSemanticHit {
            for candidate in semantic {
                merge(FusedRecallCandidate(semantic: candidate))
            }
        }

        for candidate in keyword {
            merge(FusedRecallCandidate(keyword: candidate))
        }

        if fallback != .noSemanticHit || keyword.isEmpty {
            for candidate in recent {
                merge(FusedRecallCandidate(recent: candidate))
            }
        }

        let selectedIds = Array(order.prefix(limit))
        for memoryId in order.dropFirst(limit) {
            omitted.append(
                MemoryRecallOmission(
                    memoryId: memoryId,
                    reason: .limitExceeded
                )
            )
        }
        return selectedIds.compactMap { byId[$0] }
    }

    private func keywordTokens(from query: String) -> [String] {
        let separators = CharacterSet.alphanumerics.inverted
        let tokens = query
            .lowercased()
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 3 }
        return Array(NSOrderedSet(array: tokens)) as? [String] ?? tokens
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

        let storedKey = try apiKeyStore.readKey(endpointId: record.id)
        if storedKey == nil, let legacyKey = record.apiKey?.nilIfBlank {
            try apiKeyStore.saveKey(legacyKey, endpointId: record.id)
            var sanitized = record
            sanitized.apiKey = nil
            try await databaseManager.saveEndpoint(sanitized)
            return try APIEndpointConfig(from: sanitized, model: model, apiKey: legacyKey)
        }

        return try APIEndpointConfig(from: record, model: model, apiKey: storedKey ?? record.apiKey)
    }

    private func callExtractionAPI(
        messages: [MessageRecord],
        characterCard: CharacterCardRecord?,
        existingMemoryHints: [MemoryEntryRecord],
        endpoint: APIEndpointConfig
    ) async throws -> [ExtractedMemory] {
        let extractionInput = makeExtractionInput(
            messages: messages,
            characterCard: characterCard,
            existingMemoryHints: existingMemoryHints
        )
        let userContent: String
        do {
            userContent = try JSONEncoder().encodeExtractionInput(extractionInput)
        } catch {
            logger.warning("Failed to encode structured extraction input; falling back to plain text: \(error.localizedDescription)")
            userContent = messages.map { "\($0.role): \($0.content)" }.joined(separator: "\n")
        }

        let systemPrompt = """
            You are a memory extraction assistant. Analyze the provided conversation \
            and extract key memories. Return a JSON array with the following structure:

            [
              {
                "content": "Brief description of the memory",
                "type": "event|fact|relationship|summary",
                "importance": 0-100,
                "sourceStartSortOrder": 12,
                "sourceEndSortOrder": 13,
                "sourceMessageIds": ["msg-id-1"],
                "confidence": 0.8,
                "tags": ["relationship"],
                "dedupeKey": "normalized-short-key",
                "action": "insert|reinforce|skip"
              }
            ]

            Rules:
            - Extract important events, facts about the user, relationship changes, and conversation summaries.
            - importance: 90-100 for critical plot points, 50-70 for general events, 30-50 for minor details.
            - Keep each memory concise (1-2 sentences).
            - sourceStartSortOrder and sourceEndSortOrder must be within the provided message sortOrder range.
            - sourceMessageIds must be a subset of the provided message ids.
            - confidence is your own confidence in this extraction (0.0-1.0).
            - tags should be short categorical labels (e.g., "relationship", "combat", "location").
            - dedupeKey should be a normalized short key for deduplication.
            - action "skip" if this memory is redundant or already covered by existingMemoryHints.
            - action "reinforce" if this memory strengthens an existing hint.
            - action "insert" for genuinely new memories.
            - Return ONLY the JSON array, no other text.
            """

        let apiMessages = [
            ChatMessage(role: "system", content: systemPrompt),
            ChatMessage(role: "user", content: userContent),
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

    private func makeExtractionInput(
        messages: [MessageRecord],
        characterCard: CharacterCardRecord?,
        existingMemoryHints: [MemoryEntryRecord]
    ) -> MemoryExtractionInput {
        MemoryExtractionInput(
            character: characterCard.map {
                MemoryExtractionInput.Character(
                    id: $0.id,
                    name: $0.name,
                    summary: [$0.personality, $0.backstory, $0.scenario].compactMap { $0 }.joined(separator: " ")
                )
            },
            existingMemoryHints: existingMemoryHints.map {
                MemoryExtractionInput.ExistingMemoryHint(
                    id: $0.id,
                    content: $0.content,
                    type: $0.memoryTypeValue.rawValue
                )
            },
            messages: messages.map {
                MemoryExtractionInput.Message(
                    id: $0.id,
                    sortOrder: $0.sortOrder,
                    role: $0.role,
                    content: $0.content
                )
            }
        )
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

enum MemoryExtractionAction: String, Sendable {
    case insert
    case reinforce
    case skip
}

struct ExtractedMemory: Sendable {
    let content: String
    let type: String
    let importance: RawImportance

    // v2 fields
    let sourceStartSortOrder: Int?
    let sourceEndSortOrder: Int?
    let sourceMessageIds: [String]
    let confidence: Double?
    let tags: [String]
    let dedupeKey: String?
    let action: MemoryExtractionAction?

    var resolvedType: MemoryType {
        MemoryType(rawValue: type.lowercased()) ?? .event
    }

    var resolvedImportance: Int {
        importance.value.clamped(to: 0...100)
    }

    var normalizedDedupeKey: String? {
        let rawKey = dedupeKey?.nilIfBlank ?? content
        let normalized = rawKey
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    func withSourceMessageIds(_ ids: [String]) -> ExtractedMemory {
        ExtractedMemory(
            content: content,
            type: type,
            importance: importance,
            sourceStartSortOrder: sourceStartSortOrder,
            sourceEndSortOrder: sourceEndSortOrder,
            sourceMessageIds: ids,
            confidence: confidence,
            tags: tags,
            dedupeKey: dedupeKey,
            action: action
        )
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
        case sourceStartSortOrder
        case sourceEndSortOrder
        case sourceMessageIds
        case confidence
        case tags
        case dedupeKey
        case action
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
        sourceStartSortOrder = try? container.decode(Int.self, forKey: .sourceStartSortOrder)
        sourceEndSortOrder = try? container.decode(Int.self, forKey: .sourceEndSortOrder)
        sourceMessageIds = (try? container.decode([String].self, forKey: .sourceMessageIds)) ?? []
        confidence = try? container.decode(Double.self, forKey: .confidence)
        tags = (try? container.decode([String].self, forKey: .tags)) ?? []
        dedupeKey = try? container.decode(String.self, forKey: .dedupeKey)
        action = (try? container.decode(String.self, forKey: .action)).flatMap(MemoryExtractionAction.init(rawValue:))
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

private struct SemanticRecallCandidate {
    let memory: MemoryEntryRecord
    let rank: Int
    let distance: Float
}

private struct KeywordRecallCandidate {
    let memory: MemoryEntryRecord
    let rank: Int
}

private struct RecentRecallCandidate {
    let memory: MemoryEntryRecord
    let rank: Int
}

private struct KeywordRanking {
    let memory: MemoryEntryRecord
    let matchCount: Int
    let firstMatch: Int
}

private struct FusedRecallCandidate {
    let memory: MemoryEntryRecord
    let semanticRank: Int?
    let semanticDistance: Float?
    let keywordRank: Int?
    let recencyRank: Int?
    let reasons: [MemoryRecallReason]

    init(semantic candidate: SemanticRecallCandidate) {
        memory = candidate.memory
        semanticRank = candidate.rank
        semanticDistance = candidate.distance
        keywordRank = nil
        recencyRank = nil
        reasons = [.semantic]
    }

    init(keyword candidate: KeywordRecallCandidate) {
        memory = candidate.memory
        semanticRank = nil
        semanticDistance = nil
        keywordRank = candidate.rank
        recencyRank = nil
        reasons = [.keyword]
    }

    init(recent candidate: RecentRecallCandidate) {
        memory = candidate.memory
        semanticRank = nil
        semanticDistance = nil
        keywordRank = nil
        recencyRank = candidate.rank
        reasons = [.recentHighValue]
    }

    private init(
        memory: MemoryEntryRecord,
        semanticRank: Int?,
        semanticDistance: Float?,
        keywordRank: Int?,
        recencyRank: Int?,
        reasons: [MemoryRecallReason]
    ) {
        self.memory = memory
        self.semanticRank = semanticRank
        self.semanticDistance = semanticDistance
        self.keywordRank = keywordRank
        self.recencyRank = recencyRank
        self.reasons = reasons
    }

    func merging(_ other: FusedRecallCandidate) -> FusedRecallCandidate {
        let mergedReasons = reasons + other.reasons.filter { !reasons.contains($0) }
        return FusedRecallCandidate(
            memory: memory,
            semanticRank: semanticRank ?? other.semanticRank,
            semanticDistance: semanticDistance ?? other.semanticDistance,
            keywordRank: keywordRank ?? other.keywordRank,
            recencyRank: recencyRank ?? other.recencyRank,
            reasons: mergedReasons
        )
    }
}


// MARK: - Extraction Helpers

private extension MemoryManager {
    func fetchExistingMemoryHints(characterCardId: String) async throws -> [MemoryEntryRecord] {
        try await databaseManager.fetchRecentHighValueMemories(
            characterCardId: characterCardId,
            limit: 5
        )
    }

    func validateAndFilter(
        extracted: [ExtractedMemory],
        messageBatch: [MessageRecord]
    ) -> [ExtractedMemory] {
        let validSortOrders = Set(messageBatch.map(\.sortOrder))
        let validMessageIds = Set(messageBatch.map(\.id))
        let minSortOrder = validSortOrders.min() ?? 0
        let maxSortOrder = validSortOrders.max() ?? Int.max

        return extracted.filter { memory in
            // First version does not mutate or reinforce existing memories.
            if memory.action == .skip || memory.action == .reinforce {
                return false
            }

            if memory.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return false
            }

            // Validate source range if present
            if let start = memory.sourceStartSortOrder {
                guard start >= minSortOrder && start <= maxSortOrder else {
                    logger.warning("Discarding memory with out-of-range sourceStartSortOrder \(start) (valid: \(minSortOrder)...\(maxSortOrder))")
                    return false
                }
            }
            if let end = memory.sourceEndSortOrder {
                guard end >= minSortOrder && end <= maxSortOrder else {
                    logger.warning("Discarding memory with out-of-range sourceEndSortOrder \(end) (valid: \(minSortOrder)...\(maxSortOrder))")
                    return false
                }
            }
            if let start = memory.sourceStartSortOrder,
               let end = memory.sourceEndSortOrder,
               start > end {
                logger.warning("Discarding memory with inverted source sortOrder range \(start)...\(end)")
                return false
            }

            return true
        }.map { memory in
            let validIds = memory.sourceMessageIds.filter { validMessageIds.contains($0) }
            if validIds.count != memory.sourceMessageIds.count {
                let invalidIds = memory.sourceMessageIds.filter { !validMessageIds.contains($0) }
                logger.warning("Dropping invalid sourceMessageIds from memory provenance: \(invalidIds)")
            }
            return memory.withSourceMessageIds(orderedUnique(validIds))
        }
    }

    func dedupeWithinBatch(_ memories: [ExtractedMemory]) -> [ExtractedMemory] {
        var byKey: [String: ExtractedMemory] = [:]
        for memory in memories {
            guard let key = memory.normalizedDedupeKey else {
                // No dedupe key: keep as-is
                continue
            }
            if let existing = byKey[key] {
                let keepNew: Bool
                if memory.resolvedImportance != existing.resolvedImportance {
                    keepNew = memory.resolvedImportance > existing.resolvedImportance
                } else {
                    keepNew = memory.content.count < existing.content.count
                }
                if keepNew {
                    byKey[key] = memory
                }
            } else {
                byKey[key] = memory
            }
        }
        // Rebuild order: first pass keeps deduped items in original order,
        // second pass appends items without dedupe keys.
        let dedupedKeys = Set(byKey.keys)
        var result: [ExtractedMemory] = []
        var seenKeys = Set<String>()
        for memory in memories {
            if let key = memory.normalizedDedupeKey, dedupedKeys.contains(key) {
                if !seenKeys.contains(key) {
                    seenKeys.insert(key)
                    result.append(byKey[key]!)
                }
            } else if memory.normalizedDedupeKey == nil {
                result.append(memory)
            }
        }
        return result
    }

    func makeProvenance(
        memoryEntryId: String,
        extracted: ExtractedMemory,
        modelName: String,
        promptVersion: String,
        now: Date
    ) -> MemoryEntryProvenanceRecord {
        let clampedConfidence = extracted.confidence.map { max(0.0, min(1.0, $0)) }
        let cleanedTags = Array(orderedUnique(
            extracted.tags
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        ).prefix(10))

        return MemoryEntryProvenanceRecord(
            memoryEntryId: memoryEntryId,
            sourceStartSortOrder: extracted.sourceStartSortOrder,
            sourceEndSortOrder: extracted.sourceEndSortOrder,
            sourceMessageIds: extracted.sourceMessageIds.isEmpty ? nil : Array(extracted.sourceMessageIds),
            extractionModel: modelName,
            extractionPromptVersion: promptVersion,
            confidence: clampedConfidence,
            dedupeKey: extracted.normalizedDedupeKey,
            tags: cleanedTags.isEmpty ? nil : Array(cleanedTags),
            createdAt: now,
            updatedAt: now
        )
    }

    func orderedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let key = value.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(value)
        }
        return result
    }
}

// MARK: - Structured Extraction Input

struct MemoryExtractionInput: Codable, Sendable {
    let character: Character?
    let existingMemoryHints: [ExistingMemoryHint]
    let messages: [Message]

    struct Character: Codable, Sendable {
        let id: String
        let name: String
        let summary: String
    }

    struct ExistingMemoryHint: Codable, Sendable {
        let id: String
        let content: String
        let type: String
    }

    struct Message: Codable, Sendable {
        let id: String
        let sortOrder: Int
        let role: String
        let content: String
    }
}

private extension JSONEncoder {
    func encodeExtractionInput(_ input: MemoryExtractionInput) throws -> String {
        let data = try encode(input)
        guard let string = String(data: data, encoding: .utf8) else {
            throw MemoryError.extractionFailed(reason: "Failed to encode extraction input as UTF-8")
        }
        return string
    }
}
