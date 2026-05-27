import Foundation
import Testing

@testable import OpenChat

struct MessageWindowPaginationTests {
    @Test func test_fetchRecentMessages_returnsLatestWindowInAscendingSortOrder() async throws {
        let database = try TestHelpers.makeDatabaseManager()
        let conversation = TestHelpers.makeConversation(id: "window-recent")
        try await database.saveConversation(conversation)
        try await insertMessages(database: database, conversationId: conversation.id, count: 10)

        let records = try await database.fetchRecentMessages(conversationId: conversation.id, limit: 4)

        #expect(records.map(\.sortOrder) == [6, 7, 8, 9])
        #expect(records.map(\.content) == ["message-6", "message-7", "message-8", "message-9"])
    }

    @Test func test_fetchMessagesBeforeSortOrder_returnsEarlierPageInAscendingSortOrder() async throws {
        let database = try TestHelpers.makeDatabaseManager()
        let conversation = TestHelpers.makeConversation(id: "window-before")
        try await database.saveConversation(conversation)
        try await insertMessages(database: database, conversationId: conversation.id, count: 12)

        let records = try await database.fetchMessages(
            conversationId: conversation.id,
            beforeSortOrder: 7,
            limit: 3
        )

        #expect(records.map(\.sortOrder) == [4, 5, 6])
    }

    @Test func test_fetchWindowMessages_zeroLimitReturnsEmptyPage() async throws {
        let database = try TestHelpers.makeDatabaseManager()
        let conversation = TestHelpers.makeConversation(id: "window-empty")
        try await database.saveConversation(conversation)
        try await insertMessages(database: database, conversationId: conversation.id, count: 3)

        let recent = try await database.fetchRecentMessages(conversationId: conversation.id, limit: 0)
        let earlier = try await database.fetchMessages(conversationId: conversation.id, beforeSortOrder: 2, limit: 0)

        #expect(recent.isEmpty)
        #expect(earlier.isEmpty)
    }

    private func insertMessages(database: DatabaseManager, conversationId: String, count: Int) async throws {
        for index in 0..<count {
            try await database.saveMessage(
                MessageRecord(
                    id: "message-\(index)",
                    conversationId: conversationId,
                    role: index.isMultiple(of: 2) ? "user" : "assistant",
                    content: "message-\(index)",
                    tokenCount: 1,
                    isCompressed: false,
                    originalContent: nil,
                    sortOrder: index,
                    createdAt: Date(timeIntervalSince1970: Double(index)),
                    reasoningContent: nil
                )
            )
        }
    }
}
