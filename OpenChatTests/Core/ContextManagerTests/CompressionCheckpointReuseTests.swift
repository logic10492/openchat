import Foundation
import GRDB
import Testing

@testable import OpenChat

@Suite("ContextManager checkpoint compression")
struct CompressionCheckpointReuseTests {
    @Test func test_prepareHistory_usesCheckpointAndMessagesAfterCheckpoint() async throws {
        let db = try TestHelpers.makeDatabaseManager()
        let conversation = TestHelpers.makeConversation(id: "conv-context", contextStrategy: .compression)
        let old = [
            TestHelpers.makeMessage(conversationId: conversation.id, role: "user", content: "old", sortOrder: 1),
            TestHelpers.makeMessage(conversationId: conversation.id, role: "assistant", content: "old reply", sortOrder: 2)
        ]
        let checkpoint = TestHelpers.makeCompressionCheckpoint(
            conversationId: conversation.id,
            sourceStartSortOrder: 1,
            sourceEndSortOrder: 2,
            sourceHash: CompressionSourceHasher.hash(messages: old),
            summary: "stable summary"
        )
        let recent = TestHelpers.makeMessage(conversationId: conversation.id, role: "user", content: "recent", sortOrder: 3)
        try await db.write { database in
            try conversation.insert(database)
            for message in old { try message.insert(database) }
            try recent.insert(database)
            try checkpoint.insert(database)
        }

        let session = MockURLProtocol.makeSession { _ in
            throw APIError.networkError(underlying: URLError(.badServerResponse))
        }
        let contextManager = ContextManager(databaseManager: db, apiClient: APIClient(session: session))

        let history = try await contextManager.prepareHistory(
            messages: old + [recent],
            conversation: conversation,
            endpoint: TestHelpers.makeEndpoint(maxContextTokens: 4096),
            fixedTokens: 10
        )

        #expect(history.map(\.content) == ["[Previously]\nstable summary", "recent"])
    }

    @Test func test_prepareHistory_fallsBackToTruncation_withoutSavingCheckpoint_whenCompressionFails() async throws {
        let db = try TestHelpers.makeDatabaseManager()
        let conversation = TestHelpers.makeConversation(id: "conv-fallback", contextStrategy: .compression)
        let messages = (1...8).map {
            TestHelpers.makeMessage(
                conversationId: conversation.id,
                role: $0.isMultiple(of: 2) ? "assistant" : "user",
                content: String(repeating: "long \($0) ", count: 100),
                sortOrder: $0
            )
        }
        try await db.write { database in
            try conversation.insert(database)
            for message in messages { try message.insert(database) }
        }

        let session = MockURLProtocol.makeSession { _ in
            throw APIError.networkError(underlying: URLError(.cannotConnectToHost))
        }
        let contextManager = ContextManager(databaseManager: db, apiClient: APIClient(session: session))

        let history = try await contextManager.prepareHistory(
            messages: messages,
            conversation: conversation,
            endpoint: TestHelpers.makeEndpoint(maxContextTokens: 900),
            fixedTokens: 10
        )

        let checkpoints = try await db.fetchCompressionCheckpoints(conversationId: conversation.id)
        #expect(checkpoints.isEmpty)
        #expect(history.count >= 1)
        #expect(history.last?.sortOrder == 8)
    }
}
