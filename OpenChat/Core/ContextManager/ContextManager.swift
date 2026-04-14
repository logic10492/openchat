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
        let totalBudget = max(Int((Double(endpoint.maxContextTokens) * 0.4).rounded(.down)), 1)
        let historyBudget = max(totalBudget - fixedTokens, 0)

        switch conversation.contextStrategyValue {
        case .truncation:
            return try await TruncationStrategy().process(allMessages: allMessages, tokenBudget: historyBudget)
        case .compression:
            do {
                return try await CompressionStrategy(apiClient: apiClient, endpoint: endpoint).process(
                    allMessages: allMessages,
                    tokenBudget: historyBudget
                )
            } catch {
                return try await TruncationStrategy().process(allMessages: allMessages, tokenBudget: historyBudget)
            }
        }
    }
}
