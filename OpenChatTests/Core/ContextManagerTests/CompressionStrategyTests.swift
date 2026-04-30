import Foundation
import Testing

@testable import OpenChat

@Suite("Legacy compression strategy")
struct CompressionStrategyTests {
    @Test func test_contextManager_compressionUsesCheckpointPath() async throws {
        let db = try TestHelpers.makeDatabaseManager()
        let conversation = TestHelpers.makeConversation(id: "legacy-path", contextStrategy: .compression)
        try await db.write { database in
            try conversation.insert(database)
        }
        let contextManager = ContextManager(databaseManager: db, apiClient: APIClient())
        let history = try await contextManager.prepareHistory(
            messages: [],
            conversation: conversation,
            endpoint: TestHelpers.makeEndpoint(),
            fixedTokens: 0
        )
        #expect(history.isEmpty)
    }
}
