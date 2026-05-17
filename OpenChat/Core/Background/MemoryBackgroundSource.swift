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
        guard let characterCardId = request.characterCard?.id ?? request.conversation.characterCardId else {
            return []
        }
        let result = try await recall(
            characterCardId,
            request.currentInput,
            max(request.memoryLimit, 0)
        )
        return Self.candidates(from: result)
    }

    static func candidates(from result: MemoryRecallResult) -> [BackgroundCandidate] {
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
                metadata: makeMetadata(entry: entry, trace: result.trace)
            )
        }
    }

    private static func makeMetadata(
        entry: MemoryRecallEntry,
        trace: MemoryRecallTrace
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
        return metadata
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
