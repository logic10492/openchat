import Foundation

struct WorldBookBackgroundSource: BackgroundSource {
    typealias Recall = @Sendable (
        _ worldBook: WorldBookRecord?,
        _ entries: [WorldBookEntryRecord],
        _ recentMessages: [MessageRecord],
        _ currentInput: String,
        _ limit: Int
    ) async throws -> WorldBookRecallResult

    let sourceType: BackgroundSourceType = .worldBook

    private let recall: Recall

    init(recall: @escaping Recall) {
        self.recall = recall
    }

    init(tool: WorldBookRecallTool) {
        self.recall = { worldBook, entries, recentMessages, currentInput, limit in
            try await tool.call(
                WorldBookRecallToolInput(
                    worldBook: worldBook,
                    entries: entries,
                    recentMessages: recentMessages,
                    currentInput: currentInput,
                    limit: limit
                )
            )
        }
    }

    func candidates(for request: BackgroundRequest) async throws -> [BackgroundCandidate] {
        let result = try await recall(
            request.worldBook,
            request.worldBookEntries,
            request.recentMessages,
            request.currentInput,
            max(request.worldBookLimit, 0)
        )
        return Self.candidates(from: result)
    }

    static func candidates(from result: WorldBookRecallResult) -> [BackgroundCandidate] {
        result.entries.map { entry in
            let record = entry.entry
            return BackgroundCandidate(
                id: "worldBook:\(record.id)",
                sourceType: .worldBook,
                sourceId: record.id,
                content: record.content,
                title: record.title,
                basePriority: record.priority,
                relevance: relevance(semanticRank: entry.semanticRank, semanticDistance: entry.semanticDistance),
                recency: record.updatedAt,
                metadata: makeMetadata(entry: entry, trace: result.trace)
            )
        }
    }

    private static func makeMetadata(
        entry: WorldBookRecallEntry,
        trace: WorldBookRecallTrace
    ) -> [String: String] {
        var metadata: [String: String] = [
            "sourceTable": WorldBookEntryRecord.databaseTableName,
            "sourceId": entry.entry.id,
            "worldBookId": entry.entry.worldBookId,
            "priority": String(entry.entry.priority),
            "finalRank": String(entry.finalRank),
            "keywordHits": entry.keywordHits.joined(separator: ","),
            "reasons": entry.reasons.map(\.rawValue).joined(separator: ","),
            "querySummary": trace.querySummary,
            "keywordCandidateCount": String(trace.keywordCandidateCount),
            "semanticCandidateCount": String(trace.semanticCandidateCount),
            "selectedIds": trace.selectedIds.joined(separator: ","),
            "omittedIds": trace.omissions.compactMap(\.entryId).joined(separator: ","),
            "omissionReasons": trace.omissions.map(\.reason.rawValue).joined(separator: ","),
            "omissionDetails": trace.omissions.compactMap(\.detail).joined(separator: "\n"),
        ]
        metadata["keywordRank"] = entry.keywordRank.map(String.init)
        metadata["semanticRank"] = entry.semanticRank.map(String.init)
        metadata["semanticDistance"] = entry.semanticDistance.map { String($0) }
        metadata["sourceUpdatedAt"] = String(entry.entry.updatedAt.timeIntervalSince1970)
        if trace.omissions.contains(where: { $0.reason == .semanticUnavailable }) {
            metadata["fallback"] = WorldBookRecallOmissionReason.semanticUnavailable.rawValue
        }
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
