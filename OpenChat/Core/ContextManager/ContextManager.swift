import Foundation
import GRDB

struct ContextManager {
    private let databaseManager: DatabaseManager
    private let apiClient: APIClient

    init(databaseManager: DatabaseManager, apiClient: APIClient) {
        self.databaseManager = databaseManager
        self.apiClient = apiClient
    }

    func prepareHistory(
        conversation: ConversationRecord,
        endpoint: APIEndpointConfig,
        fixedTokens: Int
    ) async throws -> [MessageRecord] {
        let allMessages = try await databaseManager.fetchMessages(conversationId: conversation.id)
        return try await prepareHistory(
            messages: allMessages,
            conversation: conversation,
            endpoint: endpoint,
            fixedTokens: fixedTokens
        )
    }

    func prepareHistory(
        messages allMessages: [MessageRecord],
        conversation: ConversationRecord,
        endpoint: APIEndpointConfig,
        fixedTokens: Int
    ) async throws -> [MessageRecord] {
        let prepared = try await prepareContextHistory(
            messages: allMessages,
            conversation: conversation,
            endpoint: endpoint,
            fixedTokens: fixedTokens
        )
        return prepared.messagesForLegacyPrompt(conversationId: conversation.id)
    }

    func prepareContextHistory(
        messages allMessages: [MessageRecord],
        conversation: ConversationRecord,
        endpoint: APIEndpointConfig,
        fixedTokens: Int
    ) async throws -> PreparedHistory {
        let policy = CompressionPolicy(
            endpoint: endpoint,
            compressionMode: conversation.compressionModeValue
        )
        let historyBudget = policy.historyBudget(fixedTokens: fixedTokens)

        switch conversation.contextStrategyValue {
        case .truncation:
            let history = try await TruncationStrategy().process(
                allMessages: allMessages,
                tokenBudget: historyBudget
            )
            return PreparedHistory(
                compressedContext: nil,
                messageHistory: history,
                didCreateCheckpoint: false,
                didFallbackToTruncation: false
            )
        case .compression:
            do {
                return try await CheckpointCompactor(
                    databaseManager: databaseManager,
                    apiClient: apiClient
                ).prepare(
                    allMessages: allMessages,
                    conversation: conversation,
                    endpoint: endpoint,
                    fixedTokens: fixedTokens
                )
            } catch {
                let history = try await TruncationStrategy().process(
                    allMessages: allMessages,
                    tokenBudget: historyBudget
                )
                return PreparedHistory(
                    compressedContext: nil,
                    messageHistory: history,
                    didCreateCheckpoint: false,
                    didFallbackToTruncation: true
                )
            }
        }
    }
}
