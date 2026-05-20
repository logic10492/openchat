import Foundation

struct MemoryBackgroundSource: BackgroundSource {
    typealias Recall = @Sendable (
        _ characterCardId: String,
        _ query: String,
        _ limit: Int
    ) async throws -> MemoryRecallResult

    let sourceType: BackgroundSourceType = .memory

    private let recall: Recall

    init(recall: @escaping Recall) {
        self.recall = recall
    }

    init(tool: MemoryRecallTool) {
        self.recall = { characterCardId, query, limit in
            try await tool.call(
                MemoryRecallToolInput(
                    characterCardId: characterCardId,
                    query: query,
                    limit: limit
                )
            )
        }
    }

    func candidates(for request: BackgroundRequest) async throws -> [BackgroundCandidate] {
        let characterCardIds = Self.characterCardIds(for: request)
        guard !characterCardIds.isEmpty else {
            return []
        }
        let query = Self.enrichedQuery(for: request)
        var candidates: [BackgroundCandidate] = []
        for characterCardId in characterCardIds {
            let result = try await recall(
                characterCardId,
                query,
                max(request.memoryLimit, 0)
            )
            candidates.append(
                contentsOf: Self.candidates(
                    from: result,
                    stageContext: request.stageContext,
                    characterCardId: characterCardId
                )
            )
        }
        return candidates
    }

    static func candidates(
        from result: MemoryRecallResult,
        stageContext: StageBackgroundContext? = nil,
        characterCardId: String? = nil
    ) -> [BackgroundCandidate] {
        result.entries.map { entry in
            let memory = entry.memory
            return BackgroundCandidate(
                id: "memory:\(memory.id)",
                sourceType: .memory,
                sourceId: memory.id,
                content: memory.content,
                title: memory.memoryType,
                basePriority: memory.importance,
                relevance: relevance(semanticRank: entry.semanticRank, semanticDistance: entry.semanticDistance),
                recency: memory.updatedAt,
                metadata: makeMetadata(
                    entry: entry,
                    trace: result.trace,
                    stageContext: stageContext,
                    characterCardId: characterCardId
                )
            )
        }
    }

    private static func makeMetadata(
        entry: MemoryRecallEntry,
        trace: MemoryRecallTrace,
        stageContext: StageBackgroundContext?,
        characterCardId: String?
    ) -> [String: String] {
        var metadata: [String: String] = [
            "sourceTable": MemoryEntryRecord.databaseTableName,
            "sourceId": entry.memory.id,
            "memoryType": entry.memory.memoryType,
            "importance": String(entry.memory.importance),
            "finalRank": String(entry.finalRank),
            "reasons": entry.reasons.map(\.rawValue).joined(separator: ","),
            "query": trace.query,
            "semanticCandidateCount": String(trace.semanticCandidateCount),
            "keywordCandidateCount": String(trace.keywordCandidateCount),
            "recentCandidateCount": String(trace.recentCandidateCount),
            "selectedIds": trace.selectedIds.joined(separator: ","),
            "omittedIds": trace.omitted.map(\.memoryId).joined(separator: ","),
            "omissionReasons": trace.omitted.map(\.reason.rawValue).joined(separator: ","),
        ]
        metadata["fallback"] = trace.fallback?.rawValue
        metadata["semanticRank"] = entry.semanticRank.map(String.init)
        metadata["semanticDistance"] = entry.semanticDistance.map { String($0) }
        metadata["keywordRank"] = entry.keywordRank.map(String.init)
        metadata["recencyRank"] = entry.recencyRank.map(String.init)
        metadata["sourceUpdatedAt"] = String(entry.memory.updatedAt.timeIntervalSince1970)
        metadata["stageId"] = stageContext?.stageId
        metadata["stageCharacterCardId"] = characterCardId
        metadata["stageActiveSpeakerId"] = stageContext?.activeSpeaker?.id
        metadata["stageParticipantIds"] = stageContext?.activeParticipants.map(\.id).joined(separator: ",")
        return metadata
    }

    private static func characterCardIds(for request: BackgroundRequest) -> [String] {
        if let ids = request.stageContext?.activeCharacterCardIds, !ids.isEmpty {
            return ids
        }
        guard let id = request.characterCard?.id ?? request.conversation.characterCardId else {
            return []
        }
        return [id]
    }

    private static func enrichedQuery(for request: BackgroundRequest) -> String {
        guard let stageQuery = request.stageContext?.queryText,
              !stageQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return request.currentInput
        }
        return [request.currentInput, stageQuery]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")
    }

    private static func relevance(
        semanticRank: Int?,
        semanticDistance: Float?
    ) -> Double? {
        if let semanticRank, semanticRank > 0 {
            return 1 / Double(semanticRank)
        }
        if let semanticDistance {
            return max(0, 1 - Double(semanticDistance))
        }
        return nil
    }
}
