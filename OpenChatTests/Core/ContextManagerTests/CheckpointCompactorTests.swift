import Foundation
import GRDB
import Testing

@testable import OpenChat

@Suite("Checkpoint compactor")
struct CheckpointCompactorTests {
    @Test func test_prepare_doesNotCallNetwork_whenBelowThreshold() async throws {
        let db = try TestHelpers.makeDatabaseManager()
        let conversation = TestHelpers.makeConversation(id: "conv-below", contextStrategy: .compression)
        let messages = [
            TestHelpers.makeMessage(conversationId: conversation.id, role: "user", content: "short", sortOrder: 1)
        ]
        try await db.write { database in
            try conversation.insert(database)
            for message in messages { try message.insert(database) }
        }

        let session = MockURLProtocol.makeSession { _ in
            throw APIError.networkError(underlying: URLError(.badServerResponse))
        }
        let compactor = CheckpointCompactor(
            databaseManager: db,
            apiClient: APIClient(session: session)
        )

        let prepared = try await compactor.prepare(
            allMessages: messages,
            conversation: conversation,
            endpoint: TestHelpers.makeEndpoint(maxContextTokens: 4096),
            fixedTokens: 10
        )

        #expect(prepared.compressedContext == nil)
        #expect(prepared.messageHistory.map(\.content) == ["short"])
        #expect(!prepared.didCreateCheckpoint)
    }

    @Test func test_prepare_createsCheckpoint_whenAboveThreshold() async throws {
        let db = try TestHelpers.makeDatabaseManager()
        let conversation = TestHelpers.makeConversation(id: "conv-create", contextStrategy: .compression)
        let messages = (1...8).map {
            TestHelpers.makeMessage(
                conversationId: conversation.id,
                role: $0.isMultiple(of: 2) ? "assistant" : "user",
                content: String(repeating: "long message \($0) ", count: 80),
                sortOrder: $0
            )
        }
        try await db.write { database in
            try conversation.insert(database)
            for message in messages { try message.insert(database) }
        }

        let responseBody = #"{"id":"1","choices":[{"index":0,"message":{"role":"assistant","content":"compressed summary"},"finish_reason":"stop"}]}"#
        let session = MockURLProtocol.makeSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(responseBody.utf8))
        }
        let compactor = CheckpointCompactor(
            databaseManager: db,
            apiClient: APIClient(session: session)
        )

        let prepared = try await compactor.prepare(
            allMessages: messages,
            conversation: conversation,
            endpoint: TestHelpers.makeEndpoint(maxContextTokens: 900),
            fixedTokens: 10
        )

        #expect(prepared.compressedContext?.summary == "compressed summary")
        #expect(prepared.didCreateCheckpoint)
        #expect(prepared.messageHistory.allSatisfy { $0.sortOrder > (prepared.compressedContext?.sourceEndSortOrder ?? 0) })

        let saved = try await db.fetchLatestCompressionCheckpoint(conversationId: conversation.id)
        #expect(saved?.summary == "compressed summary")
    }

    @Test func test_prepare_reusesExistingCheckpoint_withoutNetworkCall() async throws {
        let db = try TestHelpers.makeDatabaseManager()
        let conversation = TestHelpers.makeConversation(id: "conv-reuse", contextStrategy: .compression)
        let oldMessages = [
            TestHelpers.makeMessage(conversationId: conversation.id, role: "user", content: "old", sortOrder: 1),
            TestHelpers.makeMessage(conversationId: conversation.id, role: "assistant", content: "old reply", sortOrder: 2)
        ]
        let sourceHash = CompressionSourceHasher.hash(messages: oldMessages)
        let checkpoint = TestHelpers.makeCompressionCheckpoint(
            conversationId: conversation.id,
            sourceStartSortOrder: 1,
            sourceEndSortOrder: 2,
            sourceHash: sourceHash,
            summary: "stable summary"
        )
        let recent = TestHelpers.makeMessage(conversationId: conversation.id, role: "user", content: "recent", sortOrder: 3)
        try await db.write { database in
            try conversation.insert(database)
            for message in oldMessages { try message.insert(database) }
            try recent.insert(database)
            try checkpoint.insert(database)
        }

        let session = MockURLProtocol.makeSession { _ in
            throw APIError.networkError(underlying: URLError(.badServerResponse))
        }
        let compactor = CheckpointCompactor(databaseManager: db, apiClient: APIClient(session: session))

        let prepared = try await compactor.prepare(
            allMessages: oldMessages + [recent],
            conversation: conversation,
            endpoint: TestHelpers.makeEndpoint(maxContextTokens: 4096),
            fixedTokens: 10
        )

        #expect(prepared.compressedContext?.summary == "stable summary")
        #expect(prepared.messageHistory.map(\.content) == ["recent"])
        #expect(!prepared.didCreateCheckpoint)
    }
}
