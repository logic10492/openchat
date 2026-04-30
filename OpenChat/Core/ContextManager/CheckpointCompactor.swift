import Foundation

struct CheckpointCompactor: Sendable {
    let databaseManager: DatabaseManager
    let apiClient: APIClient

    func prepare(
        allMessages: [MessageRecord],
        conversation: ConversationRecord,
        endpoint: APIEndpointConfig,
        fixedTokens: Int
    ) async throws -> PreparedHistory {
        let policy = CompressionPolicy(
            endpoint: endpoint,
            compressionMode: conversation.compressionModeValue
        )
        let checkpoints = try await databaseManager.fetchCompressionCheckpoints(conversationId: conversation.id)
        let latestCheckpoint = latestValidCheckpoint(
            checkpoints: checkpoints,
            policy: policy,
            allMessages: allMessages
        )
        let checkpointEnd = latestCheckpoint?.sourceEndSortOrder ?? 0
        let messagesAfterCheckpoint = allMessages.filter { $0.sortOrder > checkpointEnd }
        let activeTokens = fixedTokens
            + (latestCheckpoint?.summaryTokenCount ?? 0)
            + messagesAfterCheckpoint.reduce(0) { $0 + TokenCounter.count(message: $1) }

        guard activeTokens > policy.autoCompactTokenLimit else {
            return PreparedHistory(
                compressedContext: latestCheckpoint,
                messageHistory: messagesAfterCheckpoint,
                didCreateCheckpoint: false,
                didFallbackToTruncation: false
            )
        }

        let historyBudget = policy.historyBudget(fixedTokens: fixedTokens)
        let recentBudget = max(Int(Double(historyBudget) * 0.7), 1)
        let recentMessages = selectRecentMessages(from: messagesAfterCheckpoint, budget: recentBudget)
        let recentStartSortOrder = recentMessages.first?.sortOrder ?? Int.max
        let messagesToCompress = messagesAfterCheckpoint.filter { $0.sortOrder < recentStartSortOrder }

        guard let firstSource = messagesToCompress.first,
              let lastSource = messagesToCompress.last,
              messagesToCompress.count > 1
        else {
            let truncated = try await TruncationStrategy().process(
                allMessages: messagesAfterCheckpoint,
                tokenBudget: historyBudget
            )
            return PreparedHistory(
                compressedContext: latestCheckpoint,
                messageHistory: truncated,
                didCreateCheckpoint: false,
                didFallbackToTruncation: true
            )
        }

        let recentTokens = recentMessages.reduce(0) { $0 + TokenCounter.count(message: $1) }
        let maxSummaryTokens = max(historyBudget - recentTokens, 128)
        let summary = try await CompressionSummarizer(apiClient: apiClient, endpoint: endpoint).summarize(
            previousSummary: latestCheckpoint?.summary,
            messages: messagesToCompress,
            maxTokens: maxSummaryTokens
        )
        let sourceHash = CompressionSourceHasher.hash(
            previousSourceHash: latestCheckpoint?.sourceHash,
            messages: messagesToCompress
        )
        let checkpoint = CompressionCheckpointRecord(
            id: UUID().uuidString,
            conversationId: conversation.id,
            parentCheckpointId: latestCheckpoint?.id,
            sourceStartSortOrder: latestCheckpoint?.sourceStartSortOrder ?? firstSource.sortOrder,
            sourceEndSortOrder: lastSource.sortOrder,
            sourceHash: sourceHash,
            summary: summary,
            summaryTokenCount: TokenCounter.count(summary),
            endpointId: conversation.apiEndpointId,
            modelName: endpoint.modelName,
            modelMaxContextTokens: endpoint.maxContextTokens,
            effectiveCompactWindowTokens: policy.effectiveCompactWindowTokens,
            autoCompactTokenLimit: policy.autoCompactTokenLimit,
            createdAt: .now
        )
        try await databaseManager.saveCompressionCheckpoint(checkpoint)

        return PreparedHistory(
            compressedContext: checkpoint,
            messageHistory: allMessages.filter { $0.sortOrder > checkpoint.sourceEndSortOrder },
            didCreateCheckpoint: true,
            didFallbackToTruncation: false
        )
    }

    private func latestValidCheckpoint(
        checkpoints: [CompressionCheckpointRecord],
        policy: CompressionPolicy,
        allMessages: [MessageRecord]
    ) -> CompressionCheckpointRecord? {
        let byID = Dictionary(uniqueKeysWithValues: checkpoints.map { ($0.id, $0) })
        return checkpoints
            .sorted { lhs, rhs in
                if lhs.sourceEndSortOrder == rhs.sourceEndSortOrder {
                    return lhs.createdAt > rhs.createdAt
                }
                return lhs.sourceEndSortOrder > rhs.sourceEndSortOrder
            }
            .first {
                $0.effectiveCompactWindowTokens == policy.effectiveCompactWindowTokens
                    && $0.autoCompactTokenLimit == policy.autoCompactTokenLimit
                    && isValid(checkpoint: $0, byID: byID, allMessages: allMessages)
            }
    }

    private func isValid(
        checkpoint: CompressionCheckpointRecord,
        byID: [String: CompressionCheckpointRecord],
        allMessages: [MessageRecord]
    ) -> Bool {
        if let parentID = checkpoint.parentCheckpointId {
            guard let parent = byID[parentID],
                  isValid(checkpoint: parent, byID: byID, allMessages: allMessages)
            else {
                return false
            }
            let deltaMessages = allMessages.filter {
                $0.sortOrder > parent.sourceEndSortOrder && $0.sortOrder <= checkpoint.sourceEndSortOrder
            }
            guard !deltaMessages.isEmpty else { return false }
            let hash = CompressionSourceHasher.hash(
                previousSourceHash: parent.sourceHash,
                messages: deltaMessages
            )
            return hash == checkpoint.sourceHash
        }

        let covered = allMessages.filter {
            $0.sortOrder >= checkpoint.sourceStartSortOrder && $0.sortOrder <= checkpoint.sourceEndSortOrder
        }
        guard !covered.isEmpty else { return false }
        return CompressionSourceHasher.hash(messages: covered) == checkpoint.sourceHash
    }

    private func selectRecentMessages(from messages: [MessageRecord], budget: Int) -> [MessageRecord] {
        var result: [MessageRecord] = []
        var used = 0
        for message in messages.reversed() {
            let tokens = TokenCounter.count(message: message)
            if used + tokens > budget, !result.isEmpty {
                break
            }
            result.insert(message, at: 0)
            used += tokens
        }
        if result.count < 2 {
            return Array(messages.suffix(2))
        }
        return result
    }
}
